// Port of Sources/DiffEngine.swift — Myers line diff, side-by-side row
// assembly, intra-line change ranges. Pure logic, no I/O.
import type {
  DiffLineJSON,
  DiffRowJSON,
  FileDiffJSON,
  RowKind,
} from "../shared/model.ts";
import { highlightLines } from "../shared/syntax.ts";

export interface ChangedFile {
  status: "added" | "deleted" | "modified" | "renamed" | "copied" | "typeChanged";
  oldPath: string;
  newPath: string;
}

export function statusFromCode(code: string): ChangedFile["status"] {
  switch (code[0]) {
    case "A": return "added";
    case "D": return "deleted";
    case "R": return "renamed";
    case "C": return "copied";
    case "T": return "typeChanged";
    default: return "modified";
  }
}

export function statusLetter(status: ChangedFile["status"]): string {
  switch (status) {
    case "added": return "A";
    case "deleted": return "D";
    case "modified": return "M";
    case "renamed": return "R";
    case "copied": return "C";
    case "typeChanged": return "T";
  }
}

export function displayPath(file: ChangedFile): string {
  return file.newPath.length > 0 ? file.newPath : file.oldPath;
}

export function isBinary(data: Buffer): boolean {
  const limit = Math.min(data.length, 8000);
  for (let i = 0; i < limit; i++) {
    if (data[i] === 0) return true;
  }
  return false;
}

export function splitLines(s: string): string[] {
  if (s.length === 0) return [];
  const lines = s.split("\n");
  if (lines[lines.length - 1] === "") lines.pop(); // trailing newline
  return lines;
}

/** Expand tabs to 4-column stops, counting code points (like Swift Characters). */
export function expandTabs(s: string): string {
  if (!s.includes("\t")) return s;
  let out = "";
  let col = 0;
  for (const ch of s) {
    if (ch === "\t") {
      const spaces = 4 - (col % 4);
      out += " ".repeat(spaces);
      col += spaces;
    } else {
      out += ch;
      col += 1;
    }
  }
  return out;
}

// MARK: Myers diff

type Edit =
  | { type: "equal"; o: number; n: number }
  | { type: "delete"; o: number }
  | { type: "insert"; n: number };

/** Line-based diff. Falls back to whole-file replace if the edit distance
 *  exceeds a cap (keeps worst-case time/memory bounded). */
export function diff(a: string[], b: string[]): Edit[] {
  // Map lines to integers for fast comparison.
  const table = new Map<string, number>();
  const id = (s: string): number => {
    let v = table.get(s);
    if (v === undefined) {
      v = table.size;
      table.set(s, v);
    }
    return v;
  };
  const aIDs = a.map(id);
  const bIDs = b.map(id);

  // Trim common prefix/suffix.
  let start = 0;
  while (start < aIDs.length && start < bIDs.length && aIDs[start] === bIDs[start]) start++;
  let endA = aIDs.length;
  let endB = bIDs.length;
  while (endA > start && endB > start && aIDs[endA - 1] === bIDs[endB - 1]) {
    endA--;
    endB--;
  }

  const edits: Edit[] = [];
  for (let i = 0; i < start; i++) edits.push({ type: "equal", o: i, n: i });

  const midA = aIDs.slice(start, endA);
  const midB = bIDs.slice(start, endB);
  const mid = myers(midA, midB);
  if (mid) {
    for (const e of mid) {
      if (e.type === "equal") edits.push({ type: "equal", o: e.o + start, n: e.n + start });
      else if (e.type === "delete") edits.push({ type: "delete", o: e.o + start });
      else edits.push({ type: "insert", n: e.n + start });
    }
  } else {
    // Too different: treat middle as full replacement.
    for (let i = start; i < endA; i++) edits.push({ type: "delete", o: i });
    for (let j = start; j < endB; j++) edits.push({ type: "insert", n: j });
  }

  const tail = aIDs.length - endA;
  for (let t = 0; t < tail; t++) edits.push({ type: "equal", o: endA + t, n: endB + t });
  return edits;
}

/** Standard Myers O(ND) with trace backtracking. Returns null if D exceeds cap. */
function myers(a: number[], b: number[]): Edit[] | null {
  const n = a.length;
  const m = b.length;
  if (n === 0 && m === 0) return [];
  if (n === 0) return b.map((_, i) => ({ type: "insert", n: i } as Edit));
  if (m === 0) return a.map((_, i) => ({ type: "delete", o: i } as Edit));

  const maxD = Math.min(n + m, 2000);
  const offset = maxD;
  let v = new Int32Array(2 * maxD + 2);
  const trace: Int32Array[] = [];
  let foundD = -1;

  outer: for (let d = 0; d <= maxD; d++) {
    trace.push(v);
    v = v.slice();
    for (let k = -d; k <= d; k += 2) {
      let x: number;
      if (k === -d || (k !== d && v[offset + k - 1]! < v[offset + k + 1]!)) {
        x = v[offset + k + 1]!;
      } else {
        x = v[offset + k - 1]! + 1;
      }
      let y = x - k;
      while (x < n && y < m && a[x] === b[y]) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        foundD = d;
        break outer;
      }
    }
  }
  if (foundD < 0) return null;

  const edits: Edit[] = [];
  let x = n;
  let y = m;
  for (let d = trace.length - 1; d >= 0; d--) {
    const vd = trace[d]!;
    const k = x - y;
    let prevK: number;
    if (k === -d || (k !== d && vd[offset + k - 1]! < vd[offset + k + 1]!)) {
      prevK = k + 1;
    } else {
      prevK = k - 1;
    }
    const prevX = vd[offset + prevK]!;
    const prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      edits.push({ type: "equal", o: x - 1, n: y - 1 });
      x--;
      y--;
    }
    if (d > 0) {
      if (x === prevX) {
        edits.push({ type: "insert", n: y - 1 });
        y--;
      } else {
        edits.push({ type: "delete", o: x - 1 });
        x--;
      }
    }
  }
  return edits.reverse();
}

