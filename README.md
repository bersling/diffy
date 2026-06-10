# diffy

A native macOS side-by-side diff viewer for git — a clone of IntelliJ's diff
viewer / GitLab's compare view, launched from the command line.

Pure Swift + AppKit, zero dependencies, single ~300 KB binary.

![diffy](https://img.shields.io/badge/macOS-11%2B-blue)

## Usage

Run it inside any git repository:

```sh
diffy                              # open the branch-selection wizard
diffy HEAD                         # HEAD vs working tree
diffy master                       # master vs working tree
diffy master develop               # branch vs branch
diffy origin/master origin/develop # remote refs work too
diffy v1.0.0 v2.0.0                # tags, SHAs, anything git rev-parse accepts
diffy master..develop              # same as: diffy master develop
diffy master...develop             # merge-base(master, develop) vs develop (GitLab MR semantics)
diffy master develop -- src/       # limit to paths
```

## Features

- **Branch wizard** — plain `diffy` opens a picker: "Branch with diffs" and
  "Target branch", each with a local/remote toggle and live search
- **Collapsible folder tree** sidebar with status badges (A/M/D/R/C/T), file
  counts per folder, and compressed single-child directory chains
- **Side-by-side panes** with synchronized vertical scrolling and aligned rows
- **Intra-line highlights** — the changed part of a modified line is emphasized,
  IntelliJ-style (blue = modified, green = added, red = deleted)
- **Collapsed unchanged lines** — long unchanged runs fold behind a
  "⋯ 42 unchanged lines ⋯" bar (3 context lines kept around changes); click to
  expand, ⌘E expands all
- **Change navigation** — jump between change blocks, with a "Change 3 of 12" counter
- **Line numbers**, hatched placeholders for inserted/removed regions
- **Dark & light mode**, follows the system appearance
- Binary file detection, rename detection, tab expansion, unicode, fast on 10k-line files

## Keys

| Key | Action |
|-----|--------|
| `n` / `p` (or `F7` / `⇧F7`, or `⌘J` / `⌘K`) | next / previous change |
| `]` / `[` (or `⌘↓` / `⌘↑`) | next / previous file |
| `⌘E` | expand all unchanged lines |
| `↑` / `↓` in the sidebar | switch files |
| `⌘W` / `⌘Q` | close / quit |

## Build & install

Requires Xcode command-line tools (uses only the system Swift toolchain and AppKit).

```sh
make install        # builds and symlinks into ~/.local/bin/diffy
make dist           # universal binary, zipped (dist/diffy.zip) for sharing
make pkg            # macOS installer (dist/diffy-1.0.pkg) with uninstaller
```

Or manually:

```sh
swiftc -O -swift-version 5 -o diffy Sources/*.swift
```

### Uninstall

- Installed via `make install`: `make uninstall`
- Installed via the .pkg: `sudo /usr/local/share/diffy/uninstall.sh` — removes
  the binary, the share directory, the pkg receipt, and the per-user
  preferences file (`~/Library/Preferences/diffy.plist`). diffy writes nothing
  else to the system.

## Scripting

`diffy --dump master develop` prints the computed side-by-side diff as text and
exits without opening a window — handy for testing and scripting.
