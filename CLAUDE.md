# diffy — project instructions

## Workflow rules (from the project owner)

1. **Commit and push after every finished work item.** Don't batch multiple
   features into one push; when a feature/fix is done and verified, commit it
   with a descriptive message and push to `origin main` immediately.
2. **Security check before every push — this is a PUBLIC repo**
   (github.com/bersling/diffy). Before committing, verify the changes contain:
   - no secrets, tokens, API keys, or credentials
   - no `.env` or key/certificate files
   - no hardcoded user-specific paths (`/Users/...`) or other private info
   - build artifacts stay out of git (`web/dist/` and `web/node_modules/` are
     gitignored — keep it that way)
3. **Clean up after yourself before committing & pushing.** Remove anything
   that was only needed to get the work done: debug prints/flags, scratch and
   temp files, leftover test output, dead code from abandoned approaches.
   After the security scan, also eyeball `git status` for files that shouldn't
   exist and the diff for changes that shouldn't be in it.

## Build & test

### Build

```sh
make build          # same as: cd web && npm ci && npm run build
make install        # build + symlink ~/.local/bin/diffy
```

Headless verification (byte-identical to the native Swift version):

```sh
npm start -- --dump <ref> <ref>   # from web/
# or via the Makefile:
node web/server/index.ts --dump master develop
```

Test fixture: `/tmp/diffy-fixture` (master/develop branches, covers
modify/add/delete/rename/binary/unicode/nested dirs, bare remote at
/tmp/diffy-remote.git). Recreate if missing.

### Headless UI testing (without GitLab)

```sh
cd /tmp/diffy-fixture
DIFFY_FAKE_MR=1 node web/server/index.ts --no-fetch --no-open --port 8480 master feature
# Screenshot with headless Chrome:
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --window-size=1320,850 --hide-scrollbars \
  --virtual-time-budget=3000 --screenshot=/tmp/shot.png \
  "http://127.0.0.1:8480/?file=0&theme=dark"
```

URL test params (web equivalent of the native app's hidden test flags):
`?file=N&change=N&expand-all&filter=q&wrap=0|1&theme=light|dark`

Requirements: Node ≥ 22.6 (type-stripping built in), no other global deps.

## Semantics to preserve

- Comparisons default to **merge-base (triple-dot)**: never show commits the
  base branch is ahead by. `--two-dot` / `a..b` is the explicit opt-out.
- Remote refs (`origin/...`) are **auto-fetched** before comparing (targeted,
  per-branch); deleted-on-remote branches warn and are marked in the title.
  The wizard fetches + prunes all remotes before listing. `--no-fetch` opts out.
- Plain `diffy` opens the branch wizard; `diffy HEAD` is worktree-vs-HEAD.
- `diffy <gitlab-mr-url>` opens the MR's exact diff (diff_refs) with review
  comments inline; reply + right-click-to-comment post via the GitLab API.
  Comments default to draft notes (review batching) published together via
  the Submit Review button; drafts are private, so create+delete is a safe
  E2E test. bulk_publish is the only untested-live call.
  @mentions: comment dialog autocompletes project members (/members/all);
  Token discovery: $DIFFY_GITLAB_TOKEN → ~/.config/diffy/gitlab-token →
  gitlab MCP entries in ~/.claude.json → $GITLAB_TOKEN (401s skip to next).
