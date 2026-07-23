// Shared model types — JSON-friendly shapes mirroring the Swift app's model
// (DiffEngine.swift / GitLab.swift), exchanged between server and frontend.

export type FileStatusCode = "A" | "D" | "M" | "R" | "C" | "T";

export interface ChangedFileJSON {
  status: FileStatusCode;
  oldPath: string;
  newPath: string;
  displayPath: string;
}

export type RowKind = "context" | "addition" | "deletion" | "modification" | "message";

export interface LineTokenJSON {
  /** [start, end] in code-point indices of the line text */
  s: number;
  e: number;
  k: TokenKindCode;
}

export type TokenKindCode =
  | "keyword"
  | "string"
  | "comment"
  | "number"
  | "typeName"
  | "attribute";

export interface DiffLineJSON {
  /** 1-based line number in its file (0 for messages) */
  n: number;
  /** tab-expanded display text */
  t: string;
  /** intra-line changed range [start, end) in code points, or null */
  hl: [number, number] | null;
  /** syntax tokens (only present when the file type is known) */
  tok: LineTokenJSON[];
}

export interface DiffRowJSON {
  kind: RowKind;
  left: DiffLineJSON | null;
  right: DiffLineJSON | null;
}

export interface FileDiffJSON {
  rows: DiffRowJSON[];
  /** row index where each change block starts */
  changeBlocks: number[];
  additions: number;
  deletions: number;
  isBinary: boolean;
  maxLeftColumns: number;
  maxRightColumns: number;
  maxLineNumber: number;
}

export interface MRPosition {
  oldPath: string;
  newPath: string;
  oldLine: number | null;
  newLine: number | null;
}

export interface MRNoteJSON {
  id: number;
  author: string;
  body: string;
  createdAt: string;
  system: boolean;
  isPending: boolean;
}

export interface MRThreadJSON {
  id: string;
  notes: MRNoteJSON[];
  position: MRPosition | null;
  resolved: boolean;
  isDraft: boolean;
  draftIDs: number[];
}

export interface MRInfoJSON {
  iid: number;
  title: string;
  state: string;
  sourceBranch: string;
  targetBranch: string;
  webURL: string;
}

export interface SessionJSON {
  title: string;
  leftLabel: string;
  rightLabel: string;
  files: ChangedFileJSON[];
  mr: MRInfoJSON | null;
  /** MR review state (only in MR mode) */
  draftCount: number;
  commentCount: number;
  /** initial UI state flags */
  wrap: boolean | null; // one-off --wrap flag
}

/** GET /api/file/:index response */
export interface FileResponseJSON {
  diff: FileDiffJSON;
  /** displayThreads for this file (MR mode only) */
  threads: MRThreadJSON[] | null;
}

/** GET /api/comments entry — one positioned thread for the overview list */
export interface CommentLocationJSON {
  fileIndex: number;
  line: number;
  path: string;
  thread: MRThreadJSON;
}

/** Response of MR mutation endpoints: refreshed review state */
export interface MRMutationJSON {
  draftCount: number;
  commentCount: number;
  /** displayThreads for the file the mutation was issued from */
  threads: MRThreadJSON[] | null;
}

export interface WizardJSON {
  locals: string[];
  current: string | null;
  remotes: { name: string; branches: string[] }[];
}

export interface GitLabUserJSON {
  username: string;
  name: string;
}
