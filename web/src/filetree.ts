// Sidebar file tree — port of FileNode + SidebarViewController. Virtualized
// via VList; supports expand/collapse, single-child-chain compression, and
// case-insensitive path filtering.
import type { ChangedFileJSON } from "../shared/model.ts";
import { VList } from "./vlist.ts";

const ROW_HEIGHT = 24;
const INDENT = 13;

class FileNode {
  children: FileNode[] = [];
  parent: FileNode | null = null;
  name: string;
  fileIndex: number | null;

  constructor(name: string, fileIndex: number | null = null) {
    this.name = name;
    this.fileIndex = fileIndex;
  }

  get isDir(): boolean {
    return this.fileIndex === null;
  }

  fileCount(): number {
    if (!this.isDir) return 1;
    return this.children.reduce((sum, c) => sum + c.fileCount(), 0);
  }

  /** Builds a directory tree from the changed files (carrying their global
   *  session indices), with single-child directory chains compressed
   *  ("src/main/java" style). */
  static buildTree(files: { index: number; file: ChangedFileJSON }[]): {
    root: FileNode;
    byIndex: Map<number, FileNode>;
  } {
    const root = new FileNode("");
    const byIndex = new Map<number, FileNode>();

    for (const { index, file } of files) {
      const components = file.displayPath.split("/");
      let node = root;
      for (const dir of components.slice(0, -1)) {
        let next = node.children.find((c) => c.isDir && c.name === dir) ?? null;
        if (!next) {
          next = new FileNode(dir);
          node.children.push(next);
        }
        node = next;
      }
      const leaf = new FileNode(components[components.length - 1] ?? file.displayPath, index);
      node.children.push(leaf);
      byIndex.set(index, leaf);
    }

    const sortAndCompress = (node: FileNode): void => {
      for (let i = 0; i < node.children.length; i++) {
        let child = node.children[i]!;
        if (child.isDir) {
          // Compress chains of single-child directories into one node.
          while (child.children.length === 1 && child.children[0]!.isDir) {
            const only = child.children[0]!;
            const combined = new FileNode(`${child.name}/${only.name}`);
            combined.children = only.children;
            child = combined;
            node.children[i] = combined;
          }
          sortAndCompress(node.children[i]!);
        }
      }
      node.children.sort((a, b) => {
        if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
        return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
      });
    };
    sortAndCompress(root);

    const assignParents = (node: FileNode): void => {
      for (const child of node.children) {
        child.parent = node;
        assignParents(child);
      }
    };
    assignParents(root);
    return { root, byIndex };
  }
}

interface TreeRow {
  node: FileNode;
  depth: number;
}

const FOLDER_SVG =
  '<svg viewBox="0 0 16 16" class="folder"><path d="M1.75 2.5A1.75 1.75 0 0 0 0 4.25v7.5C0 12.72.78 13.5 1.75 13.5h12.5A1.75 1.75 0 0 0 16 11.75v-6A1.75 1.75 0 0 0 14.25 4H7.06a.75.75 0 0 1-.53-.22L5.22 2.47a.75.75 0 0 0-.53-.22H1.75z"/></svg>';

export class Sidebar {
  readonly root: HTMLElement;
  onSelect: ((fileIndex: number) => void) | null = null;

  private files: ChangedFileJSON[];
  private treeRoot = new FileNode("");
  private byIndex = new Map<number, FileNode>();
  private collapsed = new Set<FileNode>();
  private rows: TreeRow[] = [];
  private selectedFileIndex: number | null = null;
  private filterText = "";
  private countLabel: HTMLElement;
  private filterInput: HTMLInputElement;
  private list: VList;

  constructor(files: ChangedFileJSON[]) {
    this.files = files;
    this.root = document.createElement("div");
    this.root.className = "sidebar";

    const header = document.createElement("div");
    header.className = "sidebar-header";
    this.countLabel = document.createElement("span");
    this.countLabel.className = "count";
    const collapseBtn = document.createElement("button");
    collapseBtn.className = "icon";
    collapseBtn.title = "Collapse All Folders";
    collapseBtn.textContent = "▸▸";
    collapseBtn.addEventListener("click", () => this.collapseAll());
    const expandBtn = document.createElement("button");
    expandBtn.className = "icon";
    expandBtn.title = "Expand All Folders";
    expandBtn.textContent = "▾▾";
    expandBtn.addEventListener("click", () => this.expandAll());
    header.append(this.countLabel, collapseBtn, expandBtn);

    const filterWrap = document.createElement("div");
    filterWrap.className = "sidebar-filter";
    this.filterInput = document.createElement("input");
    this.filterInput.type = "search";
    this.filterInput.placeholder = "Filter files…";
    this.filterInput.addEventListener("input", () => this.applyFilter(this.filterInput.value));
    filterWrap.appendChild(this.filterInput);

    const divider = document.createElement("div");
    divider.className = "divider-h";

    this.list = new VList(
      {
        rowCount: () => this.rows.length,
        rowHeight: () => ROW_HEIGHT,
        renderRow: (el, row) => this.renderRow(el, row),
        createRow: () => document.createElement("div"),
      },
      ROW_HEIGHT,
      "sidebar-list",
    );

    this.root.append(header, filterWrap, divider, this.list.container);
    this.rebuildTree();
  }

