// Virtual scrolling core. Geometry manages per-row heights + prefix-sum
// offsets with binary-search lookup; VList is a delegate-driven virtualized
// scroller (sidebar, wizard lists). The diff panes use Geometry directly
// with their own dual-renderer (see panes.ts).

export class Geometry {
  private heights: number[] = [];
  private offsets: number[] = [0];
  private dirty = true;
  private defaultHeight: number;

  constructor(defaultHeight: number) {
    this.defaultHeight = defaultHeight;
  }

  get rowCount(): number {
    return this.heights.length;
  }

  setRowCount(n: number): void {
    if (n === this.heights.length) return;
    this.heights = new Array(n).fill(this.defaultHeight);
    this.dirty = true;
  }

  setHeight(row: number, h: number): void {
    if (this.heights[row] !== h) {
      this.heights[row] = h;
      this.dirty = true;
    }
  }

  reset(): void {
    this.heights = [];
    this.offsets = [0];
    this.dirty = true;
  }

  private recompute(): void {
    if (!this.dirty) return;
    const n = this.heights.length;
    if (this.offsets.length !== n + 1) this.offsets = new Array(n + 1);
    this.offsets[0] = 0;
    for (let i = 0; i < n; i++) {
      this.offsets[i + 1] = this.offsets[i]! + this.heights[i]!;
    }
    this.dirty = false;
  }

  totalHeight(): number {
    this.recompute();
    return this.offsets[this.heights.length]!;
  }

  offsetOf(row: number): number {
    this.recompute();
    return this.offsets[Math.max(0, Math.min(row, this.heights.length))]!;
  }

  heightOf(row: number): number {
    return this.heights[row] ?? this.defaultHeight;
  }

  /** First row whose bottom edge is below `y` (i.e. the row containing y). */
  rowAtOffset(y: number): number {
    this.recompute();
    let lo = 0;
    let hi = this.heights.length;
    // Find smallest i with offsets[i+1] > y.
    while (lo < hi) {
      const mid = (lo + hi) >>> 1;
      if (this.offsets[mid + 1]! > y) hi = mid;
      else lo = mid + 1;
    }
    return lo;
  }
}

export interface VListDelegate {
  rowCount(): number;
  rowHeight(row: number): number;
  renderRow(el: HTMLElement, row: number): void;
  /** Optional: custom element factory (defaults to a div). */
  createRow?(): HTMLElement;
  /** Called after the visible window changes (e.g. to sync a partner). */
  onVisibleChange?(first: number, last: number): void;
}

const OVERSCAN = 6;

export class VList {
  readonly container: HTMLElement;
  private spacer: HTMLElement;
  private geometry: Geometry;
  private pool: HTMLElement[] = [];
  private visible = new Map<number, HTMLElement>();
  private renderQueued = false;
  private delegate: VListDelegate;

  constructor(
    delegate: VListDelegate,
    defaultRowHeight: number,
    className = "",
  ) {
    this.delegate = delegate;
    this.geometry = new Geometry(defaultRowHeight);
    this.container = document.createElement("div");
    this.container.className = className;
    this.container.style.position = "relative";
    this.container.style.overflowY = "auto";
    this.container.style.overflowX = "hidden";
    this.spacer = document.createElement("div");
    this.spacer.style.width = "1px";
    this.spacer.style.visibility = "hidden";
    this.container.appendChild(this.spacer);
    this.container.addEventListener("scroll", () => this.queueRender());
    // The first render can happen before layout (clientHeight ~0), leaving
    // only the overscan rows; re-render when the viewport size changes.
    new ResizeObserver(() => this.queueRender()).observe(this.container);
  }

  get scrollTop(): number {
    return this.container.scrollTop;
  }

  /** Row counts/heights/state changed — recompute and re-render everything
   *  (visible rows are re-configured, so selection/highlight state shows). */
  refresh(keepScroll = true): void {
    const top = keepScroll ? this.container.scrollTop : 0;
    this.geometry.setRowCount(this.delegate.rowCount());
    for (let i = 0; i < this.delegate.rowCount(); i++) {
      this.geometry.setHeight(i, this.delegate.rowHeight(i));
    }
    this.spacer.style.height = `${this.geometry.totalHeight()}px`;
    this.container.scrollTop = top;
    for (const [row, el] of this.visible) {
      if (row < this.delegate.rowCount()) this.delegate.renderRow(el, row);
    }
    this.render();
  }

  scrollToRow(row: number, align: "center" | "nearest" = "center"): void {
    const count = this.delegate.rowCount();
    if (row < 0 || row >= count) return;
    const viewH = this.container.clientHeight;
    const rowTop = this.geometry.offsetOf(row);
    const rowBottom = rowTop + this.geometry.heightOf(row);
    let target: number;
    if (align === "center") {
      target = rowTop + this.geometry.heightOf(row) / 2 - viewH / 2;
    } else {
      const cur = this.container.scrollTop;
      if (rowTop >= cur && rowBottom <= cur + viewH) return;
      target = rowTop < cur ? rowTop : rowBottom - viewH;
    }
    const maxY = Math.max(0, this.geometry.totalHeight() - viewH);
    this.container.scrollTop = Math.max(0, Math.min(target, maxY));
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
    const scrollTop = this.container.scrollTop;
    const viewH = this.container.clientHeight;
    const first = Math.max(0, this.geometry.rowAtOffset(scrollTop) - OVERSCAN);
    const last = Math.min(
      this.delegate.rowCount() - 1,
      this.geometry.rowAtOffset(scrollTop + viewH) + OVERSCAN,
    );

    // Recycle rows that left the window.
    for (const [row, el] of this.visible) {
      if (row < first || row > last) {
        el.remove();
        this.pool.push(el);
        this.visible.delete(row);
      }
    }
    // Render new rows.
    for (let row = first; row <= last; row++) {
      if (this.visible.has(row)) continue;
      const el = this.pool.pop() ?? this.delegate.createRow?.() ?? document.createElement("div");
      el.style.position = "absolute";
      el.style.left = "0";
      el.style.right = "0";
      el.style.top = "0";
      this.delegate.renderRow(el, row);
      el.style.transform = `translateY(${this.geometry.offsetOf(row)}px)`;
      el.style.height = `${this.geometry.heightOf(row)}px`;
      this.container.appendChild(el);
      this.visible.set(row, el);
    }
    // Keep positions fresh (heights may have changed).
    for (const [row, el] of this.visible) {
      el.style.transform = `translateY(${this.geometry.offsetOf(row)}px)`;
      el.style.height = `${this.geometry.heightOf(row)}px`;
    }
    this.delegate.onVisibleChange?.(first, last);
  }
}
