// The side-by-side diff panes: two horizontally-independent, vertically-synced
// virtualized renderers sharing one row geometry (ported from DiffPane +
// DiffHalfRowView/FoldRowView in Sources/UI.swift).
import type {
  DiffLineJSON,
  DiffRowJSON,
  MRThreadJSON,
  RowKind,
  TokenKindCode,
} from "../shared/model.ts";
import {
  ROW_HEIGHT,
  charWidth,
  gutterWidth as gutterWidthFor,
  wrappedLineCount,
} from "./metrics.ts";
import { Geometry } from "./vlist.ts";
import { buildCommentCard, measureCommentHeight } from "./comments.ts";

export type PaneSide = "left" | "right";

/** What a pane actually displays: a real diff row, a fold bar standing in for
 *  hidden unchanged rows, or a review-comment thread. (Ported DisplayRow.) */
export type DisplayRow =
  | { type: "line"; fullIndex: number; row: DiffRowJSON }
  | { type: "fold"; start: number; end: number; count: number }
  | { type: "comment"; thread: MRThreadJSON; side: PaneSide; anchor: number };

export interface PanesCallbacks {
  onFoldClick(start: number, end: number): void;
  onAddComment(fullIndex: number, side: PaneSide): void;
  onReply(thread: MRThreadJSON): void;
  onDiscard(thread: MRThreadJSON): void;
  /** Selection changed in a pane (for copy enablement). */
  onSelectionChange?(): void;
}

const OVERSCAN = 6;
const MAX_CONTENT_WIDTH = 100_000;

interface PaneState {
  side: PaneSide;
  el: HTMLElement;
  inner: HTMLElement;
  visible: Map<number, HTMLElement>;
  selection: Set<number>;
  anchorRow: number | null;
}

function el(tag: string, className: string): HTMLElement {
  const e = document.createElement(tag);
  e.className = className;
  return e;
}

/** Flattens syntax tokens + the intra-line highlight range into styled spans. */
function renderCodeContent(code: HTMLElement, line: DiffLineJSON, kind: RowKind): void {
  code.textContent = "";
  const chars = [...line.t];
  const hl = line.hl;
  const showHL = hl !== null && kind !== "context" && kind !== "message";
  if (line.tok.length === 0 && !showHL) {
    code.textContent = line.t;
    return;
  }
  // Collect segment boundaries (clamped to the text length).
  const hlS = hl ? Math.max(0, Math.min(hl[0], chars.length)) : 0;
  const hlE = hl ? Math.max(0, Math.min(hl[1], chars.length)) : 0;
  const bounds = new Set<number>([0, chars.length]);
  for (const t of line.tok) {
    bounds.add(Math.max(0, Math.min(t.s, chars.length)));
    bounds.add(Math.max(0, Math.min(t.e, chars.length)));
  }
  if (showHL) {
    bounds.add(hlS);
    bounds.add(hlE);
  }
  const sorted = [...bounds].sort((a, b) => a - b);
  const kindAt = (pos: number): TokenKindCode | null => {
    for (const t of line.tok) {
      if (pos >= t.s && pos < t.e) return t.k;
    }
    return null;
  };
  for (let i = 0; i + 1 < sorted.length; i++) {
    const a = sorted[i]!;
    const b = sorted[i + 1]!;
    if (a === b) continue;
    const text = chars.slice(a, b).join("");
    const k = kindAt(a);
    const inHL = showHL && a >= hlS && b <= hlE;
    if (!k && !inHL) {
      code.appendChild(document.createTextNode(text));
      continue;
    }
    const span = document.createElement("span");
    span.className = (k ? `tok ${k}` : "") + (inHL ? " hl" : "");
    span.textContent = text;
    code.appendChild(span);
  }
}

export class DiffPanes {
  readonly root: HTMLElement;
  commentingEnabled = false;

  private left: PaneState;
  private right: PaneState;
  private geometry = new Geometry(ROW_HEIGHT);
  private rows: DisplayRow[] = [];
  private gutterPx = 48;
  private contentWidth: Record<PaneSide, number> = { left: 480, right: 480 };
  private maxColumns: Record<PaneSide, number> = { left: 80, right: 80 };
  private maxLineNumber = 1;
  private softWrap = false;
  private currentBlock: { start: number; end: number } | null = null;
  private isSyncing = false;
  private renderQueued = false;
  private pool: Record<"line" | "fold" | "comment", HTMLElement[]> = {
    line: [],
    fold: [],
    comment: [],
  };
  private contextMenu: HTMLElement | null = null;
  private wrapHeightCache = new Map<number, number>();
  private callbacks: PanesCallbacks;

