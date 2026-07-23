// Viewer: sidebar + header + diff panes, navigation, fold/comment management.
// Port of ContentViewController + MainWindowController from Sources/UI.swift.
import type {
  FileDiffJSON,
  MRPosition,
  MRThreadJSON,
  MRMutationJSON,
  SessionJSON,
} from "../shared/model.ts";
import { api } from "./api.ts";
import { DiffPanes, type DisplayRow, type PaneSide } from "./panes.ts";
import { Sidebar } from "./filetree.ts";
import {
  commentDialog,
  showCommentsPopover,
  type CommentOverviewEntry,
} from "./comments.ts";
import type { GitLabUserJSON } from "../shared/model.ts";
import { truncateMiddle } from "./metrics.ts";

const CONTEXT_LINES = 3;
const MIN_FOLD_SIZE = 10;
const WRAP_DEFAULTS_KEY = "diffySoftWrap";
const SIDEBAR_WIDTH_KEY = "diffySidebarWidth";

/** URL-param driven initial state — the web equivalent of the native app's
 *  hidden test flags (--select, --change, --expand-all, --filter-files, --wrap). */
export interface ViewerOptions {
  file?: number;
  change?: number;
  wrap?: boolean;
  expandAll?: boolean;
  filter?: string;
}

export class Viewer {
  readonly root: HTMLElement;

  private session: SessionJSON;
  private sidebar: Sidebar;
  private panes: DiffPanes;
  private pathLabel: HTMLElement;
  private statsLabel: HTMLElement;
  private counterLabel: HTMLElement;
  private reviewButton: HTMLButtonElement;
  private commentsButton: HTMLButtonElement;
  private wrapButton: HTMLButtonElement;

  private currentIndex = -1;
  private currentDiff: FileDiffJSON | null = null;
  private currentThreads: MRThreadJSON[] | null = null;
  private currentBlock = -1;
  private displayRows: DisplayRow[] = [];
  private fullToDisplay = new Map<number, number>();
  private expandedFolds = new Set<number>(); // keyed by fold range start (full index)
  private commentMap = new Map<number, { thread: MRThreadJSON; side: PaneSide }[]>();
  private fileRequest = 0;
  private softWrap: boolean;
  private members: GitLabUserJSON[] = [];
  private membersLoading = false;
  private draftCount: number;
  private commentCount: number;

