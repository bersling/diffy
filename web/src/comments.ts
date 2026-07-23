// Review-comment UI: thread cards (ported from CommentRowView), the comment
// dialog with @mention autocomplete (ported from MentionTextView), and the
// all-comments overview popover (ported from CommentsListController).
import type { GitLabUserJSON, MRNoteJSON, MRThreadJSON } from "../shared/model.ts";

// MARK: - avatar colors (djb2 hash → hue, ported)

function avatarColor(name: string): string {
  let h = 5381;
  for (const b of new TextEncoder().encode(name)) {
    h = ((h << 5) + h + b) | 0;
  }
  const hue = Math.abs(h) % 360;
  return `hsl(${hue} 50% 60%)`;
}

// MARK: - comment card DOM

export interface CommentCardHandlers {
  onReply?: (thread: MRThreadJSON) => void;
  onDiscard?: (thread: MRThreadJSON) => void;
}

function buildNote(note: MRNoteJSON): HTMLElement {
  const el = document.createElement("div");
  el.className = "comment-note";
  const authorLine = document.createElement("div");
  authorLine.className = "authorline";
  const avatar = document.createElement("span");
  avatar.className = "avatar";
  avatar.style.background = avatarColor(note.author);
  const author = document.createElement("span");
  author.className = "author";
  author.textContent = note.author;
  const date = document.createElement("span");
  date.className = "date" + (note.isPending ? " pending" : "");
  date.textContent = note.isPending ? "Pending" : note.createdAt.slice(0, 10);
  authorLine.append(avatar, author, date);
  const body = document.createElement("div");
  body.className = "body";
  body.textContent = note.body;
  el.append(authorLine, body);
  return el;
}

/** Builds the card DOM. Used both for real rows and the offscreen measurer,
 *  so heights always agree. */
export function buildCommentCard(
  thread: MRThreadJSON,
  handlers: CommentCardHandlers | null,
): HTMLElement {
  const card = document.createElement("div");
  card.className = "comment-card";
  if (thread.resolved) card.classList.add("resolved");
  if (thread.draftIDs.length > 0) card.classList.add("pending");

  if (thread.isDraft || thread.resolved) {
    const badge = document.createElement("span");
    badge.className = "badge " + (thread.isDraft ? "draft" : "resolved");
    badge.textContent = thread.isDraft ? "Pending review" : "Resolved ✓";
    card.appendChild(badge);
  }

  for (const note of thread.notes) {
    card.appendChild(buildNote(note));
  }

  const actions = document.createElement("div");
  actions.className = "comment-actions";
  if (!thread.isDraft) {
    const reply = document.createElement("button");
    reply.textContent = "Reply…";
    reply.addEventListener("click", (e) => {
      e.stopPropagation();
      handlers?.onReply?.(thread);
    });
    actions.appendChild(reply);
  }
  if (thread.draftIDs.length > 0) {
    const discard = document.createElement("button");
    discard.textContent = "Discard Draft";
    discard.addEventListener("click", (e) => {
      e.stopPropagation();
      handlers?.onDiscard?.(thread);
    });
    actions.appendChild(discard);
  }
  card.appendChild(actions);
  return card;
}

// MARK: - height measurement (offscreen, identical DOM)

let measureHost: HTMLElement | null = null;
const heightCache = new Map<string, number>();

function getMeasureHost(): HTMLElement {
  if (!measureHost) {
    measureHost = document.createElement("div");
    measureHost.style.position = "absolute";
    measureHost.style.left = "-10000px";
    measureHost.style.top = "0";
    measureHost.style.visibility = "hidden";
    measureHost.style.pointerEvents = "none";
    document.body.appendChild(measureHost);
  }
  return measureHost;
}

