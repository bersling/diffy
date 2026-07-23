// Port of Sources/GitLab.swift — MR URL parsing, token discovery, API client,
// discussions / draft notes / members.
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import type { MRPosition } from "../shared/model.ts";

export class GitLabError extends Error {}

export interface MRRef {
  host: string; // e.g. gitlab.example.com
  projectPath: string; // e.g. group/project
  iid: number;
}

/** Parses https://host/group/project/-/merge_requests/123[/diffs...] */
export function parseMRRef(urlString: string): MRRef | null {
  let url: URL;
  try {
    url = new URL(urlString);
  } catch {
    return null;
  }
  const host = url.host;
  const p = url.pathname;
  const marker = "/-/merge_requests/";
  const idx = p.indexOf(marker);
  if (!host || idx < 0) return null;
  const project = p.slice(1, idx);
  const rest = p.slice(idx + marker.length);
  const iidString = rest.split("/")[0] ?? rest;
  const iid = Number.parseInt(iidString, 10);
  if (!project || !Number.isFinite(iid)) return null;
  return { host, projectPath: project, iid };
}

export interface GitLabMR {
  iid: number;
  title: string;
  state: string;
  sourceBranch: string;
  targetBranch: string;
  baseSha: string;
  startSha: string;
  headSha: string;
  webURL: string;
}

export interface MRNote {
  id: number;
  author: string;
  body: string;
  createdAt: string;
  system: boolean;
  isPending: boolean;
}

export interface MRThread {
  id: string;
  notes: MRNote[];
  position: MRPosition | null;
  resolved: boolean;
  isDraft: boolean;
  draftIDs: number[];
}

export interface MRDraft {
  id: number;
  note: string;
  position: MRPosition | null;
  /** set when the draft replies to a thread */
  discussionID: string | null;
}

export interface GitLabUser {
  username: string;
  name: string;
}

// MARK: - Token discovery

/** Collects candidate tokens without ever printing them: env vars,
 *  ~/.config/diffy/gitlab-token, and any gitlab MCP server configured in
 *  ~/.claude.json (so an existing Claude Code GitLab setup just works).
 *  MCP entries whose API URL matches `host` are preferred. The client
 *  tries candidates in order and skips ones the server rejects (stale
 *  tokens in the environment are common). */
export async function tokenCandidates(host: string): Promise<string[]> {
  const tokens: string[] = [];
  const add = (t: string | undefined | null) => {
    const v = t?.trim();
    if (v && !tokens.includes(v)) tokens.push(v);
  };

  add(process.env.DIFFY_GITLAB_TOKEN);

  const home = os.homedir();
  try {
    add(await fs.readFile(path.join(home, ".config/diffy/gitlab-token"), "utf8"));
  } catch { /* not present */ }

  // gitlab MCP servers from ~/.claude.json, host-matching entries first
  try {
    const data = await fs.readFile(path.join(home, ".claude.json"), "utf8");
    const json = JSON.parse(data) as Record<string, unknown>;
    const serverDicts: Record<string, unknown>[] = [];
    const collect = (servers: unknown) => {
      if (servers && typeof servers === "object") {
        for (const v of Object.values(servers as Record<string, unknown>)) {
          if (v && typeof v === "object") serverDicts.push(v as Record<string, unknown>);
        }
      }
    };
    collect(json.mcpServers);
    if (json.projects && typeof json.projects === "object") {
      for (const project of Object.values(json.projects as Record<string, unknown>)) {
        collect((project as Record<string, unknown>)?.mcpServers);
      }
    }
    const matching: string[] = [];
    const other: string[] = [];
    for (const server of serverDicts) {
      const env = server.env as Record<string, string> | undefined;
      const t = env?.GITLAB_PERSONAL_ACCESS_TOKEN;
      if (!t) continue;
      const url = env.GITLAB_API_URL ?? env.GITLAB_URL ?? "";
      if (url.includes(host)) matching.push(t);
      else other.push(t);
    }
    matching.forEach(add);
    other.forEach(add);
  } catch { /* not present or invalid */ }

  add(process.env.GITLAB_TOKEN);
  add(process.env.GITLAB_PERSONAL_ACCESS_TOKEN);
  return tokens;
}

// MARK: - API client

/** The operations MRContext needs — implemented by GitLabClient (live) and
 *  by the in-memory fake used for UI testing (server/fake-mr.ts). */
export interface MRClientAPI {
  fetchMR(): Promise<GitLabMR>;
  fetchDiscussions(): Promise<MRThread[]>;
  postReply(discussionID: string, body: string): Promise<void>;
  fetchDraftNotes(): Promise<MRDraft[]>;
  createDraft(
    mr: GitLabMR,
    body: string,
    position: MRPosition | null,
    replyToDiscussionID: string | null,
  ): Promise<void>;
  publishDrafts(): Promise<void>;
  deleteDraft(id: number): Promise<void>;
  fetchMembers(): Promise<GitLabUser[]>;
  postThread(mr: GitLabMR, body: string, position: MRPosition): Promise<void>;
}