  constructor(session: SessionJSON, options: ViewerOptions = {}) {
    this.session = session;
    this.draftCount = session.draftCount;
    this.commentCount = session.commentCount;

    this.root = document.createElement("div");
    this.root.className = "viewer";

    // --- sidebar + splitter ---
    this.sidebar = new Sidebar(session.files);
    const savedWidth = Number(localStorage.getItem(SIDEBAR_WIDTH_KEY));
    if (savedWidth >= 180 && savedWidth <= 520) {
      this.sidebar.root.style.width = `${savedWidth}px`;
    } else {
      this.sidebar.root.style.width = "260px";
    }
    const splitter = document.createElement("div");
    splitter.className = "splitter";
    splitter.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const startX = e.clientX;
      const startWidth = this.sidebar.root.getBoundingClientRect().width;
      const onMove = (ev: MouseEvent) => {
        const w = Math.max(180, Math.min(520, startWidth + ev.clientX - startX));
        this.sidebar.root.style.width = `${w}px`;
      };
      const onUp = () => {
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
        localStorage.setItem(
          SIDEBAR_WIDTH_KEY,
          String(Math.round(this.sidebar.root.getBoundingClientRect().width)),
        );
      };
      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    });

    // --- content ---
    const content = document.createElement("div");
    content.className = "content";

    const header = document.createElement("div");
    header.className = "header";
    this.pathLabel = document.createElement("span");
    this.pathLabel.className = "path";
    this.statsLabel = document.createElement("span");
    this.statsLabel.className = "stats";
    const spacer = document.createElement("span");
    spacer.className = "spacer";

    this.commentsButton = this.headerButton("Comments", "Show all review comments in this MR");
    this.commentsButton.addEventListener("click", () => void this.showAllComments());
    this.reviewButton = this.headerButton("Submit Review", "Publish all pending review comments at once");
    this.reviewButton.classList.add("orange");
    this.reviewButton.addEventListener("click", () => void this.submitReview());
    this.counterLabel = document.createElement("span");
    this.counterLabel.className = "counter";
    this.wrapButton = this.headerButton("↩", "Soft-wrap long lines (W)");
    this.wrapButton.classList.add("wrap");
    this.wrapButton.addEventListener("click", () => this.toggleWrap());
    const expandButton = this.headerButton("⤢", "Expand Unchanged Lines");
    expandButton.addEventListener("click", () => this.expandAllFolds());
    const prev = this.headerButton("▲", "Previous Change (P)");
    prev.addEventListener("click", () => this.prevChange());
    const next = this.headerButton("▼", "Next Change (N)");
    next.addEventListener("click", () => this.nextChange());

    header.append(
      this.pathLabel,
      this.statsLabel,
      spacer,
      this.commentsButton,
      this.reviewButton,
      this.counterLabel,
      expandButton,
      this.wrapButton,
      prev,
      next,
    );

    this.panes = new DiffPanes({
      onFoldClick: (start) => this.expandFold(start),
      onAddComment: (fullIndex, side) => void this.addComment(fullIndex, side),
      onReply: (thread) => void this.replyToThread(thread),
      onDiscard: (thread) => void this.discardDrafts(thread),
    });
    this.panes.commentingEnabled = session.mr !== null;

    content.append(header, this.panes.root);
    this.root.append(this.sidebar.root, splitter, content);

    // --- wiring ---
    this.sidebar.onSelect = (index) => void this.showFile(index);

    const fileCount = `(${session.files.length} file${session.files.length === 1 ? "" : "s"})`;
    document.title = session.mr
      ? `diffy — !${session.mr.iid} ${session.mr.title} — ${session.title}  ${fileCount}`
      : `diffy — ${session.title}  ${fileCount}`;

    // Soft wrap: one-off override wins; else saved pref; default on.
    const saved = localStorage.getItem(WRAP_DEFAULTS_KEY);
    const initial =
      options.wrap !== undefined
        ? options.wrap
        : session.wrap === true
          ? true
          : saved === null
            ? true
            : saved === "1";
    this.softWrap = initial;
    this.panes.setSoftWrap(initial);
    this.wrapButton.classList.toggle("active", initial);

    this.updateReviewButtons();
    this.installKeyboard();

    if (session.mr) this.loadMembers();
    if (options.filter) this.sidebar.setFilter(options.filter);
    if (session.files.length > 0) {
      const initialFile =
        options.file !== undefined && options.file >= 0 && options.file < session.files.length
          ? options.file
          : 0;
      this.sidebar.selectFile(initialFile);
      void this.showFile(initialFile).then(() => {
        for (let i = 0; i < (options.change ?? 0); i++) this.nextChange();
        if (options.expandAll) this.expandAllFolds();
      });
    }
  }

  private headerButton(label: string, tooltip: string): HTMLButtonElement {
    const b = document.createElement("button");
    b.className = "icon";
    b.textContent = label;
    b.title = tooltip;
    return b;
  }

  // MARK: file display

  private async showFile(index: number): Promise<void> {
    if (index < 0 || index >= this.session.files.length) return;
    if (index === this.currentIndex && this.currentDiff) return;
    const request = ++this.fileRequest;
    this.currentIndex = index;
    const { diff, threads } = await api.file(index);
    if (request !== this.fileRequest) return; // superseded by a newer click

    this.currentDiff = diff;
    this.currentThreads = threads;
    this.currentBlock = -1;

    const file = this.session.files[index]!;
    if (file.status === "R" || file.status === "C") {
      this.setPathLabel(`${file.oldPath} → ${file.newPath}`);
    } else {
      this.setPathLabel(file.displayPath);
    }
    this.statsLabel.textContent = "";
    if (diff.additions > 0) {
      const plus = document.createElement("span");
      plus.className = "plus";
      plus.textContent = `+${diff.additions} `;
      this.statsLabel.appendChild(plus);
    }
    if (diff.deletions > 0) {
      const minus = document.createElement("span");
      minus.className = "minus";
      minus.textContent = `−${diff.deletions}`;
      this.statsLabel.appendChild(minus);
    }

    this.expandedFolds.clear();
    this.rebuildCommentMap();
    this.rebuildDisplayRows();
    this.panes.setContent(this.displayRows, diff);
    this.updateCounter();
  }

  private setPathLabel(path: string): void {
    this.pathLabel.textContent = path;
    // Approximate AppKit's middle truncation once layout settles.
    requestAnimationFrame(() => {
      const avail = this.pathLabel.clientWidth;
      if (avail > 50) {
        this.pathLabel.textContent = truncateMiddle(
          path,
          avail,
          "600 12.5px -apple-system, BlinkMacSystemFont, sans-serif",
        );
      }
    });
  }

  // MARK: folds + comment anchoring

  /** Anchors the MR's review threads to full-row indices of the current file. */
  private rebuildCommentMap(): void {
    this.commentMap.clear();
    const diff = this.currentDiff;
    const threads = this.currentThreads;
    if (!diff || !threads || threads.length === 0) return;
    const file = this.session.files[this.currentIndex]!;
    const rowByRightLine = new Map<number, number>();
    const rowByLeftLine = new Map<number, number>();
    diff.rows.forEach((row, i) => {
      if (row.right) rowByRightLine.set(row.right.n, i);
      if (row.left) rowByLeftLine.set(row.left.n, i);
    });
    for (const thread of threads) {
      const pos = thread.position;
      if (!pos) continue;
      const rightIdx = pos.newLine !== null ? rowByRightLine.get(pos.newLine) : undefined;
      if (pos.newLine !== null && pos.newPath === file.newPath && rightIdx !== undefined) {
        this.pushComment(rightIdx, thread, "right");
      } else if (pos.oldLine !== null) {
        const leftIdx = rowByLeftLine.get(pos.oldLine);
        if (leftIdx !== undefined) this.pushComment(leftIdx, thread, "left");
      }
    }
  }

  private pushComment(fullIndex: number, thread: MRThreadJSON, side: PaneSide): void {
    let list = this.commentMap.get(fullIndex);
    if (!list) {
      list = [];
      this.commentMap.set(fullIndex, list);
    }
    list.push({ thread, side });
  }

  /** Rebuilds the display list: context runs longer than the threshold are
   *  folded, keeping CONTEXT_LINES visible around each change. Lines with
   *  review comments are never folded; their threads follow them as rows. */
  private rebuildDisplayRows(): void {
    const diff = this.currentDiff;
    if (!diff) {
      this.displayRows = [];
      this.fullToDisplay = new Map();
      return;
    }
    const rows = diff.rows;
    const out: DisplayRow[] = [];
    const map = new Map<number, number>();
    const emit = (idx: number) => {
      map.set(idx, out.length);
      out.push({ type: "line", fullIndex: idx, row: rows[idx]! });
      for (const { thread, side } of this.commentMap.get(idx) ?? []) {
        out.push({ type: "comment", thread, side, anchor: idx });
      }
    };
    let i = 0;
    while (i < rows.length) {
      if (rows[i]!.kind !== "context" || this.commentMap.has(i)) {
        emit(i);
        i += 1;
        continue;
      }
      let j = i;
      while (j < rows.length && rows[j]!.kind === "context" && !this.commentMap.has(j)) j += 1;
      const head = i === 0 ? 0 : CONTEXT_LINES; // after previous change
      const tail = j === rows.length ? 0 : CONTEXT_LINES; // before next change
      const hideStart = i + head;
      const hideEnd = j - tail;
      const hidden = hideEnd - hideStart;
      if (hidden >= MIN_FOLD_SIZE && !this.expandedFolds.has(hideStart)) {
        for (let k = i; k < hideStart; k++) emit(k);
        out.push({ type: "fold", start: hideStart, end: hideEnd, count: hidden });
        for (let k = hideEnd; k < j; k++) emit(k);
      } else {
        for (let k = i; k < j; k++) emit(k);
      }
      i = j;
    }
    this.displayRows = out;
    this.fullToDisplay = map;
  }

  private expandFold(start: number): void {
    if (this.expandedFolds.has(start)) return;
    this.expandedFolds.add(start);
    this.rebuildDisplayRows();
    this.panes.updateRows(this.displayRows);
    this.reapplyCurrentBlock();
  }

  private expandAllFolds(): void {
    let changed = false;
    for (const row of this.displayRows) {
      if (row.type === "fold") {
        this.expandedFolds.add(row.start);
        changed = true;
      }
    }
    if (!changed) return;
    this.rebuildDisplayRows();
    this.panes.updateRows(this.displayRows);
    this.reapplyCurrentBlock();
  }

  // MARK: change navigation

  private blockRange(startRow: number): { start: number; end: number } {
    const diff = this.currentDiff;
    if (!diff) return { start: startRow, end: startRow };
    let end = startRow;
    while (
      end < diff.rows.length &&
      diff.rows[end]!.kind !== "context" &&
      diff.rows[end]!.kind !== "message"
    ) {
      end += 1;
    }
    return { start: startRow, end: Math.max(end, startRow + 1) };
  }

  private goToBlock(blockIndex: number): void {
    const diff = this.currentDiff;
    if (!diff || diff.changeBlocks.length === 0) return;
    const clamped = Math.max(0, Math.min(blockIndex, diff.changeBlocks.length - 1));
    this.currentBlock = clamped;
    const startRow = diff.changeBlocks[clamped]!;
    this.panes.setCurrentBlock(this.blockRange(startRow));
    const displayIndex = this.fullToDisplay.get(startRow);
    if (displayIndex !== undefined) this.panes.scrollToRow(displayIndex, true);
    this.updateCounter();
  }

  private reapplyCurrentBlock(): void {
    const diff = this.currentDiff;
    if (this.currentBlock < 0 || !diff || this.currentBlock >= diff.changeBlocks.length) return;
    this.panes.setCurrentBlock(this.blockRange(diff.changeBlocks[this.currentBlock]!));
  }

  nextChange(): void {
    this.goToBlock(this.currentBlock + 1);
  }

  prevChange(): void {
    this.goToBlock(this.currentBlock <= 0 ? 0 : this.currentBlock - 1);
  }

  private selectFileOffset(offset: number): void {
    const target = this.currentIndex + offset;
    if (target < 0 || target >= this.session.files.length) return;
    this.sidebar.selectFile(target);
    void this.showFile(target);
  }

  private updateCounter(): void {
    const diff = this.currentDiff;
    if (!diff || diff.changeBlocks.length === 0) {
      this.counterLabel.textContent = "";
    } else if (this.currentBlock < 0) {
      const total = diff.changeBlocks.length;
      this.counterLabel.textContent = `${total} change${total === 1 ? "" : "s"}`;
    } else {
      this.counterLabel.textContent = `Change ${this.currentBlock + 1} of ${diff.changeBlocks.length}`;
    }
  }

  // MARK: soft wrap

  private setSoftWrap(on: boolean, persist: boolean): void {
    this.softWrap = on;
    this.wrapButton.classList.toggle("active", on);
    this.panes.setSoftWrap(on);
    if (persist) localStorage.setItem(WRAP_DEFAULTS_KEY, on ? "1" : "0");
  }

  toggleWrap(): void {
    this.setSoftWrap(!this.softWrap, true);
  }

  // MARK: keyboard

  private installKeyboard(): void {
    document.addEventListener("keydown", (e) => {
      const target = e.target as HTMLElement;
      if (
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target.isContentEditable
      ) {
        return;
      }
      if (e.metaKey || e.ctrlKey) {
        if (e.key === "ArrowDown") {
          e.preventDefault();
          this.selectFileOffset(1);
        } else if (e.key === "ArrowUp") {
          e.preventDefault();
          this.selectFileOffset(-1);
        }
        return;
      }
      if (e.altKey) return;
      switch (e.key) {
        case "n":
          this.nextChange();
          break;
        case "p":
        case "N":
          this.prevChange();
          break;
        case "F7":
          if (e.shiftKey) this.prevChange();
          else this.nextChange();
          break;
        case "]":
          this.selectFileOffset(1);
          break;
        case "[":
          this.selectFileOffset(-1);
          break;
        case "w":
          this.toggleWrap();
          break;
        default:
          return;
      }
      e.preventDefault();
    });
  }

  // MARK: GitLab review comments

  private loadMembers(): void {
    if (this.membersLoading) return;
    this.membersLoading = true;
    void api.members().then(({ members }) => {
      this.members = members;
    });
  }

  private membersProvider = (): GitLabUserJSON[] => {
    if (this.members.length === 0) this.loadMembers();
    return this.members;
  };

  private updateReviewButtons(): void {
    const isMR = this.session.mr !== null;
    this.reviewButton.style.display = isMR && this.draftCount > 0 ? "" : "none";
    this.reviewButton.textContent = `Submit Review (${this.draftCount})`;
    this.commentsButton.style.display = isMR && this.commentCount > 0 ? "" : "none";
    this.commentsButton.textContent = `Comments (${this.commentCount})`;
  }

  private refreshThreads(result: MRMutationJSON): void {
    this.currentThreads = result.threads;
    this.draftCount = result.draftCount;
    this.commentCount = result.commentCount;
    this.rebuildCommentMap();
    this.rebuildDisplayRows();
    this.panes.updateRows(this.displayRows);
    this.reapplyCurrentBlock();
    this.updateReviewButtons();
  }

  private showError(err: unknown): void {
    const message = err instanceof Error ? err.message : String(err);
    this.showToast(`GitLab request failed: ${message}`);
  }

  private showToast(message: string): void {
    const toast = document.createElement("div");
    toast.className = "comments-popover";
    toast.style.padding = "10px 14px";
    toast.style.color = "var(--red)";
    toast.textContent = message;
    document.body.appendChild(toast);
    toast.style.top = "48px";
    toast.style.left = `${Math.max(8, window.innerWidth - 420)}px`;
    setTimeout(() => toast.remove(), 6000);
    toast.addEventListener("click", () => toast.remove());
  }

  private async showAllComments(): Promise<void> {
    if (!this.session.mr) return;
    const { comments } = await api.comments();
    const entries: CommentOverviewEntry[] = comments.map((c) => ({
      fileIndex: c.fileIndex,
      line: c.line,
      path: c.path,
      thread: c.thread,
    }));
    if (entries.length === 0) return;
    showCommentsPopover(this.commentsButton, entries, (entry) => void this.navigateToComment(entry));
  }

  private async navigateToComment(entry: CommentOverviewEntry): Promise<void> {
    if (entry.fileIndex !== this.currentIndex) {
      this.sidebar.selectFile(entry.fileIndex);
      await this.showFile(entry.fileIndex);
    }
    // After the file is shown, scroll to the thread's row.
    const displayIndex = this.displayRows.findIndex(
      (r) => r.type === "comment" && r.thread.id === entry.thread.id,
    );
    if (displayIndex >= 0) this.panes.scrollToRow(displayIndex, true);
  }

  private async submitReview(): Promise<void> {
    if (!this.session.mr || this.draftCount === 0) return;
    try {
      this.refreshThreads(await api.publish(this.currentIndex));
    } catch (err) {
      this.showError(err);
    }
  }

  private async discardDrafts(thread: MRThreadJSON): Promise<void> {
    if (thread.draftIDs.length === 0) return;
    try {
      this.refreshThreads(await api.discard(thread.draftIDs, this.currentIndex));
    } catch (err) {
      this.showError(err);
    }
  }

  private async replyToThread(thread: MRThreadJSON): Promise<void> {
    if (!this.session.mr) return;
    const result = await commentDialog(
      `Reply to ${thread.notes[0]?.author ?? "thread"}`,
      this.membersProvider,
    );
    if (!result) return;
    try {
      this.refreshThreads(
        await api.reply(thread.id, result.body, result.sendNow, this.currentIndex),
      );
    } catch (err) {
      this.showError(err);
    }
  }

  private async addComment(fullIndex: number, side: PaneSide): Promise<void> {
    const diff = this.currentDiff;
    if (!this.session.mr || !diff || fullIndex >= diff.rows.length) return;
    const row = diff.rows[fullIndex]!;
    const file = this.session.files[this.currentIndex]!;
    let oldLine: number | null = null;
    let newLine: number | null = null;
    if (side === "right") {
      if (!row.right) return;
      newLine = row.right.n;
      if (row.kind === "context") oldLine = row.left?.n ?? null;
    } else {
      if (!row.left) return;
      oldLine = row.left.n;
      if (row.kind === "context") newLine = row.right?.n ?? null;
    }
    const lineDesc = newLine !== null ? `line ${newLine}` : `old line ${oldLine ?? 0}`;
    const result = await commentDialog(
      `Comment on ${file.displayPath.split("/").pop()}, ${lineDesc}`,
      this.membersProvider,
    );
    if (!result) return;
    const position: MRPosition = {
      oldPath: file.oldPath.length > 0 ? file.oldPath : file.newPath,
      newPath: file.newPath.length > 0 ? file.newPath : file.oldPath,
      oldLine,
      newLine,
    };
    try {
      this.refreshThreads(await api.comment(position, result.body, result.sendNow, this.currentIndex));
    } catch (err) {
      this.showError(err);
    }
  }
}