  private rebuildTree(): void {
    const query = this.filterText.trim();
    let subset: { index: number; file: ChangedFileJSON }[];
    if (!query) {
      subset = this.files.map((file, index) => ({ index, file }));
      this.countLabel.textContent = `${this.files.length} file${this.files.length === 1 ? "" : "s"}`;
    } else {
      subset = this.files
        .map((file, index) => ({ index, file }))
        .filter(({ file }) => file.displayPath.toLowerCase().includes(query.toLowerCase()));
      this.countLabel.textContent = `${subset.length} of ${this.files.length}`;
    }
    const { root, byIndex } = FileNode.buildTree(subset);
    this.treeRoot = root;
    this.byIndex = byIndex;
    this.collapsed.clear();
    this.rebuildRows();
  }

  private rebuildRows(): void {
    const rows: TreeRow[] = [];
    const walk = (node: FileNode, depth: number) => {
      for (const child of node.children) {
        rows.push({ node: child, depth });
        if (child.isDir && !this.collapsed.has(child)) {
          walk(child, depth + 1);
        }
      }
    };
    walk(this.treeRoot, 0);
    this.rows = rows;
    this.list.refresh();
  }

  private renderRow(el: HTMLElement, row: number): void {
    const { node, depth } = this.rows[row]!;
    const selected = node.fileIndex !== null && node.fileIndex === this.selectedFileIndex;
    el.className = "tree-row" + (selected ? " selected" : "");
    el.style.paddingLeft = `${2 + depth * INDENT}px`;
    el.textContent = "";

    if (node.isDir) {
      const disclosure = document.createElement("span");
      disclosure.className = "disclosure" + (this.collapsed.has(node) ? "" : " open");
      disclosure.textContent = "▸";
      el.appendChild(disclosure);
      const folder = document.createElement("span");
      folder.innerHTML = FOLDER_SVG;
      el.appendChild(folder);
    } else {
      const spacer = document.createElement("span");
      spacer.style.width = "13px";
      spacer.style.flex = "none";
      el.appendChild(spacer);
      const file = this.files[node.fileIndex!]!;
      const badge = document.createElement("span");
      badge.className = "badge";
      badge.textContent = file.status;
      const color = `var(--status-${statusName(file.status)})`;
      badge.style.background = selected
        ? `color-mix(in srgb, ${color} 45%, transparent)`
        : `color-mix(in srgb, ${color} 18%, transparent)`;
      badge.style.color = selected ? "white" : color;
      el.appendChild(badge);
    }

    const name = document.createElement("span");
    name.className = "name" + (node.isDir ? " dir" : "");
    name.textContent = node.name;
    el.appendChild(name);

    if (node.isDir) {
      const count = document.createElement("span");
      count.className = "filecount secondary";
      count.textContent = String(node.fileCount());
      el.appendChild(count);
    }

    el.onmousedown = (e) => {
      if (e.button !== 0) return;
      if (node.isDir) {
        if (this.collapsed.has(node)) this.collapsed.delete(node);
        else this.collapsed.add(node);
        this.rebuildRows();
      } else {
        this.selectedFileIndex = node.fileIndex;
        this.list.refresh();
        if (node.fileIndex !== null) this.onSelect?.(node.fileIndex);
      }
    };
  }

  private applyFilter(query: string): void {
    this.filterText = query;
    this.rebuildTree();
    // Preserve selection if the file is still visible.
    if (this.selectedFileIndex !== null && this.byIndex.has(this.selectedFileIndex)) {
      this.scrollToFile(this.selectedFileIndex, false);
    }
  }

  /** Test hook (URL param): drive the filter as if typed into the field. */
  setFilter(query: string): void {
    this.filterInput.value = query;
    this.applyFilter(query);
  }

  expandAll(): void {
    this.collapsed.clear();
    this.rebuildRows();
  }

  collapseAll(): void {
    this.collapsed.clear();
    const walk = (node: FileNode) => {
      for (const child of node.children) {
        if (child.isDir) {
          this.collapsed.add(child);
          walk(child);
        }
      }
    };
    walk(this.treeRoot);
    this.rebuildRows();
  }

  /** Select a file, clearing an active filter if it hides the file
   *  (ported selectFile semantics). */
  selectFile(index: number): void {
    if (!this.byIndex.has(index) && this.filterText) {
      this.filterInput.value = "";
      this.filterText = "";
      this.rebuildTree();
    }
    const node = this.byIndex.get(index);
    if (!node) return;
    // Expand collapsed ancestors so the row exists.
    let p = node.parent;
    while (p && p !== this.treeRoot) {
      this.collapsed.delete(p);
      p = p.parent;
    }
    this.selectedFileIndex = index;
    this.rebuildRows();
    this.scrollToFile(index, false);
  }

  private scrollToFile(index: number, _animated: boolean): void {
    const row = this.rows.findIndex((r) => r.node.fileIndex === index);
    if (row >= 0) this.list.scrollToRow(row, "nearest");
  }

  get selectedIndex(): number | null {
    return this.selectedFileIndex;
  }
}

function statusName(letter: string): string {
  switch (letter) {
    case "A": return "added";
    case "D": return "deleted";
    case "M": return "modified";
    case "R": return "renamed";
    case "C": return "copied";
    default: return "typeChanged";
  }
}
