// In-memory fake GitLab backend for exercising the MR review UI without a
// GitLab server. Enabled via the DIFFY_FAKE_MR environment variable (dev/test
// only, never set in normal use). Mutations apply to in-memory state, so the
// full flow — comment, reply, draft, discard, publish — works end to end.
import type { MRPosition } from "../shared/model.ts";
import type {
  GitLabMR,
  GitLabUser,
  MRClientAPI,
  MRDraft,
  MRThread,
} from "./gitlab.ts";

export class FakeMRClient implements MRClientAPI {
  readonly mr: GitLabMR = {
    iid: 42,
    title: "Fake MR for UI testing",
    state: "opened",
    sourceBranch: "feature",
    targetBranch: "master",
    baseSha: "0".repeat(40),
    startSha: "0".repeat(40),
    headSha: "1".repeat(40),
    webURL: "https://gitlab.example.com/group/project/-/merge_requests/42",
  };

  private threads: MRThread[];
  private drafts: MRDraft[];
  private nextThreadID = 100;
  private nextDraftID = 100;
  private nextNoteID = 100;

  constructor(anchorPath: string, anchorNewLine: number, anchorOldLine: number) {
    this.threads = [
      {
        id: "thread-1",
        notes: [
          {
            id: 1,
            author: "Ada Reviewer",
            body: "This looks suspicious — can you double-check the bounds here?",
            createdAt: "2026-07-20T10:00:00.000Z",
            system: false,
            isPending: false,
          },
          {
            id: 2,
            author: "Bob Author",
            body: "Good catch, verified against the old implementation.",
            createdAt: "2026-07-20T11:30:00.000Z",
            system: false,
            isPending: false,
          },
        ],
        position: { oldPath: anchorPath, newPath: anchorPath, oldLine: null, newLine: anchorNewLine },
        resolved: false,
        isDraft: false,
        draftIDs: [],
      },
      {
        id: "thread-2",
        notes: [
          {
            id: 3,
            author: "Carol Senior",
            body: "Nit: naming could be clearer, but fine as is.",
            createdAt: "2026-07-19T09:00:00.000Z",
            system: false,
            isPending: false,
          },
        ],
        position: { oldPath: anchorPath, newPath: anchorPath, oldLine: anchorOldLine, newLine: null },
        resolved: true,
        isDraft: false,
        draftIDs: [],
      },
    ];
    this.drafts = [];
  }

  async fetchMR(): Promise<GitLabMR> {
    return this.mr;
  }

  async fetchDiscussions(): Promise<MRThread[]> {
    return structuredClone(this.threads);
  }

  async fetchDraftNotes(): Promise<MRDraft[]> {
    return structuredClone(this.drafts);
  }

  async postReply(discussionID: string, body: string): Promise<void> {
    const thread = this.threads.find((t) => t.id === discussionID);
    if (!thread) throw new Error(`unknown discussion: ${discussionID}`);
    thread.notes.push({
      id: this.nextNoteID++,
      author: "You",
      body,
      createdAt: new Date().toISOString(),
      system: false,
      isPending: false,
    });
  }

  async createDraft(
    _mr: GitLabMR,
    body: string,
    position: MRPosition | null,
    replyToDiscussionID: string | null,
  ): Promise<void> {
    this.drafts.push({
      id: this.nextDraftID++,
      note: body,
      position: position ? structuredClone(position) : null,
      discussionID: replyToDiscussionID,
    });
  }

  async publishDrafts(): Promise<void> {
    for (const draft of this.drafts) {
      if (draft.discussionID) {
        const thread = this.threads.find((t) => t.id === draft.discussionID);
        thread?.notes.push({
          id: this.nextNoteID++,
          author: "You",
          body: draft.note,
          createdAt: new Date().toISOString(),
          system: false,
          isPending: false,
        });
      } else {
        this.threads.push({
          id: `thread-${this.nextThreadID++}`,
          notes: [{
            id: this.nextNoteID++,
            author: "You",
            body: draft.note,
            createdAt: new Date().toISOString(),
            system: false,
            isPending: false,
          }],
          position: draft.position,
          resolved: false,
          isDraft: false,
          draftIDs: [],
        });
      }
    }
    this.drafts = [];
  }

  async deleteDraft(id: number): Promise<void> {
    this.drafts = this.drafts.filter((d) => d.id !== id);
  }

  async fetchMembers(): Promise<GitLabUser[]> {
    return [
      { username: "areviewer", name: "Ada Reviewer" },
      { username: "bauthor", name: "Bob Author" },
      { username: "csenior", name: "Carol Senior" },
      { username: "ddoe", name: "Dana Doe" },
    ];
  }

  async postThread(_mr: GitLabMR, body: string, position: MRPosition): Promise<void> {
    this.threads.push({
      id: `thread-${this.nextThreadID++}`,
      notes: [{
        id: this.nextNoteID++,
        author: "You",
        body,
        createdAt: new Date().toISOString(),
        system: false,
        isPending: false,
      }],
      position: structuredClone(position),
      resolved: false,
      isDraft: false,
      draftIDs: [],
    });
  }
}
