// Font metrics — the web equivalent of Theme.charWidth / Theme.rowHeight.
// The code font is monospace, so text widths are exact multiples of the
// measured advance width; canvas measureText covers the rare wide-char case.

export const ROW_HEIGHT = 18;
export const CODE_FONT = "12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace";

let measuredCharWidth = 7.23; // Menlo 12px fallback

const canvas = document.createElement("canvas");
const ctx = canvas.getContext("2d")!;

export function initMetrics(): void {
  ctx.font = CODE_FONT;
  measuredCharWidth = ctx.measureText("0").width;
}

export function charWidth(): number {
  return measuredCharWidth;
}

/** Pixel width of a text run in the code font. */
export function textWidth(text: string): number {
  ctx.font = CODE_FONT;
  return ctx.measureText(text).width;
}

/** Number of wrapped visual lines for `text` in a column `availWidth` wide.
 *  Fast path: code-point count × charWidth (exact for monospace ASCII). */
export function wrappedLineCount(text: string, availWidth: number): number {
  const cpCount = [...text].length;
  if (cpCount * measuredCharWidth <= availWidth) return 1;
  return Math.max(1, Math.ceil(textWidth(text) / availWidth));
}

/** Gutter width for a max line number (mirrors DiffPane.setContent). */
export function gutterWidth(maxLineNumber: number): number {
  const digits = Math.max(2, String(Math.max(maxLineNumber, 1)).length);
  return digits * measuredCharWidth + 20;
}

/** Middle-truncate a path like AppKit's byTruncatingMiddle. */
export function truncateMiddle(text: string, maxWidth: number, font: string): string {
  ctx.font = font;
  if (ctx.measureText(text).width <= maxWidth) return text;
  const chars = [...text];
  let head = Math.ceil(chars.length / 2);
  let tail = chars.length - head;
  const ellipsis = "…";
  while (head > 1 || tail > 1) {
    const candidate = chars.slice(0, head).join("") + ellipsis + chars.slice(chars.length - tail).join("");
    if (ctx.measureText(candidate).width <= maxWidth) return candidate;
    if (head >= tail) head--;
    else tail--;
  }
  return ellipsis;
}
