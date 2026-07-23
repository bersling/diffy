# diffy

A side-by-side git diff viewer for the browser, launched from the command
line — a clone of IntelliJ's diff viewer / GitLab's compare view.

Local Node.js server + framework-free web frontend, zero runtime dependencies.

## Requirements

- **Node ≥ 22.6** (TypeScript type-stripping is built in)
- A modern browser (Chrome, Edge, Firefox, Safari)

## Usage

Run it inside any git repository:

```sh
npm start -- master develop               # changes in develop since merge base
npm start                                  # open the branch-selection wizard
npm start -- HEAD                          # HEAD vs working tree
npm start -- origin/master origin/develop  # remote refs work too
npm start -- v1.0.0 v2.0.0                # tags, SHAs
npm start -- master develop -- src/        # limit to paths
```

Comparisons use the **merge base** by default (GitLab-MR / `...` semantics):
you only see changes made on the right-hand branch — commits the base branch
is ahead by are never shown as phantom reverts. For an exact tip-vs-tip
comparison use `--two-dot master develop` (or `master..develop`).

Remote refs are **fetched automatically**: `diffy origin/a origin/b` fetches
those branches first so the diff reflects the actual state on the remote, and
warns if a branch was deleted there. The wizard fetches + prunes all remotes
so its branch lists are live. Skip all fetching with `--no-fetch` (offline).

### Headless mode

```sh
npm start -- --dump master develop
```

Prints the computed side-by-side diff as text and exits — handy for testing
and scripting.

## GitLab merge requests

```sh
npm start -- https://gitlab.example.com/group/project/-/merge_requests/123
```

Run inside the repo checkout: diffy queries the GitLab API for the MR, fetches
the right refs (including `refs/merge-requests/<iid>/head`, so merged or
deleted source branches still work), and opens the MR's exact diff with
**review comments inline** — threads appear under the lines they belong to,
resolved ones dimmed, commented lines never folded away. Each note carries a
colour-coded author dot and notes are separated by hairlines, so multi-reply
threads stay readable. **Reply** on any thread, or **right-click a line → Add
Comment** to start a new one.

Comments default to **Add to Review** (GitLab review batching): they stay
private drafts — shown as orange *Pending* cards with a Discard button — until
you publish them all at once with the **Submit Review (N)** button in the
header. "Send Now" posts immediately instead.

Type **`@`** in any comment to autocomplete project members (↑/↓ to navigate,
Enter/Tab/click to insert), so mentions notify the right people on GitLab.

The header's **Comments (N)** button opens an overview of every review thread
in the MR (file, line, author, snippet, resolved/pending state) — click one to
jump straight to that line.

The token is auto-discovered (first match wins, invalid tokens are skipped):
`$DIFFY_GITLAB_TOKEN` → `~/.config/diffy/gitlab-token` → any gitlab MCP server
in `~/.claude.json` → `$GITLAB_TOKEN` / `$GITLAB_PERSONAL_ACCESS_TOKEN`.

**Token permissions:** create a [personal access token](https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html)
(GitLab → User settings → Access tokens) with the **`api`** scope — needed to
read merge requests/discussions *and* post comments. If you only want to view
MRs and comments (no posting), the read-only **`read_api`** scope is enough.
The token's user must have at least Reporter access to the project.

## Features

- **Branch wizard** — plain `diffy` opens a picker: "Branch with diffs" and
  "Target branch", each with a local/remote toggle and live search
- **Collapsible folder tree** sidebar with status badges (A/M/D/R/C/T), file
  counts per folder, compressed single-child directory chains, a **filter
  field** (live path search), and collapse-all / expand-all buttons
- **Syntax highlighting** — built-in tokenizer (no dependencies) with
  Xcode-style colors for Swift, Kotlin, Java, TypeScript/JavaScript, Python,
  Go, Rust, C/C++/ObjC, C#, Ruby, PHP, shell, SQL, YAML, JSON, CSS/SCSS,
  HTML/XML, TOML/INI, Dockerfile, and more
- **Side-by-side panes** with synchronized vertical scrolling and aligned rows
- **Intra-line highlights** — the changed part of a modified line is emphasized,
  IntelliJ-style (blue = modified, green = added, red = deleted)
- **Collapsed unchanged lines** — long unchanged runs fold behind a
  "⋯ 42 unchanged lines ⋯" bar (3 context lines kept around changes); click to
  expand, header button expands all
- **Line selection & copy** — click / shift-click / cmd-click to select lines in
  either pane, ⌘C or right-click → Copy
- **Change navigation** — jump between change blocks, with a "Change 3 of 12" counter
- **Line numbers**, hatched placeholders for inserted/removed regions
- **Dark & light mode**, follows the system appearance
- Binary file detection, rename detection, tab expansion, unicode, virtual
  scrolling (thousands of rows at 60 fps)

## Keys

| Key | Action |
|-----|--------|
| `n` / `p` (or `F7` / `⇧F7`) | next / previous change |
| `]` / `[` (or `⌘↓` / `⌘↑`) | next / previous file |
| `w` | toggle soft-wrap |
| `⌘C` | copy selected lines (click/shift-click/cmd-click to select; or right-click → Copy) |

## Install

```sh
make install        # builds the frontend and symlinks diffy into ~/.local/bin/diffy
```

Or manually:

```sh
cd web
npm ci
npm run build
node server/index.ts -- master develop
```

To launch `diffy` from anywhere, add `~/.local/bin` to your `$PATH`, then
run `make install`.

## Uninstall

```sh
make uninstall
```
