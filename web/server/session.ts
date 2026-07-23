// Port of the DiffSession half of Sources/Git.swift and the MRContext half of
// Sources/GitLab.swift — ties together the comparison the user asked for.
import type {
  ChangedFileJSON,
  FileDiffJSON,
  FileStatusCode,
  MRNoteJSON,
  MRThreadJSON,
  SessionJSON,
} from "../shared/model.ts";
import type { ChangedFile } from "./diff-engine.ts";
import { displayPath, makeFileDiff, statusLetter } from "./diff-engine.ts";
import { Git, GitError } from "./git.ts";
import type { GitLabMR, MRDraft, MRThread, MRClientAPI } from "./gitlab.ts";

const err = (msg: string) => process.stderr.write(`diffy: ${msg}\n`);

function toJSON(file: ChangedFile): ChangedFileJSON {
  return {
    status: statusLetter(file.status) as FileStatusCode,
    oldPath: file.oldPath,
    newPath: file.newPath,
    displayPath: displayPath(file),
  };
}

// MARK: - MR context

export class MRContext {
  readonly client: MRClientAPI;
  readonly mr: GitLabMR;
  threads: MRThread[];
  drafts: MRDraft[];
  members: { username: string; name: string }[] = [];

  constructor(client: MRClientAPI, mr: GitLabMR, threads: MRThread[], drafts: MRDraft[]) {
    this.client = client;
    this.mr = mr;
    this.threads = threads;
    this.drafts = drafts;
  }

  /** Loads project members in the background for @mention autocomplete. */
  loadMembersAsync(): void {
    void this.client.fetchMembers().then((m) => {
      this.members = m;
    });
  }

  async refresh(): Promise<void> {
    try {
      this.threads = await this.client.fetchDiscussions();
    } catch { /* keep stale threads on transient errors */ }
    try {
      this.drafts = await this.client.fetchDraftNotes();
    } catch { /* keep stale drafts */ }
  }

  get draftCount(): number {
    return this.drafts.length;
  }

  private static matches(pos: MRThread["position"] | MRDraft["position"], file: ChangedFile): boolean {
    if (!pos) return false;
    return (
      (file.newPath.length > 0 && pos.newPath === file.newPath) ||
      (file.oldPath.length > 0 && pos.oldPath === file.oldPath)
    );
  }

  /** Threads to display for one file: published threads (with your pending
   *  draft replies appended) plus standalone draft threads. */
  displayThreads(file: ChangedFile): MRThreadJSON[] {
    const result: MRThreadJSON[] = [];
    for (const thread of this.threads) {
      if (!MRContext.matches(thread.position, file)) continue;
      const notes: MRNoteJSON[] = thread.notes.map((n) => ({ ...n }));
      const draftIDs: number[] = [];
      for (const draft of this.drafts) {
        if (draft.discussionID !== thread.id) continue;
        notes.push({
          id: -draft.id,
          author: "You",
          body: draft.note,
          createdAt: "draft",
          system: false,
          isPending: true,
        });
        draftIDs.push(draft.id);
      }
      result.push({
        id: thread.id,
        notes,
        position: thread.position,
        resolved: thread.resolved,
        isDraft: false,
        draftIDs,
      });
    }
    for (const draft of this.drafts) {
      if (draft.discussionID !== null || !MRContext.matches(draft.position, file)) continue;
      result.push({
        id: `draft-${draft.id}`,
        notes: [{
          id: -draft.id,
          author: "You",
          body: draft.note,
          createdAt: "draft",
          system: false,
          isPending: true,
        }],
        position: draft.position,
        resolved: false,
        isDraft: true,
        draftIDs: [draft.id],
      });
    }
    return result;
  }

