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
   - build artifacts stay out of git (`diffy` binary and `dist/` are
     gitignored — keep it that way)
3. **Clean up after yourself before committing & pushing.** Remove anything
   that was only needed to get the work done: debug prints/flags, scratch and
   temp files, stale staging directories (e.g. `dist/diffy/` keeps old files
   unless wiped — the dist target now does `rm -rf` first; keep it that way),
   leftover test output, dead code from abandoned approaches. After the
   security scan, also eyeball `git status` for files that shouldn't exist
   and the diff for changes that shouldn't be in it.

(The prompt-counter experiment was removed on request — don't reintroduce it.)

## Build & test

- Build: `make build` (or `make install` to refresh `~/.local/bin/diffy`)
- Ship artifacts: `make dist` (universal zip), `make pkg` (.pkg installer)
- Compile flag matters: `-swift-version 5` (Swift 6 mode breaks AppKit
  top-level code)
- Headless verification: `diffy --dump <ref> <ref>` prints the computed diff
  as text; `--screenshot <png>` renders the window to a PNG and exits.
  More hidden test flags: `--select <n>`, `--change <n>`, `--expand-all`,
  `--collapse-folders`, `--appearance light|dark`, `--auto-confirm`,
  `--two-dot`, `--no-fetch`.
- Test fixture: `/tmp/diffy-fixture` (master/develop, covers
  modify/add/delete/rename/binary/unicode/nested dirs, bare remote at
  /tmp/diffy-remote.git). Recreate if missing.

## Semantics to preserve

- Comparisons default to **merge-base (triple-dot)**: never show commits the
  base branch is ahead by. `--two-dot` / `a..b` is the explicit opt-out.
- Remote refs (`origin/...`) are **auto-fetched** before comparing (targeted,
  per-branch); deleted-on-remote branches warn and are marked in the title.
  The wizard fetches + prunes all remotes before listing. `--no-fetch` opts out.
- Plain `diffy` opens the branch wizard; `diffy HEAD` is worktree-vs-HEAD.
- `diffy <gitlab-mr-url>` opens the MR's exact diff (diff_refs) with review
  comments inline; reply + right-click-to-comment post via the GitLab API.
  Token discovery: $DIFFY_GITLAB_TOKEN → ~/.config/diffy/gitlab-token →
  gitlab MCP entries in ~/.claude.json → $GITLAB_TOKEN (401s skip to next).