  constructor(callbacks: PanesCallbacks) {
    this.callbacks = callbacks;
    this.root = el("div", "panes");
    this.left = this.makePane("left");
    this.right = this.makePane("right");
    this.root.append(this.left.el, this.right.el);

    // Keep wrap heights + comment cards correct when panes resize.
    new ResizeObserver(() => this.onResize()).observe(this.root);
    document.addEventListener("mousedown", (e) => {
      if (this.contextMenu && !this.contextMenu.contains(e.target as Node)) {
        this.closeContextMenu();
      }
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.closeContextMenu();
    });
  }

  private makePane(side: PaneSide): PaneState {
    const paneEl = el("div", `pane ${side}`);
    paneEl.tabIndex = -1;
    const inner = el("div", "pane-inner");
    paneEl.appendChild(inner);
    const state: PaneState = {
      side,
      el: paneEl,
      inner,
      visible: new Map(),
      selection: new Set(),
      anchorRow: null,
    };
    paneEl.addEventListener("scroll", () => this.onScroll(state));
    paneEl.addEventListener("contextmenu", (e) => this.onContextMenu(state, e));
    paneEl.addEventListener("copy", (e) => this.onCopy(state, e));
    return state;
  }

  // MARK: geometry

  private paneWidth(state: PaneState): number {
    return Math.max(240, state.el.clientWidth);
  }

  /** Width available for line text in soft-wrap mode (matches Swift's
   *  wrapTextWidth = clipWidth - gutter - 8 - 6). */
  private wrapTextWidth(): number {
    return Math.max(60, this.paneWidth(this.left) - this.gutterPx - 8 - 6);
  }

  private computeHeight(row: number): number {
    const displayRow = this.rows[row]!;
    if (displayRow.type === "fold") return ROW_HEIGHT;
    if (displayRow.type === "comment") {
      return measureCommentHeight(displayRow.thread, this.paneWidth(this.left) - 32) + 8;
    }
    const diffRow = displayRow.row;
    if (diffRow.kind === "message") return ROW_HEIGHT;
    if (!this.softWrap) return ROW_HEIGHT;
    const cached = this.wrapHeightCache.get(row);
    if (cached !== undefined) return cached;
    let lines = 1;
    const w = this.wrapTextWidth();
    if (diffRow.left) lines = Math.max(lines, wrappedLineCount(diffRow.left.t, w));
    if (diffRow.right) lines = Math.max(lines, wrappedLineCount(diffRow.right.t, w));
    const height = lines * ROW_HEIGHT;
    this.wrapHeightCache.set(row, height);
    return height;
  }

  private recomputeGeometry(): void {
    this.geometry.setRowCount(this.rows.length);
    for (let i = 0; i < this.rows.length; i++) {
      this.geometry.setHeight(i, this.computeHeight(i));
    }
    const total = this.geometry.totalHeight();
    for (const state of [this.left, this.right]) {
      const width = this.softWrap
        ? this.paneWidth(state)
        : Math.max(this.contentWidth[state.side], this.paneWidth(state));
      state.inner.style.height = `${total}px`;
      state.inner.style.width = `${width}px`;
    }
  }

  // MARK: content

  setContent(
    rows: DisplayRow[],
    meta: { maxLeftColumns: number; maxRightColumns: number; maxLineNumber: number },
  ): void {
    this.rows = rows;
    this.currentBlock = null;
    this.maxColumns = { left: meta.maxLeftColumns, right: meta.maxRightColumns };
    this.maxLineNumber = meta.maxLineNumber;
    this.gutterPx = gutterWidthFor(meta.maxLineNumber);
    const cw = charWidth();
    this.contentWidth = {
      left: Math.min(this.gutterPx + 8 + meta.maxLeftColumns * cw + 30, MAX_CONTENT_WIDTH),
      right: Math.min(this.gutterPx + 8 + meta.maxRightColumns * cw + 30, MAX_CONTENT_WIDTH),
    };
    this.left.selection.clear();
    this.right.selection.clear();
    this.left.anchorRow = null;
    this.right.anchorRow = null;
    this.wrapHeightCache.clear();
    this.clearPane(this.left);
    this.clearPane(this.right);
    this.left.el.scrollTop = 0;
    this.right.el.scrollTop = 0;
    this.left.el.scrollLeft = 0;
    this.right.el.scrollLeft = 0;
    this.recomputeGeometry();
    this.render();
  }