export class GitLabClient implements MRClientAPI {
  readonly ref: MRRef;
  private tokens: string[] = [];
  private tokenIndex = 0;

  private constructor(ref: MRRef) {
    this.ref = ref;
  }

  static async create(ref: MRRef): Promise<GitLabClient> {
    const tokens = await tokenCandidates(ref.host);
    if (tokens.length === 0) {
      throw new GitLabError(
        "no GitLab token found. Provide one via the GITLAB_TOKEN environment " +
        "variable, ~/.config/diffy/gitlab-token, or a gitlab MCP server in ~/.claude.json",
      );
    }
    const client = new GitLabClient(ref);
    client.tokens = tokens;
    return client;
  }

  private get encodedProject(): string {
    // Encode like Swift's .alphanumerics allowed set: every path segment
    // becomes %XX-encoded except unreserved alphanumerics.
    return [...this.ref.projectPath]
      .map((ch) => (/[A-Za-z0-9]/.test(ch) ? ch : encodeURIComponent(ch)))
      .join("");
  }

  private async request(
    method: string,
    apiPath: string,
    query: Record<string, string> = {},
    jsonBody: unknown = undefined,
  ): Promise<Buffer> {
    // Build the URL manually: URLSearchParams would be fine for the query,
    // but the path must keep the %2F in the URL-encoded project id.
    const qs = Object.entries(query)
      .map(([k, v]) => `${k}=${v}`)
      .join("&");
    const url = `https://${this.ref.host}/api/v4/projects/${this.encodedProject}${apiPath}${qs ? `?${qs}` : ""}`;

    // Try token candidates in order; skip ones the server rejects.
    for (;;) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 30_000);
      let res: Response;
      try {
        res = await fetch(url, {
          method,
          headers: {
            "PRIVATE-TOKEN": this.tokens[this.tokenIndex]!,
            ...(jsonBody !== undefined ? { "Content-Type": "application/json" } : {}),
          },
          body: jsonBody !== undefined ? JSON.stringify(jsonBody) : undefined,
          signal: controller.signal,
        });
      } catch (err) {
        clearTimeout(timer);
        throw new GitLabError(`GitLab request failed: ${(err as Error).message}`);
      }
      clearTimeout(timer);
      const data = Buffer.from(await res.arrayBuffer());
      if (res.status === 401 && this.tokenIndex + 1 < this.tokens.length) {
        this.tokenIndex += 1;
        continue;
      }
      if (res.status < 200 || res.status >= 300) {
        const snippet = data.subarray(0, 300).toString("utf8");
        throw new GitLabError(`GitLab API ${method} ${apiPath} returned ${res.status}: ${snippet}`);
      }
      return data;
    }
  }

  async fetchMR(): Promise<GitLabMR> {
    const data = await this.request("GET", `/merge_requests/${this.ref.iid}`);
    const json = JSON.parse(data.toString("utf8")) as Record<string, unknown>;
    const diffRefs = json.diff_refs as Record<string, unknown> | undefined;
    const title = json.title as string | undefined;
    const source = json.source_branch as string | undefined;
    const target = json.target_branch as string | undefined;
    const base = diffRefs?.base_sha as string | undefined;
    const start = diffRefs?.start_sha as string | undefined;
    const head = diffRefs?.head_sha as string | undefined;
    if (!title || !source || !target || !base || !start || !head) {
      throw new GitLabError("unexpected MR response from GitLab");
    }
    return {
      iid: this.ref.iid,
      title,
      state: (json.state as string) ?? "unknown",
      sourceBranch: source,
      targetBranch: target,
      baseSha: base,
      startSha: start,
      headSha: head,
      webURL: (json.web_url as string) ?? "",
    };
  }

  async fetchDiscussions(): Promise<MRThread[]> {
    const threads: MRThread[] = [];
    let page = 1;
    for (;;) {
      const data = await this.request("GET", `/merge_requests/${this.ref.iid}/discussions`, {
        per_page: "100",
        page: String(page),
      });
      const items = JSON.parse(data.toString("utf8")) as Record<string, unknown>[];
      if (!Array.isArray(items)) throw new GitLabError("unexpected discussions response");
      for (const item of items) {
        const id = item.id as string | undefined;
        const noteDicts = item.notes as Record<string, unknown>[] | undefined;
        if (!id || !Array.isArray(noteDicts)) continue;
        const notes: MRNote[] = [];
        let position: MRPosition | null = null;
        let resolved = false;
        for (const n of noteDicts) {
          const system = (n.system as boolean) ?? false;
          const noteID = n.id as number | undefined;
          const body = n.body as string | undefined;
          if (noteID === undefined || body === undefined) continue;
          const author = ((n.author as Record<string, unknown>)?.name as string) ?? "?";
          notes.push({
            id: noteID,
            author,
            body,
            createdAt: (n.created_at as string) ?? "",
            system,
            isPending: false,
          });
          if (!position) {
            const p = n.position as Record<string, unknown> | undefined;
            if (p && ((p.position_type as string) ?? "text") === "text") {
              position = {
                oldPath: (p.old_path as string) ?? "",
                newPath: (p.new_path as string) ?? "",
                oldLine: (p.old_line as number) ?? null,
                newLine: (p.new_line as number) ?? null,
              };
            }
          }
          if ((n.resolvable as boolean) === true) {
            resolved = (n.resolved as boolean) ?? false;
          }
        }
        const userNotes = notes.filter((n) => !n.system);
        if (userNotes.length > 0) {
          threads.push({ id, notes: userNotes, position, resolved, isDraft: false, draftIDs: [] });
        }
      }
      if (items.length < 100) break;
      page += 1;
    }
    return threads;
  }

  async postReply(discussionID: string, body: string): Promise<void> {
    await this.request(
      "POST",
      `/merge_requests/${this.ref.iid}/discussions/${discussionID}/notes`,
      {},
      { body },
    );
  }

  // MARK: draft notes (review batching)

  private static parsePosition(p: Record<string, unknown> | undefined): MRPosition | null {
    if (!p || ((p.position_type as string) ?? "text") !== "text") return null;
    return {
      oldPath: (p.old_path as string) ?? "",
      newPath: (p.new_path as string) ?? "",
      oldLine: (p.old_line as number) ?? null,
      newLine: (p.new_line as number) ?? null,
    };
  }

  async fetchDraftNotes(): Promise<MRDraft[]> {
    const drafts: MRDraft[] = [];
    let page = 1;
    for (;;) {
      const data = await this.request("GET", `/merge_requests/${this.ref.iid}/draft_notes`, {
        per_page: "100",
        page: String(page),
      });
      const items = JSON.parse(data.toString("utf8")) as Record<string, unknown>[];
      if (!Array.isArray(items)) throw new GitLabError("unexpected draft_notes response");
      for (const item of items) {
        const id = item.id as number | undefined;
        const note = item.note as string | undefined;
        if (id === undefined || note === undefined) continue;
        const rawDiscussion = item.discussion_id;
        const discussionID =
          typeof rawDiscussion === "string"
            ? rawDiscussion
            : typeof rawDiscussion === "number"
              ? String(rawDiscussion)
              : null;
        drafts.push({
          id,
          note,
          position: GitLabClient.parsePosition(item.position as Record<string, unknown> | undefined),
          discussionID,
        });
      }
      if (items.length < 100) break;
      page += 1;
    }
    return drafts;
  }

  async createDraft(
    mr: GitLabMR,
    body: string,
    position: MRPosition | null,
    replyToDiscussionID: string | null,
  ): Promise<void> {
    const json: Record<string, unknown> = { note: body };
    if (replyToDiscussionID) {
      json.in_reply_to_discussion_id = replyToDiscussionID;
    }
    if (position) {
      const pos: Record<string, unknown> = {
        position_type: "text",
        base_sha: mr.baseSha,
        start_sha: mr.startSha,
        head_sha: mr.headSha,
        old_path: position.oldPath,
        new_path: position.newPath,
      };
      if (position.oldLine !== null) pos.old_line = position.oldLine;
      if (position.newLine !== null) pos.new_line = position.newLine;
      json.position = pos;
    }
    await this.request("POST", `/merge_requests/${this.ref.iid}/draft_notes`, {}, json);
  }

  async publishDrafts(): Promise<void> {
    await this.request("POST", `/merge_requests/${this.ref.iid}/draft_notes/bulk_publish`);
  }

  async deleteDraft(id: number): Promise<void> {
    await this.request("DELETE", `/merge_requests/${this.ref.iid}/draft_notes/${id}`);
  }

  // MARK: members (for @mentions)

  /** Project members including inherited ones; falls back gracefully on error. */
  async fetchMembers(): Promise<GitLabUser[]> {
    const users: GitLabUser[] = [];
    const seen = new Set<string>();
    let page = 1;
    while (page <= 5) {
      let items: Record<string, unknown>[];
      try {
        const data = await this.request("GET", "/members/all", {
          per_page: "100",
          page: String(page),
        });
        items = JSON.parse(data.toString("utf8")) as Record<string, unknown>[];
        if (!Array.isArray(items)) break;
      } catch {
        break;
      }
      for (const item of items) {
        const username = item.username as string | undefined;
        if (!username || seen.has(username)) continue;
        seen.add(username);
        users.push({ username, name: (item.name as string) ?? username });
      }
      if (items.length < 100) break;
      page += 1;
    }
    return users.sort((a, b) => a.username.toLowerCase().localeCompare(b.username.toLowerCase()));
  }

  async postThread(mr: GitLabMR, body: string, position: MRPosition): Promise<void> {
    const pos: Record<string, unknown> = {
      position_type: "text",
      base_sha: mr.baseSha,
      start_sha: mr.startSha,
      head_sha: mr.headSha,
      old_path: position.oldPath,
      new_path: position.newPath,
    };
    if (position.oldLine !== null) pos.old_line = position.oldLine;
    if (position.newLine !== null) pos.new_line = position.newLine;
    await this.request(
      "POST",
      `/merge_requests/${this.ref.iid}/discussions`,
      {},
      { body, position: pos },
    );
  }
}
