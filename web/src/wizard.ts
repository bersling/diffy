// Branch-selection wizard — port of Wizard.swift (BranchPicker +
// WizardWindowController). Shown when diffy-web starts without refs.
import type { SessionJSON, WizardJSON } from "../shared/model.ts";
import { api } from "./api.ts";
import { VList } from "./vlist.ts";

export const WORKING_TREE = "« Working Tree »";

interface Group {
  name: string;
  branches: string[];
}

class BranchPicker {
  readonly element: HTMLElement;
  selected: string | null = null;
  onSelectionChanged: (() => void) | null = null;

  private groups: Group[];
  private activeGroup = 0;
  private filtered: string[] = [];
  private search: HTMLInputElement;
  private tabs: HTMLElement;
  private list: VList;
  private selectedRow = -1;

  constructor(title: string, groups: Group[]) {
    this.groups = groups;
    this.element = document.createElement("div");
    this.element.className = "picker";

    const label = document.createElement("label");
    label.textContent = title;

    this.tabs = document.createElement("div");
    this.tabs.className = "tabs";
    groups.forEach((group, index) => {
      const tab = document.createElement("button");
      tab.textContent = group.name;
      tab.className = index === 0 ? "active" : "";
      tab.addEventListener("click", () => {
        this.activeGroup = index;
        this.search.value = "";
        for (const [i, t] of [...this.tabs.children].entries()) {
          t.classList.toggle("active", i === index);
        }
        this.refilter();
      });
      this.tabs.appendChild(tab);
    });

    this.search = document.createElement("input");
    this.search.type = "search";
    this.search.placeholder = "Filter branches…";
    this.search.addEventListener("input", () => this.refilter());

    this.list = new VList(
      {
        rowCount: () => this.filtered.length,
        rowHeight: () => 22,
        renderRow: (el, row) => this.renderRow(el, row),
        createRow: () => document.createElement("div"),
      },
      22,
      "blist",
    );

    this.element.append(label, this.tabs, this.search, this.list.container);
    this.refilter();
  }

  private renderRow(el: HTMLElement, row: number): void {
    el.className = "brow" + (row === this.selectedRow ? " selected" : "");
    el.textContent = this.filtered[row] ?? "";
    el.onmousedown = (e) => {
      if (e.button !== 0) return;
      this.selectRow(row);
    };
    el.ondblclick = () => {
      // Double-click confirms the wizard (native: row action).
      this.selectRow(row);
      this.onDoubleConfirm?.();
    };
  }

  onDoubleConfirm: (() => void) | null = null;

  private selectRow(row: number): void {
    this.selectedRow = row;
    this.selected = row >= 0 && row < this.filtered.length ? this.filtered[row]! : null;
    this.list.refresh();
    this.onSelectionChanged?.();
  }

  private refilter(): void {
    const base = this.groups[this.activeGroup]?.branches ?? [];
    const query = this.search.value.trim().toLowerCase();
    this.filtered = query
      ? base.filter((b) => b.toLowerCase().includes(query))
      : [...base];
    // Keep the previous choice if still visible, else pick the top match.
    if (this.selected && this.filtered.includes(this.selected)) {
      this.selectedRow = this.filtered.indexOf(this.selected);
    } else if (this.filtered.length > 0) {
      this.selectedRow = 0;
      this.selected = this.filtered[0]!;
    } else {
      this.selectedRow = -1;
      this.selected = null;
    }
    this.list.refresh();
    this.onSelectionChanged?.();
  }

  /** Select a branch by name, switching to whichever group contains it. */
  preselect(name: string): void {
    for (let gi = 0; gi < this.groups.length; gi++) {
      if (!this.groups[gi]!.branches.includes(name)) continue;
      this.activeGroup = gi;
      for (const [i, t] of [...this.tabs.children].entries()) {
        t.classList.toggle("active", i === gi);
      }
      this.refilter();
      const row = this.filtered.indexOf(name);
      if (row >= 0) {
        this.selectRow(row);
        this.list.scrollToRow(row, "center");
      }
      return;
    }
  }
}

export class Wizard {
  readonly root: HTMLElement;
  private errorEl!: HTMLElement;

  constructor(onConfirm: (session: SessionJSON) => void) {
    this.root = document.createElement("div");
    this.root.className = "wizard";
    this.root.innerHTML = `<div class="center-message">Loading branches…</div>`;
    const rootEl = this.root;

    void (async () => {
      let data: WizardJSON;
      try {
        data = await api.wizard();
      } catch (err) {
        rootEl.innerHTML = `<div class="center-message"></div>`;
        (rootEl.firstElementChild as HTMLElement).textContent = String(err);
        return;
      }

      const box = document.createElement("div");
      box.className = "wizard-box";
      const h1 = document.createElement("h1");
      h1.textContent = "diffy — Compare Branches";

      const sourceGroups: Group[] = [
        { name: "local", branches: [WORKING_TREE, ...data.locals] },
        ...data.remotes.map((r) => ({ name: r.name, branches: r.branches })),
      ];
      const targetGroups: Group[] = [
        { name: "local", branches: data.locals },
        ...data.remotes.map((r) => ({ name: r.name, branches: r.branches })),
      ];

      const sourcePicker = new BranchPicker("Branch with diffs", sourceGroups);
      const targetPicker = new BranchPicker("Target branch", targetGroups);

      this.errorEl = document.createElement("div");
      this.errorEl.className = "error";
      this.errorEl.style.display = "none";

      const buttons = document.createElement("div");
      buttons.className = "buttons";
      const showButton = document.createElement("button");
      showButton.className = "primary";
      showButton.textContent = "Show Diff";
      buttons.append(showButton);

      const updateEnabled = () => {
        showButton.disabled = !(sourcePicker.selected && targetPicker.selected);
      };
      sourcePicker.onSelectionChanged = updateEnabled;
      targetPicker.onSelectionChanged = updateEnabled;

      // Sensible defaults: current branch vs main/master/develop.
      if (data.current) sourcePicker.preselect(data.current);
      else sourcePicker.preselect(WORKING_TREE);
      const target =
        ["main", "master", "develop"].find((b) => data.locals.includes(b) && b !== data.current) ??
        data.locals.find((b) => b !== data.current);
      if (target) targetPicker.preselect(target);
      updateEnabled();

      let busy = false;
      const confirm = async () => {
        if (busy || !sourcePicker.selected || !targetPicker.selected) return;
        busy = true;
        showButton.disabled = true;
        this.errorEl.style.display = "none";
        try {
          const result = await api.compare(sourcePicker.selected, targetPicker.selected);
          if (!result.ok) {
            this.errorEl.textContent = result.message ?? "No differences";
            this.errorEl.style.display = "";
          } else if (result.session) {
            onConfirm(result.session);
          }
        } catch (err) {
          this.errorEl.textContent = `Cannot compare: ${err instanceof Error ? err.message : err}`;
          this.errorEl.style.display = "";
        } finally {
          busy = false;
          updateEnabled();
        }
      };
      showButton.addEventListener("click", () => void confirm());
      sourcePicker.onDoubleConfirm = () => void confirm();
      targetPicker.onDoubleConfirm = () => void confirm();
      box.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          void confirm();
        }
      });

      box.append(h1, sourcePicker.element, targetPicker.element, this.errorEl, buttons);
      rootEl.textContent = "";
      rootEl.appendChild(box);
    })();
  }
}