  /** Every positioned thread paired with the file it belongs to, in file
   *  order — for the all-comments overview. */
  allThreadLocations(files: ChangedFile[]): { fileIndex: number; line: number; thread: MRThreadJSON }[] {
    const result: { fileIndex: number; line: number; thread: MRThreadJSON }[] = [];
    for (let fileIndex = 0; fileIndex < files.length; fileIndex++) {
      for (const thread of this.displayThreads(files[fileIndex]!)) {
        if (!thread.position) continue;
        result.push({
          fileIndex,
          line: thread.position.newLine ?? thread.position.oldLine ?? 0,
          thread,
        });
      }
    }
    return result;
  }
}

// MARK: - Diff session

export class DiffSession {
  readonly git: Git;
  readonly leftRef: string;
  readonly rightRef: string | null;
  leftLabel: string;
  rightLabel: string;
  readonly files: ChangedFile[];
  mr: MRContext | null = null;
  private cache = new Map<number, FileDiffJSON>();

  private constructor(
    git: Git,
    leftRef: string,
    rightRef: string | null,
    leftLabel: string,
    rightLabel: string,
    files: ChangedFile[],
  ) {
    this.git = git;
    this.leftRef = leftRef;
    this.rightRef = rightRef;
    this.leftLabel = leftLabel;
    this.rightLabel = rightLabel;
    this.files = files;
  }

  /** Fetches every `<remote>/<branch>` mentioned in the refs so the diff
   *  reflects the actual state on the remote, not a stale local snapshot.
   *  Returns refs whose branch no longer exists on the remote. */
  private static async fetchRemoteRefs(git: Git, refs: string[]): Promise<Set<string>> {
    const parts: string[] = [];
    for (const ref of refs) {
      const triple = ref.indexOf("...");
      const double = ref.indexOf("..");
      if (triple >= 0) {
        parts.push(ref.slice(0, triple), ref.slice(triple + 3));
      } else if (double >= 0) {
        parts.push(ref.slice(0, double), ref.slice(double + 2));
      } else {
        parts.push(ref);
      }
    }
    const remotes = new Set(await git.remotes());
    const deleted = new Set<string>();
    const seen = new Set<string>();
    for (const part of parts) {
      const slash = part.indexOf("/");
      if (slash < 0) continue;
      const remote = part.slice(0, slash);
      const branch = part.slice(slash + 1);
      if (!remotes.has(remote) || !branch || seen.has(part)) continue;
      seen.add(part);
      err(`fetching ${part}…`);
      const result = await git.fetch(remote, branch);
      if (result.kind === "deletedOnRemote") {
        deleted.add(part);
        err(`warning: '${branch}' no longer exists on ${remote} — showing the last locally known state`);
      } else if (result.kind === "failed") {
        err(`warning: fetch of ${part} failed (offline?) — using local refs\n  ${result.error}`);
      }
    }
    return deleted;
  }

  /** Resolves the left side of a comparison. By default (`twoDot == false`)
   *  the left side is the merge base of base and target — GitLab-MR
   *  semantics: only changes made on the target side are shown, never
   *  commits the base branch is ahead by. `--two-dot` compares tips exactly. */
  private static async leftSide(
    git: Git,
    base: string,
    target: string,
    twoDot: boolean,
  ): Promise<{ ref: string; label: string }> {
    if (!twoDot) {
      try {
        const mergeBase = await git.mergeBase(base, target);
        const baseSha = await git.resolve(base);
        if (baseSha) {
          if (mergeBase === baseSha) return { ref: base, label: base };
          return { ref: mergeBase, label: `${base} (merge base)` };
        }
      } catch { /* fall through to plain base */ }
    }
    return { ref: base, label: base };
  }