  /** Swap the row list without touching the scroll position (fold expand,
   *  comment refresh). */
  updateRows(rows: DisplayRow[]): void {
    this.rows = rows;
    this.wrapHeightCache.clear();
    this.clearPane(this.left);
    this.clearPane(this.right);
    this.recomputeGeometry();
    this.render();
  }

  private clearPane(state: PaneState): void {
    for (const el of state.visible.values()) el.remove();
    state.visible.clear();
  }

  setSoftWrap(on: boolean): void {
    if (on === this.softWrap) return;
    this.softWrap = on;
    this.wrapHeightCache.clear();
    this.left.el.classList.toggle("wrap", on);
    this.right.el.classList.toggle("wrap", on);
    this.clearPane(this.left);
    this.clearPane(this.right);
    if (on) {
      this.left.el.scrollLeft = 0;
      this.right.el.scrollLeft = 0;
    }
    this.recomputeGeometry();
    this.render();
  }

  get wrapEnabled(): boolean {
    return this.softWrap;
  }

  /** Highlight the current change block (full-row index range). */
  setCurrentBlock(range: { start: number; end: number } | null): void {
    this.currentBlock = range;
    for (const state of [this.left, this.right]) {
      for (const [row, element] of state.visible) {
        const displayRow = this.rows[row];
        if (displayRow?.type === "line") {
          element.classList.toggle(
            "inblock",
            range !== null &&
              displayRow.fullIndex >= range.start &&
              displayRow.fullIndex < range.end &&
              displayRow.row.kind !== "context",
          );
        }
      }
    }
  }

  scrollToRow(row: number, animated: boolean): void {
    if (row < 0 || row >= this.rows.length) return;
    const viewH = this.left.el.clientHeight;
    const mid = this.geometry.offsetOf(row) + this.geometry.heightOf(row) / 2;
    const maxY = Math.max(0, this.geometry.totalHeight() - viewH);
    const target = Math.max(0, Math.min(mid - viewH / 2, maxY));
    this.left.el.scrollTo({ top: target, behavior: animated ? "smooth" : "auto" });
    if (!animated) {
      this.right.el.scrollTop = target;
      this.render();
    }
  }

  // MARK: scrolling / rendering

  private onScroll(source: PaneState): void {
    const partner = source === this.left ? this.right : this.left;
    if (!this.isSyncing) {
      const y = source.el.scrollTop;
      if (Math.abs(partner.el.scrollTop - y) > 0.5) {
        this.isSyncing = true;
        partner.el.scrollTop = y;
        this.isSyncing = false;
      }
    }
    this.queueRender();
  }

  private onResize(): void {
    // Wrapped lines and comment cards re-measure against the new width.
    this.wrapHeightCache.clear();
    this.clearPane(this.left);
    this.clearPane(this.right);
    this.recomputeGeometry();
    this.render();
  }

  private queueRender(): void {
    if (this.renderQueued) return;
    this.renderQueued = true;
    requestAnimationFrame(() => {
      this.renderQueued = false;
      this.render();
    });
  }

  private render(): void {
    if (this.rows.length === 0) return;
    const scrollTop = this.left.el.scrollTop;
    const viewH = this.left.el.clientHeight;
    const first = Math.max(0, this.geometry.rowAtOffset(scrollTop) - OVERSCAN);
    const last = Math.min(
      this.rows.length - 1,
      this.geometry.rowAtOffset(scrollTop + viewH) + OVERSCAN,
    );
    this.renderPane(this.left, first, last);
    this.renderPane(this.right, first, last);
  }

  private renderPane(state: PaneState, first: number, last: number): void {
    for (const [row, element] of state.visible) {
      if (row < first || row > last) {
        element.remove();
        this.pool[this.kindOf(this.rows[row]!)].push(element);
        state.visible.delete(row);
      }
    }
    for (let row = first; row <= last; row++) {
      let element = state.visible.get(row);
      if (!element) {
        const displayRow = this.rows[row]!;
        const kind = this.kindOf(displayRow);
        element = this.pool[kind].pop() ?? this.createRowElement(kind);
        element.dataset.row = String(row);
        this.configureRowElement(state, element, row);
        state.inner.appendChild(element);
        state.visible.set(row, element);
      }
      element.style.transform = `translateY(${this.geometry.offsetOf(row)}px)`;
      element.style.height = `${this.geometry.heightOf(row)}px`;
    }
    this.positionOverlays(state);
  }