// MARK: Row assembly

export function makeFileDiff(
  file: ChangedFile,
  oldContent: Buffer,
  newContent: Buffer,
  withTokens = true,
): FileDiffJSON {
  if (isBinary(oldContent) || isBinary(newContent)) {
    const line: DiffLineJSON = { n: 0, t: "Binary files differ", hl: null, tok: [] };
    return {
      rows: [{ kind: "message", left: line, right: { ...line } }],
      changeBlocks: [],
      additions: 0,
      deletions: 0,
      isBinary: true,
      maxLeftColumns: 24,
      maxRightColumns: 24,
      maxLineNumber: 0,
    };
  }

  const oldLines = splitLines(oldContent.toString("utf8"));
  const newLines = splitLines(newContent.toString("utf8"));
  const edits = diff(oldLines, newLines);
  return assembleRows(file, oldLines, newLines, edits, withTokens);
}

function assembleRows(
  file: ChangedFile,
  oldLines: string[],
  newLines: string[],
  edits: Edit[],
  withTokens: boolean,
): FileDiffJSON {
  const rows: DiffRowJSON[] = [];
  const blocks: number[] = [];
  let additions = 0;
  let deletions = 0;
  let pendingDel: number[] = [];
  let pendingIns: number[] = [];
  let maxLeft = 0;
  let maxRight = 0;

  const oldDisplay = oldLines.map(expandTabs);
  const newDisplay = newLines.map(expandTabs);
  const path = displayPath(file);
  const oldTokens = withTokens ? highlightLines(oldDisplay, path) : null;
  const newTokens = withTokens ? highlightLines(newDisplay, path) : null;

  const cpLen = (s: string) => [...s].length;

  const flushPending = () => {
    if (pendingDel.length === 0 && pendingIns.length === 0) return;
    blocks.push(rows.length);
    const count = Math.max(pendingDel.length, pendingIns.length);
    for (let i = 0; i < count; i++) {
      const oldIdx = i < pendingDel.length ? pendingDel[i]! : null;
      const newIdx = i < pendingIns.length ? pendingIns[i]! : null;
      let leftHL: [number, number] | null = null;
      let rightHL: [number, number] | null = null;
      if (oldIdx !== null && newIdx !== null) {
        [leftHL, rightHL] = intralineRanges(oldDisplay[oldIdx]!, newDisplay[newIdx]!);
      }
      let kind: RowKind;
      if (pendingDel.length > 0 && pendingIns.length > 0) {
        kind = "modification";
      } else if (oldIdx !== null) {
        kind = "deletion";
      } else {
        kind = "addition";
      }
      const left: DiffLineJSON | null = oldIdx !== null
        ? { n: oldIdx + 1, t: oldDisplay[oldIdx]!, hl: leftHL, tok: oldTokens?.[oldIdx] ?? [] }
        : null;
      const right: DiffLineJSON | null = newIdx !== null
        ? { n: newIdx + 1, t: newDisplay[newIdx]!, hl: rightHL, tok: newTokens?.[newIdx] ?? [] }
        : null;
      if (left) maxLeft = Math.max(maxLeft, cpLen(left.t));
      if (right) maxRight = Math.max(maxRight, cpLen(right.t));
      rows.push({ kind, left, right });
    }
    deletions += pendingDel.length;
    additions += pendingIns.length;
    pendingDel = [];
    pendingIns = [];
  };

  for (const edit of edits) {
    if (edit.type === "equal") {
      flushPending();
      const o = edit.o;
      const nn = edit.n;
      const left: DiffLineJSON = {
        n: o + 1, t: oldDisplay[o]!, hl: null, tok: oldTokens?.[o] ?? [],
      };
      const right: DiffLineJSON = {
        n: nn + 1, t: newDisplay[nn]!, hl: null, tok: newTokens?.[nn] ?? [],
      };
      maxLeft = Math.max(maxLeft, cpLen(left.t));
      maxRight = Math.max(maxRight, cpLen(right.t));
      rows.push({ kind: "context", left, right });
    } else if (edit.type === "delete") {
      pendingDel.push(edit.o);
    } else {
      pendingIns.push(edit.n);
    }
  }
  flushPending();

  if (rows.length === 0) {
    const line: DiffLineJSON = { n: 0, t: "Files are identical", hl: null, tok: [] };
    rows.push({ kind: "message", left: line, right: { ...line } });
  }

  return {
    rows,
    changeBlocks: blocks,
    additions,
    deletions,
    isBinary: false,
    maxLeftColumns: maxLeft,
    maxRightColumns: maxRight,
    maxLineNumber: Math.max(oldLines.length, newLines.length),
  };
}

/** Character ranges that differ between two lines (common prefix/suffix trimmed).
 *  Units are code-point offsets. */
export function intralineRanges(
  oldText: string,
  newText: string,
): [[number, number] | null, [number, number] | null] {
  const a = [...oldText];
  const b = [...newText];
  let p = 0;
  while (p < a.length && p < b.length && a[p] === b[p]) p++;
  let s = 0;
  while (s < a.length - p && s < b.length - p && a[a.length - 1 - s] === b[b.length - 1 - s]) s++;
  const leftEnd = a.length - s;
  const rightEnd = b.length - s;
  return [
    p < leftEnd ? [p, leftEnd] : null,
    p < rightEnd ? [p, rightEnd] : null,
  ];
}
