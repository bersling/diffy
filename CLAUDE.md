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
3. **Bump PROMPT_COUNTER.md** on every user prompt. A UserPromptSubmit hook in
   `.claude/settings.json` should do this automatically; if it didn't fire
   (check the count vs. the actual prompt number), bump it manually so the
   count stays honest, and include it in the next commit.

## Build & test

- Build: `make build` (or `make install` to refresh `~/.local/bin/diffy`)
- Ship artifacts: `make dist` (universal zip), `make pkg` (.pkg installer)
- Compile flag matters: `-swift-version 5` (Swift 6 mode breaks AppKit
  top-level code)
- Headless verification: `diffy --dump <ref> <ref>` prints the computed diff
  as text; `--screenshot <png>` renders the window to a PNG and exits.
  More hidden test flags: `--select <n>`, `--change <n>`, `--expand-all`,
  `--collapse-folders`, `--appearance light|dark`, `--auto-confirm`,
  `--two-dot`.
- Test fixture: `/tmp/diffy-fixture` (master/develop, covers
  modify/add/delete/rename/binary/unicode/nested dirs, bare remote at
  /tmp/diffy-remote.git). Recreate if missing.

## Semantics to preserve

- Comparisons default to **merge-base (triple-dot)**: never show commits the
  base branch is ahead by. `--two-dot` / `a..b` is the explicit opt-out.
- Plain `diffy` opens the branch wizard; `diffy HEAD` is worktree-vs-HEAD.