  static async create(opts: {
    cwd: string;
    refs: string[];
    paths: string[];
    twoDot?: boolean;
    noFetch?: boolean;
    labels?: { left: string; right: string };
  }): Promise<DiffSession> {
    const { refs, paths } = opts;
    const twoDot = opts.twoDot ?? false;
    const noFetch = opts.noFetch ?? false;
    const git = await Git.open(opts.cwd);

    const deletedOnRemote = noFetch ? new Set<string>() : await DiffSession.fetchRemoteRefs(git, refs);

    let leftRef: string;
    let rightRef: string | null;
    let leftLabel: string;
    let rightLabel: string;

    if (refs.length === 0) {
      leftRef = "HEAD";
      rightRef = null;
      leftLabel = "HEAD";
      rightLabel = "Working tree";
      await git.verifyRef("HEAD");
    } else if (refs.length === 1) {
      const ref = refs[0]!;
      const triple = ref.indexOf("...");
      const double = ref.indexOf("..");
      if (triple >= 0) {
        const a = ref.slice(0, triple);
        const b = ref.slice(triple + 3);
        if (!a || !b) throw new GitError(`invalid range: ${ref}`);
        await git.verifyRef(a);
        await git.verifyRef(b);
        leftRef = await git.mergeBase(a, b);
        rightRef = b;
        leftLabel = `${a} (merge base)`;
        rightLabel = b;
      } else if (double >= 0) {
        const a = ref.slice(0, double);
        const b = ref.slice(double + 2);
        if (!a || !b) throw new GitError(`invalid range: ${ref}`);
        await git.verifyRef(a);
        await git.verifyRef(b);
        leftRef = a;
        rightRef = b;
        leftLabel = a;
        rightLabel = b;
      } else {
        await git.verifyRef(ref);
        const left = await DiffSession.leftSide(git, ref, "HEAD", twoDot);
        leftRef = left.ref;
        leftLabel = left.label;
        rightRef = null;
        rightLabel = "Working tree";
      }
    } else if (refs.length === 2) {
      await git.verifyRef(refs[0]!);
      await git.verifyRef(refs[1]!);
      const left = await DiffSession.leftSide(git, refs[0]!, refs[1]!, twoDot);
      leftRef = left.ref;
      leftLabel = left.label;
      rightRef = refs[1]!;
      rightLabel = refs[1]!;
    } else {
      throw new GitError("too many refs (expected at most 2)");
    }

    for (const ref of deletedOnRemote) {
      leftLabel = leftLabel.replace(ref, `${ref} ⚠︎ deleted on remote`);
      rightLabel = rightLabel.replace(ref, `${ref} ⚠︎ deleted on remote`);
    }
    if (opts.labels) {
      leftLabel = opts.labels.left;
      rightLabel = opts.labels.right;
    }

    const files = await git.changedFiles(leftRef, rightRef, paths);
    return new DiffSession(git, leftRef, rightRef, leftLabel, rightLabel, files);
  }

  get title(): string {
    return `${this.leftLabel} → ${this.rightLabel}`;
  }

  async fileDiffAt(index: number): Promise<FileDiffJSON> {
    const cached = this.cache.get(index);
    if (cached) return cached;
    const file = this.files[index]!;
    const oldData = file.status === "added"
      ? Buffer.alloc(0)
      : await this.git.content(this.leftRef, file.oldPath);
    const newData = file.status === "deleted"
      ? Buffer.alloc(0)
      : await this.git.content(this.rightRef, file.newPath);
    const diff = makeFileDiff(file, oldData, newData);
    this.cache.set(index, diff);
    return diff;
  }

  toJSON(wrap: boolean | null): SessionJSON {
    return {
      title: this.title,
      leftLabel: this.leftLabel,
      rightLabel: this.rightLabel,
      files: this.files.map(toJSON),
      mr: this.mr
        ? {
            iid: this.mr.mr.iid,
            title: this.mr.mr.title,
            state: this.mr.mr.state,
            sourceBranch: this.mr.mr.sourceBranch,
            targetBranch: this.mr.mr.targetBranch,
            webURL: this.mr.mr.webURL,
          }
        : null,
      draftCount: this.mr?.draftCount ?? 0,
      commentCount: this.mr ? this.mr.allThreadLocations(this.files).length : 0,
      wrap,
    };
  }
}

export { toJSON as changedFileToJSON };