/** Height of a comment row's card (excluding the 8px vertical margins). */
export function measureCommentHeight(thread: MRThreadJSON, cardWidth: number): number {
  const width = Math.max(160, Math.round(cardWidth));
  const key = `${thread.id}@${width}:${thread.notes.length}:${thread.draftIDs.join(",")}`;
  const cached = heightCache.get(key);
  if (cached !== undefined) return cached;
  const host = getMeasureHost();
  const card = buildCommentCard(thread, null);
  card.style.position = "static";
  card.style.width = `${width}px`;
  host.appendChild(card);
  const height = card.offsetHeight;
  card.remove();
  heightCache.set(key, height);
  return height;
}

export function invalidateCommentHeights(): void {
  heightCache.clear();
}

// MARK: - @mention matching (ported from MentionTextView.match)

export function matchMembers(
  members: GitLabUserJSON[],
  prefix: string,
  limit = 8,
): GitLabUserJSON[] {
  const lower = prefix.toLowerCase();
  if (lower.length === 0) return members.slice(0, limit);
  const byUsername: GitLabUserJSON[] = [];
  const byName: GitLabUserJSON[] = [];
  for (const m of members) {
    if (m.username.toLowerCase().startsWith(lower)) byUsername.push(m);
    else if (m.name.toLowerCase().includes(lower)) byName.push(m);
  }
  return [...byUsername, ...byName].slice(0, limit);
}

// MARK: - mention-enabled textarea

/** A textarea with an @-mention completion dropdown, mirroring the GitLab
 *  UX (and the native MentionTextView). */
export class MentionTextArea {
  readonly element: HTMLTextAreaElement;
  private menu: HTMLElement | null = null;
  private matches: GitLabUserJSON[] = [];
  private selected = 0;
  private mentionStart = 0; // index of '@' in the value
  private membersProvider: () => GitLabUserJSON[];

  constructor(membersProvider: () => GitLabUserJSON[]) {
    this.membersProvider = membersProvider;
    this.element = document.createElement("textarea");
    this.element.addEventListener("input", () => this.updateMentionState());
    this.element.addEventListener("keydown", (e) => this.onKeyDown(e));
    this.element.addEventListener("blur", () => {
      // Delay so a click on the menu still registers.
      setTimeout(() => this.dismiss(), 150);
    });
  }

  get value(): string {
    return this.element.value;
  }

  focus(): void {
    this.element.focus();
  }

