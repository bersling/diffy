# diffy-web — browser-based diff viewer (local server + web UI)

A port of the native Swift/AppKit diffy to web technologies. Same CLI
semantics, same feature set — but rendered in your browser via a local
Node.js server.

## Requirements

- **Node ≥ 22.6** (TypeScript type-stripping is built in — no compiler needed)
- npm (comes with Node)
- A modern browser (Chrome/Edge/Firefox/Safari)

## Quick start

```sh
cd web
npm ci
npm run build
npm start -- master develop
```

This starts the server, opens a browser tab, and shows the diff between
`master` and `develop` (merge-base, i.e. `master...develop` semantics —
only your changes, not the base's).

## CLI usage

```sh
npm start -- [options] [<ref> [<ref>]] [-- <path>...]
```

| Example | What it does |
|---------|--------------|
| `npm start` | Branch wizard |
| `node server/index.ts <gitlab-mr-url>` | GitLab MR with inline review |
| `npm start -- HEAD` | Working tree vs HEAD |
| `node server/index.ts master develop` | Changes in develop since merge base |
| `npm start -- --two-dot a b` | Exact tip vs tip |
| `node server/index.ts --dump master develop` | Headless text dump (scripting) |

Flags: `--two-dot`, `--no-fetch`, `--wrap`, `--dump`, `--port <n>`,
`--no-open`, `-h`.

## API endpoints (for scripting)

The server listens on `127.0.0.1` and exposes a JSON API:

| Endpoint | Returns |
|----------|---------|
| `GET /api/state` | Session or wizard mode |
| `GET /api/wizard` | Branch lists for the picker |
| `POST /api/compare` | Build a session from source + target |
| `GET /api/file/:index` | File diff + inline review threads |
| `GET /api/comments` | All review thread locations |
| `GET /api/mr/members` | Project members for @mentions |
| `POST /api/mr/reply` | Reply to a discussion |
| `POST /api/mr/comment` | New comment (send-now or draft) |
| `POST /api/mr/discard` | Delete draft notes |
| `POST /api/mr/publish` | Publish all pending drafts |

## Differences from the native macOS app

- **`--screenshot`** — not implemented; use headless Chrome instead.
- **⌘J / ⌘K** — not bound (browser conflicts). Use `n`/`p` or `F7`/`⇧F7`.
- **⌘E** (expand all folds), **⌥⌘←/→** — not bound (browser conflicts).
  Use the header button or URL param `?expand-all`.
- Native test flags are **URL params**: `?file=N&change=N&expand-all&filter=q&wrap=0|1&theme=light|dark`
- **`DIFFY_FAKE_MR=1`** env var attaches an in-memory fake GitLab MR
  backend for UI testing without a real GitLab server.

## Performance

- Virtual scrolling: only the visible + overscan rows are DOM elements.
  Thousands of rows, tens of kilobytes of DOM at any time.
- Wrap heights computed via canvas `measureText` (cached); 100k rows
  scroll at 60 fps.
- Diff computation runs server-side, lazy per file; results are cached.

## Development

```sh
npm run typecheck   # tsc --noEmit
npm run build       # vite build → web/dist/
npm start           # node server/index.ts (frontend must be built first)
```
