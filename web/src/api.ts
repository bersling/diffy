// Thin typed client for the diffy-web server API.
import type {
  CommentLocationJSON,
  FileResponseJSON,
  GitLabUserJSON,
  MRMutationJSON,
  MRPosition,
  SessionJSON,
  WizardJSON,
} from "../shared/model.ts";

export type StateResponse =
  | { mode: "wizard" }
  | { mode: "session"; session: SessionJSON };

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    headers: body !== undefined ? { "Content-Type": "application/json" } : undefined,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const data = (await res.json()) as T & { error?: string };
  if (!res.ok) {
    throw new Error(data.error ?? `request failed: ${res.status}`);
  }
  return data;
}

export const api = {
  state: () => request<StateResponse>("GET", "/api/state"),
  wizard: () => request<WizardJSON>("GET", "/api/wizard"),
  compare: (source: string, target: string) =>
    request<{ ok: boolean; message?: string; session?: SessionJSON }>(
      "POST",
      "/api/compare",
      { source, target },
    ),
  file: (index: number) => request<FileResponseJSON>("GET", `/api/file/${index}`),
  comments: () =>
    request<{ comments: CommentLocationJSON[]; draftCount: number }>("GET", "/api/comments"),
  members: () => request<{ members: GitLabUserJSON[] }>("GET", "/api/mr/members"),
  reply: (discussionID: string, body: string, sendNow: boolean, fileIndex: number) =>
    request<MRMutationJSON>("POST", "/api/mr/reply", { discussionID, body, sendNow, fileIndex }),
  comment: (position: MRPosition, body: string, sendNow: boolean, fileIndex: number) =>
    request<MRMutationJSON>("POST", "/api/mr/comment", { position, body, sendNow, fileIndex }),
  discard: (draftIDs: number[], fileIndex: number) =>
    request<MRMutationJSON>("POST", "/api/mr/discard", { draftIDs, fileIndex }),
  publish: (fileIndex: number) =>
    request<MRMutationJSON>("POST", "/api/mr/publish", { fileIndex }),
};