  private onKeyDown(e: KeyboardEvent): void {
    if (!this.menu) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      this.moveSelection(1);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      this.moveSelection(-1);
    } else if (e.key === "Enter" || e.key === "Tab") {
      e.preventDefault();
      this.acceptSelection();
    } else if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      this.dismiss();
    }
  }

  /** Detects an `@token` ending at the caret and shows/updates the popup. */
  private updateMentionState(): void {
    const members = this.membersProvider();
    const text = this.element.value;
    const caret = this.element.selectionStart;
    if (members.length === 0 || caret !== this.element.selectionEnd) {
      this.dismiss();
      return;
    }
    let i = caret;
    while (i > 0) {
      const c = text[i - 1]!;
      if (c === "@") {
        const prefix = text.slice(i, caret);
        // Only trigger at start or after whitespace/'('.
        if (i >= 2) {
          const before = text[i - 2]!;
          if (!/\s/.test(before) && before !== "(") {
            this.dismiss();
            return;
          }
        }
        this.showMatches(prefix, i - 1);
        return;
      }
      // mention tokens are word chars only
      if (/[\p{L}\p{N}_\-.]/u.test(c)) {
        i -= 1;
      } else {
        break;
      }
    }
    this.dismiss();
  }

  private showMatches(prefix: string, mentionAt: number): void {
    this.matches = matchMembers(this.membersProvider(), prefix);
    if (this.matches.length === 0) {
      this.dismiss();
      return;
    }
    this.mentionStart = mentionAt;
    if (!this.menu) {
      this.menu = document.createElement("div");
      this.menu.className = "mention-menu";
      document.body.appendChild(this.menu);
      this.menu.addEventListener("mousedown", (e) => {
        e.preventDefault(); // keep textarea focus
        const row = (e.target as HTMLElement).closest<HTMLElement>(".mrow");
        if (row) {
          this.selected = Number(row.dataset.index);
          this.acceptSelection();
        }
      });
    }
    this.renderMenu();
    this.positionMenu();
  }

  private renderMenu(): void {
    if (!this.menu) return;
    this.menu.textContent = "";
    this.matches.forEach((user, index) => {
      const row = document.createElement("div");
      row.className = "mrow" + (index === this.selected ? " sel" : "");
      row.dataset.index = String(index);
      const u = document.createElement("span");
      u.className = "muser";
      u.textContent = `@${user.username}`;
      const n = document.createElement("span");
      n.className = "mname";
      n.textContent = user.name;
      row.append(u, n);
      this.menu!.appendChild(row);
    });
  }

  /** Positions the menu below the caret using the mirror-div technique. */
  private positionMenu(): void {
    if (!this.menu) return;
    const ta = this.element;
    const mirror = document.createElement("div");
    const style = getComputedStyle(ta);
    for (const prop of [
      "font-family", "font-size", "font-weight", "line-height", "letter-spacing",
      "padding-top", "padding-right", "padding-bottom", "padding-left",
      "border-top-width", "border-right-width", "border-bottom-width", "border-left-width",
      "box-sizing",
    ]) {
      mirror.style.setProperty(prop, style.getPropertyValue(prop));
    }
    mirror.style.position = "absolute";
    mirror.style.visibility = "hidden";
    mirror.style.whiteSpace = "pre-wrap";
    mirror.style.wordBreak = "break-word";
    mirror.style.width = style.width;
    mirror.style.top = "0";
    mirror.style.left = "-10000px";
    mirror.textContent = ta.value.slice(0, this.mentionStart);
    const marker = document.createElement("span");
    marker.textContent = "@";
    mirror.appendChild(marker);
    document.body.appendChild(mirror);
    const taRect = ta.getBoundingClientRect();
    const markerOffset = { top: marker.offsetTop, left: marker.offsetLeft };
    mirror.remove();
    const lineHeight = parseFloat(style.lineHeight) || 16;
    const top = taRect.top + markerOffset.top - ta.scrollTop + lineHeight;
    const left = taRect.left + markerOffset.left - ta.scrollLeft;
    const menuHeight = this.matches.length * 22 + 2;
    this.menu.style.top = `${Math.min(top, window.innerHeight - menuHeight - 8)}px`;
    this.menu.style.left = `${Math.min(left, window.innerWidth - 268)}px`;
  }

  private moveSelection(delta: number): void {
    this.selected = Math.max(0, Math.min(this.matches.length - 1, this.selected + delta));
    this.renderMenu();
  }

  private acceptSelection(): void {
    const user = this.matches[this.selected];
    if (!user) {
      this.dismiss();
      return;
    }
    const caret = this.element.selectionStart;
    const insertion = `@${user.username} `;
    this.element.value =
      this.element.value.slice(0, this.mentionStart) + insertion + this.element.value.slice(caret);
    const newCaret = this.mentionStart + insertion.length;
    this.element.setSelectionRange(newCaret, newCaret);
    this.dismiss();
  }

  private dismiss(): void {
    this.menu?.remove();
    this.menu = null;
    this.matches = [];
    this.selected = 0;
  }
}

// MARK: - comment dialog

export interface CommentDialogResult {
  body: string;
  sendNow: boolean;
}

/** Modal text-entry dialog (ported from ContentViewController.commentDialog).
 *  "Add to Review" batches into a draft; "Send Now" posts immediately. */