  private kindOf(row: DisplayRow): "line" | "fold" | "comment" {
    if (row.type === "fold") return "fold";
    if (row.type === "comment") return "comment";
    return "line";
  }

  private createRowElement(kind: "line" | "fold" | "comment"): HTMLElement {
    if (kind === "fold") {
      const row = el("div", "drow fold");
      row.appendChild(el("span", "fold-label"));
      return row;
    }
    if (kind === "comment") {
      return el("div", "drow comment-row");
    }
    // line
    const row = el("div", "drow");
    const gutter = el("div", "gutter");
    gutter.appendChild(el("span", "gnum"));
    const code = el("div", "code");
    row.append(gutter, code);
    return row;
  }

  private configureRowElement(state: PaneState, element: HTMLElement, row: number): void {
    const displayRow = this.rows[row]!;
    element.style.left = "0";
    element.style.top = "0";
    element.style.width = "100%";
    if (displayRow.type === "fold") {
      const label = element.firstElementChild as HTMLElement;
      label.textContent = `⋯ ${displayRow.count} unchanged lines ⋯`;
      element.onclick = () => this.callbacks.onFoldClick(displayRow.start, displayRow.end);
      return;
    }
    if (displayRow.type === "comment") {
      element.textContent = "";
      element.onclick = null;
      if (displayRow.side === state.side) {
        element.className = "drow comment";
        const card = buildCommentCard(displayRow.thread, {
          onReply: (t) => this.callbacks.onReply(t),
          onDiscard: (t) => this.callbacks.onDiscard(t),
        });
        element.appendChild(card);
      } else {
        element.className = "drow comment-spacer";
      }
      return;
    }

    // line row
    const diffRow = displayRow.row;
    const line = state.side === "left" ? diffRow.left : diffRow.right;
    const gutter = element.firstElementChild as HTMLElement;
    const code = element.lastElementChild as HTMLElement;
    element.onclick = null;

    if (diffRow.kind === "message") {
      element.className = "drow message";
      gutter.style.display = "none";
      code.className = "code";
      code.textContent = "";
      const msg = el("span", "msg");
      msg.textContent = line?.t ?? "";
      code.appendChild(msg);
      this.wireSelection(state, element);
      return;
    }
    gutter.style.display = "";

    const kindClass = { context: "ctx", addition: "add", deletion: "del", modification: "mod", message: "message" }[
      diffRow.kind
    ];
    element.className = `drow ${line ? kindClass : "placeholder"}`;
    if (
      this.currentBlock &&
      displayRow.fullIndex >= this.currentBlock.start &&
      displayRow.fullIndex < this.currentBlock.end &&
      diffRow.kind !== "context"
    ) {
      element.classList.add("inblock");
    }
    if (state.selection.has(row)) element.classList.add("selected");

    (gutter.firstElementChild as HTMLElement).textContent = line ? String(line.n) : "";
    gutter.style.width = `${this.gutterPx}px`;
    gutter.style.flexBasis = `${this.gutterPx}px`;
    code.className = "code";
    if (line) {
      renderCodeContent(code, line, diffRow.kind);
    } else {
      code.textContent = "";
    }
    this.wireSelection(state, element);
  }

  /** Fold labels + comment cards anchor to the visible portion of the pane
   *  when scrolled horizontally (ported from updateForVisibleRect). */
  private positionOverlays(state: PaneState): void {
    const scrollLeft = state.el.scrollLeft;
    const paneW = this.paneWidth(state);
    for (const [row, element] of state.visible) {
      const displayRow = this.rows[row];
      if (!displayRow) continue;
      if (displayRow.type === "fold") {
        const label = element.firstElementChild as HTMLElement;
        const labelW = label.offsetWidth;
        label.style.left = `${scrollLeft + Math.max(8, (paneW - labelW) / 2)}px`;
      } else if (displayRow.type === "comment" && displayRow.side === state.side) {
        const card = element.firstElementChild as HTMLElement | null;
        if (card) {
          card.style.left = `${scrollLeft + 16}px`;
          card.style.width = `${paneW - 32}px`;
        }
      }
    }
  }