export function commentDialog(
  title: string,
  membersProvider: () => GitLabUserJSON[],
): Promise<CommentDialogResult | null> {
  return new Promise((resolve) => {
    const backdrop = document.createElement("div");
    backdrop.className = "modal-backdrop";
    const modal = document.createElement("div");
    modal.className = "modal";
    const h = document.createElement("h2");
    h.textContent = title;
    const info = document.createElement("div");
    info.className = "info";
    info.textContent =
      "“Add to Review” batches the comment; submit the whole review at once with the Submit Review button.";
    const text = new MentionTextArea(membersProvider);
    const buttons = document.createElement("div");
    buttons.className = "buttons";
    const cancel = document.createElement("button");
    cancel.textContent = "Cancel";
    const sendNow = document.createElement("button");
    sendNow.textContent = "Send Now";
    const addToReview = document.createElement("button");
    addToReview.textContent = "Add to Review";
    addToReview.className = "primary";
    buttons.append(cancel, sendNow, addToReview);
    modal.append(h, info, text.element, buttons);
    backdrop.appendChild(modal);
    document.body.appendChild(backdrop);
    text.focus();

    let done = false;
    const finish = (result: CommentDialogResult | null) => {
      if (done) return;
      done = true;
      backdrop.remove();
      document.removeEventListener("keydown", onKey, true);
      resolve(result);
    };
    const submit = (sendNowFlag: boolean) => {
      const body = text.value.trim();
      finish(body.length > 0 ? { body, sendNow: sendNowFlag } : null);
    };
    cancel.addEventListener("click", () => finish(null));
    sendNow.addEventListener("click", () => submit(true));
    addToReview.addEventListener("click", () => submit(false));
    backdrop.addEventListener("mousedown", (e) => {
      if (e.target === backdrop) finish(null);
    });
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        finish(null);
      }
    };
    document.addEventListener("keydown", onKey, true);
  });
}

// MARK: - all-comments overview popover

export interface CommentOverviewEntry {
  fileIndex: number;
  line: number;
  path: string;
  thread: MRThreadJSON;
}

export function showCommentsPopover(
  anchor: HTMLElement,
  entries: CommentOverviewEntry[],
  onSelect: (entry: CommentOverviewEntry) => void,
): void {
  const pop = document.createElement("div");
  pop.className = "comments-popover";
  for (const entry of entries) {
    const row = document.createElement("div");
    row.className = "crow";
    const head = document.createElement("div");
    head.className = "chead";
    const fileName = entry.path.split("/").pop() ?? entry.path;
    head.textContent = `${fileName}:${entry.line}`;
    if (entry.thread.resolved) {
      const ok = document.createElement("span");
      ok.className = "ok";
      ok.textContent = "  ✓";
      head.appendChild(ok);
    } else if (entry.thread.draftIDs.length > 0) {
      const pend = document.createElement("span");
      pend.className = "pend";
      pend.textContent = "  • pending";
      head.appendChild(pend);
    }
    const snip = document.createElement("div");
    snip.className = "csnip";
    const first = entry.thread.notes[0];
    snip.textContent = `${first?.author ?? ""}  ${(first?.body ?? "").replace(/\n/g, " ").slice(0, 80)}`;
    row.append(head, snip);
    row.addEventListener("click", () => {
      close();
      onSelect(entry);
    });
    pop.appendChild(row);
  }
  document.body.appendChild(pop);
  const rect = anchor.getBoundingClientRect();
  pop.style.top = `${rect.bottom + 4}px`;
  pop.style.left = `${Math.max(8, rect.right - 400)}px`;

  const onDown = (e: MouseEvent) => {
    if (!pop.contains(e.target as Node)) close();
  };
  const onKey = (e: KeyboardEvent) => {
    if (e.key === "Escape") close();
  };
  function close() {
    pop.remove();
    document.removeEventListener("mousedown", onDown, true);
    document.removeEventListener("keydown", onKey, true);
  }
  document.addEventListener("mousedown", onDown, true);
  document.addEventListener("keydown", onKey, true);
}