  // MARK: selection / copy / context menu

  private wireSelection(state: PaneState, element: HTMLElement): void {
    element.onmousedown = (e: MouseEvent) => {
      if (e.button !== 0) return; // left button only; context menu handles right
      const row = Number(element.dataset.row);
      const displayRow = this.rows[row];
      if (!displayRow || displayRow.type !== "line") return;
      if (displayRow.row.kind === "message") return;
      state.el.focus({ preventScroll: true });
      if (e.shiftKey && state.anchorRow !== null) {
        const [a, b] = [Math.min(state.anchorRow, row), Math.max(state.anchorRow, row)];
        state.selection = new Set(rangeInclusive(a, b));
      } else if (e.metaKey || e.ctrlKey) {
        if (state.selection.has(row)) state.selection.delete(row);
        else state.selection.add(row);
        state.anchorRow = row;
      } else {
        state.selection = new Set([row]);
        state.anchorRow = row;
      }
      this.refreshSelectionClasses(state);
      this.callbacks.onSelectionChange?.();
    };
  }

  private refreshSelectionClasses(state: PaneState): void {
    for (const [row, element] of state.visible) {
      element.classList.toggle("selected", state.selection.has(row));
    }
  }

  private selectedLines(state: PaneState): string[] {
    const lines: string[] = [];
    const sorted = [...state.selection].sort((a, b) => a - b);
    for (const row of sorted) {
      const displayRow = this.rows[row];
      if (displayRow?.type !== "line") continue;
      const line = state.side === "left" ? displayRow.row.left : displayRow.row.right;
      if (line) lines.push(line.t);
    }
    return lines;
  }

  private onCopy(state: PaneState, e: ClipboardEvent): void {
    const lines = this.selectedLines(state);
    if (lines.length === 0) return;
    e.preventDefault();
    e.clipboardData?.setData("text/plain", lines.join("\n"));
  }

  copySelection(state: "left" | "right"): void {
    const lines = this.selectedLines(state === "left" ? this.left : this.right);
    if (lines.length === 0) return;
    void navigator.clipboard?.writeText(lines.join("\n"));
  }

  hasSelection(): boolean {
    return this.left.selection.size > 0 || this.right.selection.size > 0;
  }

  private onContextMenu(state: PaneState, e: MouseEvent): void {
    const rowEl = (e.target as HTMLElement).closest<HTMLElement>(".drow");
    if (!rowEl || rowEl.dataset.row === undefined) return;
    const row = Number(rowEl.dataset.row);
    const displayRow = this.rows[row];
    if (!displayRow || displayRow.type !== "line" || displayRow.row.kind === "message") return;
    const line = state.side === "left" ? displayRow.row.left : displayRow.row.right;
    if (!line) return;
    e.preventDefault();
    this.closeContextMenu();

    const menu = el("div", "ctxmenu");
    const addItem = (title: string, action: () => void) => {
      const item = el("div", "item");
      item.textContent = title;
      item.addEventListener("click", () => {
        this.closeContextMenu();
        action();
      });
      menu.appendChild(item);
    };

    const inSelection = state.selection.has(row) && state.selection.size > 1;
    addItem(inSelection ? `Copy ${state.selection.size} Lines` : "Copy Line", () => {
      if (!state.selection.has(row)) {
        state.selection = new Set([row]);
        this.refreshSelectionClasses(state);
      }
      this.copySelection(state.side);
    });
    if (this.commentingEnabled) {
      addItem(`Add Comment on Line ${line.n}…`, () => {
        this.callbacks.onAddComment(displayRow.fullIndex, state.side);
      });
    }

    document.body.appendChild(menu);
    const menuRect = menu.getBoundingClientRect();
    menu.style.left = `${Math.min(e.clientX, window.innerWidth - menuRect.width - 8)}px`;
    menu.style.top = `${Math.min(e.clientY, window.innerHeight - menuRect.height - 8)}px`;
    this.contextMenu = menu;
  }

  private closeContextMenu(): void {
    this.contextMenu?.remove();
    this.contextMenu = null;
  }
}

function rangeInclusive(a: number, b: number): number[] {
  const out: number[] = [];
  for (let i = a; i <= b; i++) out.push(i);
  return out;
}
