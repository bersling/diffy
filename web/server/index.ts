// diffy-web — local server + browser UI. Port of Sources/main.swift: same CLI
// semantics (merge-base default, --two-dot, --no-fetch, --dump, MR URLs,
// branch wizard), but the "window" is a browser tab served over localhost.
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { execFile } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type {
  CommentLocationJSON,
  FileResponseJSON,
  MRMutationJSON,
  MRPosition,
  WizardJSON,
} from "../shared/model.ts";
import { Git } from "./git.ts";
import { DiffSession, MRContext } from "./session.ts";
import { GitLabClient, parseMRRef } from "./gitlab.ts";
import { FakeMRClient } from "./fake-mr.ts";

const usage = `diffy — fast side-by-side diff viewer for git (web edition)

USAGE:
  diffy-web [options] [<ref> [<ref>]] [-- <path>...]

EXAMPLES:
  diffy-web                        open the branch-selection wizard
  diffy-web <gitlab-mr-url>        open a GitLab MR with inline review comments
  diffy-web HEAD                   HEAD vs working tree
  diffy-web master                 your work vs master (since you diverged from it)
  diffy-web master develop         changes in develop since it diverged from master
  diffy-web origin/master origin/develop
  diffy-web master develop -- src/ limit to paths

  Comparisons use the merge base by default (GitLab-MR semantics): commits
  the base branch is ahead by are NOT shown. To compare branch tips exactly:
  diffy-web --two-dot master develop (or: diffy-web master..develop)

  Remote refs (origin/...) are fetched automatically before comparing, so the
  diff reflects the actual state on the remote. Skip with --no-fetch.

  GitLab: run inside the repo checkout with the MR URL to see the MR's exact
  diff plus its review comments inline; right-click a line to add a comment.
  The token is read from $GITLAB_TOKEN, ~/.config/diffy/gitlab-token, or an
  existing gitlab MCP server entry in ~/.claude.json.

KEYS:
  n / p (or ⇧N)                  next / previous change
  ] / [                          next / previous file
  w                              toggle soft-wrapping of long lines

OPTIONS:
  --two-dot            compare tips exactly instead of using the merge base
  --no-fetch           skip fetching; compare local snapshots of remote refs
  --wrap               start with soft-wrap enabled (one-off; doesn't persist)
  --dump               print the computed diff as text and exit (no server)
  --port <n>           listen on a specific port (default: random free port)
  --no-open            don't open the browser automatically
  -h, --help           show this help
`;

function fail(message: string): never {
  process.stderr.write(`diffy: ${message}\n`);
  process.exit(1);
}

// MARK: - Parse arguments

const refs: string[] = [];
const paths: string[] = [];
let dumpMode = false;
let twoDot = false;
let noFetch = false;
let wrapOnLaunch = false;
let requestedPort: number | null = null;
let autoOpen = true;

{
  const args = process.argv.slice(2);
  let afterDoubleDash = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    if (afterDoubleDash) {
      paths.push(arg);
    } else if (arg === "--") {
      afterDoubleDash = true;
    } else if (arg === "-h" || arg === "--help") {
      console.log(usage);
      process.exit(0);
    } else if (arg === "--dump") {
      dumpMode = true;
    } else if (arg === "--two-dot") {
      twoDot = true;
    } else if (arg === "--no-fetch") {
      noFetch = true;
    } else if (arg === "--wrap") {
      wrapOnLaunch = true;
    } else if (arg === "--no-open") {
      autoOpen = false;
    } else if (arg === "--port") {
      i += 1;
      const n = Number.parseInt(args[i] ?? "", 10);
      if (!Number.isFinite(n) || n <= 0 || n > 65535) fail("--port requires a valid port number");
      requestedPort = n;
    } else if (arg.startsWith("-")) {
      fail(`unknown option: ${arg}\n\n${usage}`);
    } else {
      refs.push(arg);
    }
  }
}

// MARK: - Build session (or defer to the branch wizard)

interface WizardState {
  git: Git;
}

let session: DiffSession | null = null;
let wizard: WizardState | null = null;

async function buildInitialState(): Promise<void> {
  const mrRef = refs.map(parseMRRef).find((r) => r !== null) ?? null;
  const wizardMode = refs.length === 0 && !dumpMode;
  const cwd = process.cwd();

  if (mrRef) {
    const client = await GitLabClient.create(mrRef);
    process.stderr.write(`diffy: loading MR !${mrRef.iid} from ${mrRef.host}…\n`);
    const mr = await client.fetchMR();
    const git = await Git.open(cwd);
    if (!noFetch) {
      for (const branch of [mr.targetBranch, mr.sourceBranch]) {
        process.stderr.write(`diffy: fetching origin/${branch}…\n`);
        await git.fetch("origin", branch);
      }
      // GitLab keeps every MR's head reachable via a special ref even
      // after squash-merges or source-branch deletion.
      await git.fetch("origin", `refs/merge-requests/${mrRef.iid}/head`);
    }
    for (const sha of [mr.baseSha, mr.headSha]) {
      if ((await git.resolve(sha)) === null) {
        fail(`commit ${sha} from the MR is not present locally — is this the right repository checkout for ${mrRef.projectPath}?`);
      }
    }
    const s = await DiffSession.create({
      cwd: git.repoRoot,
      refs: [mr.baseSha, mr.headSha],
      paths,
      twoDot: true,
      noFetch: true,
      labels: { left: `${mr.targetBranch} (MR base)`, right: mr.sourceBranch },
    });
    const threads = await client.fetchDiscussions();
    const drafts = await client.fetchDraftNotes().catch(() => []);
    const context = new MRContext(client, mr, threads, drafts);
    context.loadMembersAsync();
    s.mr = context;
    session = s;
  } else if (wizardMode) {
    const git = await Git.open(cwd);
    // Refresh remotes (with prune) so the branch lists reflect the actual
    // remote state, not a stale local snapshot.
    if (!noFetch) {
      for (const remote of await git.remotes()) {
        process.stderr.write(`diffy: fetching ${remote}…\n`);
        await git.fetch(remote, null, true);
      }
    }
    wizard = { git };
  } else {
    session = await DiffSession.create({ cwd, refs, paths, twoDot, noFetch });
  }

  // Dev/test hook: attach an in-memory fake MR so the review UI can be
  // exercised without a GitLab server (see server/fake-mr.ts).
  if (process.env.DIFFY_FAKE_MR && session && session.files.length > 0) {
    const firstPath = session.files[0]!.newPath || session.files[0]!.oldPath;
    const fake = new FakeMRClient(firstPath, 2, 3);
    const threads = await fake.fetchDiscussions();
    const context = new MRContext(fake, fake.mr, threads, []);
    context.loadMembersAsync();
    session.mr = context;
  }

  if (session && session.files.length === 0) {
    console.log(`diffy: no differences between ${session.leftLabel} and ${session.rightLabel}`);
    process.exit(0);
  }
}

// MARK: - Dump mode (headless, for testing/scripting)

async function dump(s: DiffSession): Promise<void> {
  const cp = (str: string) => [...str];
  const pad38 = (str: string) => {
    const chars = cp(str);
    if (chars.length > 38) return chars.slice(0, 38).join("");
    return str + " ".repeat(38 - chars.length);
  };
  console.log(`== ${s.title} — ${s.files.length} changed file(s) ==`);
  for (let idx = 0; idx < s.files.length; idx++) {
    const file = s.files[idx]!;
    const diff = await s.fileDiffAt(idx);
    const pathDesc = file.status === "renamed" || file.status === "copied"
      ? `${file.oldPath} -> ${file.newPath}`
      : file.newPath.length > 0 ? file.newPath : file.oldPath;
    const letter = { added: "A", deleted: "D", modified: "M", renamed: "R", copied: "C", typeChanged: "T" }[file.status];
    console.log(`\n[${letter}] ${pathDesc}  (+${diff.additions} -${diff.deletions})${diff.isBinary ? " [binary]" : ""}`);
    for (const row of diff.rows) {
      const kindChar = { context: " ", addition: "+", deletion: "-", modification: "~", message: "!" }[row.kind];
      const ln = row.left ? String(row.left.n).padStart(4) : "    ";
      const rn = row.right ? String(row.right.n).padStart(4) : "    ";
      const lt = row.left?.t ?? "";
      const rt = row.right?.t ?? "";
      console.log(`${kindChar} ${ln} | ${pad38(lt)} || ${rn} | ${rt}`);
    }
  }
}

// MARK: - HTTP server

const distDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../dist");

const contentTypes: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".json": "application/json",
  ".map": "application/json",
  ".woff2": "font/woff2",
};

function sendJSON(res: ServerResponse, status: number, body: unknown): void {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end(data);
}

function sendError(res: ServerResponse, err: unknown): void {
  sendJSON(res, 400, { error: err instanceof Error ? err.message : String(err) });
}

async function readBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > 16 * 1024 * 1024) throw new Error("request too large");
    chunks.push(chunk as Buffer);
  }
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

async function serveStatic(res: ServerResponse, urlPath: string): Promise<boolean> {
  let filePath = urlPath === "/" ? "/index.html" : urlPath;
  // Prevent path traversal.
  const resolved = path.normalize(path.join(distDir, filePath));
  if (!resolved.startsWith(distDir)) return false;
  try {
    const data = await fs.readFile(resolved);
    const ext = path.extname(resolved);
    res.writeHead(200, {
      "Content-Type": contentTypes[ext] ?? "application/octet-stream",
      "Cache-Control": "no-store",
    });
    res.end(data);
    return true;
  } catch {
    return false;
  }
}

/** Refreshed review state after an MR mutation. */
async function mutationResult(fileIndex: number | null): Promise<MRMutationJSON> {
  const mr = session?.mr;
  if (!session || !mr) throw new Error("not an MR session");
  await mr.refresh();
  const threads = fileIndex !== null && session.files[fileIndex]
    ? mr.displayThreads(session.files[fileIndex]!)
    : null;
  return {
    draftCount: mr.draftCount,
    commentCount: mr.allThreadLocations(session.files).length,
    threads,
  };
}

async function handleAPI(
  req: IncomingMessage,
  res: ServerResponse,
  urlPath: string,
): Promise<void> {
  // State / session
  if (req.method === "GET" && urlPath === "/api/state") {
    if (wizard) {
      sendJSON(res, 200, { mode: "wizard" });
    } else if (session) {
      sendJSON(res, 200, { mode: "session", session: session.toJSON(wrapOnLaunch ? true : null) });
    } else {
      sendError(res, new Error("no session"));
    }
    return;
  }

  if (req.method === "GET" && urlPath === "/api/wizard") {
    if (!wizard) return sendError(res, new Error("not in wizard mode"));
    const git = wizard.git;
    const remotes: { name: string; branches: string[] }[] = [];
    for (const remote of await git.remotes()) {
      remotes.push({ name: remote, branches: await git.remoteBranches(remote) });
    }
    const body: WizardJSON = {
      locals: await git.localBranches(),
      current: await git.currentBranch(),
      remotes,
    };
    sendJSON(res, 200, body);
    return;
  }

  if (req.method === "POST" && urlPath === "/api/compare") {
    if (!wizard) return sendError(res, new Error("not in wizard mode"));
    const body = (await readBody(req)) as { source?: string; target?: string };
    if (!body.source || !body.target) return sendError(res, new Error("source and target are required"));
    const refs = body.source === "« Working Tree »" ? [body.target] : [body.target, body.source];
    // The wizard already fetched all remotes at startup.
    const s = await DiffSession.create({
      cwd: wizard.git.repoRoot,
      refs,
      paths,
      noFetch: true,
    });
    if (s.files.length === 0) {
      sendJSON(res, 200, {
        ok: false,
        message: `No differences: ${s.leftLabel} and ${s.rightLabel} are identical.`,
      });
      return;
    }
    session = s;
    wizard = null;
    sendJSON(res, 200, { ok: true, session: s.toJSON(wrapOnLaunch ? true : null) });
    return;
  }

  const fileMatch = urlPath.match(/^\/api\/file\/(\d+)$/);
  if (req.method === "GET" && fileMatch) {
    if (!session) return sendError(res, new Error("no session"));
    const index = Number.parseInt(fileMatch[1]!, 10);
    if (index < 0 || index >= session.files.length) return sendError(res, new Error("file index out of range"));
    const diff = await session.fileDiffAt(index);
    const body: FileResponseJSON = {
      diff,
      threads: session.mr ? session.mr.displayThreads(session.files[index]!) : null,
    };
    sendJSON(res, 200, body);
    return;
  }

  if (req.method === "GET" && urlPath === "/api/comments") {
    if (!session?.mr) return sendError(res, new Error("not an MR session"));
    const locations: CommentLocationJSON[] = session.mr
      .allThreadLocations(session.files)
      .map((l) => ({
        fileIndex: l.fileIndex,
        line: l.line,
        path: session!.files[l.fileIndex]!.newPath || session!.files[l.fileIndex]!.oldPath,
        thread: l.thread,
      }));
    sendJSON(res, 200, { comments: locations, draftCount: session.mr.draftCount });
    return;
  }

  if (req.method === "GET" && urlPath === "/api/mr/members") {
    if (!session?.mr) return sendError(res, new Error("not an MR session"));
    sendJSON(res, 200, { members: session.mr.members });
    return;
  }

  // MARK: MR mutations

  if (req.method === "POST" && urlPath === "/api/mr/reply") {
    if (!session?.mr) return sendError(res, new Error("not an MR session"));
    const body = (await readBody(req)) as {
      discussionID?: string; body?: string; sendNow?: boolean; fileIndex?: number;
    };
    if (!body.discussionID || !body.body?.trim()) return sendError(res, new Error("discussionID and body are required"));
    if (body.sendNow) {
      await session.mr.client.postReply(body.discussionID, body.body.trim());
    } else {
      await session.mr.client.createDraft(session.mr.mr, body.body.trim(), null, body.discussionID);
    }
    sendJSON(res, 200, await mutationResult(body.fileIndex ?? null));
    return;
  }

  if (req.method === "POST" && urlPath === "/api/mr/comment") {
    if (!session?.mr) return sendError(res, new Error("not an MR session"));
    const body = (await readBody(req)) as {
      position?: MRPosition; body?: string; sendNow?: boolean; fileIndex?: number;
    };
    if (!body.position || !body.body?.trim()) return sendError(res, new Error("position and body are required"));
    if (body.sendNow) {
      await session.mr.client.postThread(session.mr.mr, body.body.trim(), body.position);
    } else {
      await session.mr.client.createDraft(session.mr.mr, body.body.trim(), body.position, null);
    }
    sendJSON(res, 200, await mutationResult(body.fileIndex ?? null));
    return;
  }

  if (req.method === "POST" && urlPath === "/api/mr/discard") {
    if (!session?.mr) return sendError(res, new Error("not an MR session"));
    const body = (await readBody(req)) as { draftIDs?: number[]; fileIndex?: number };
    if (!Array.isArray(body.draftIDs) || body.draftIDs.length === 0) {
      return sendError(res, new Error("draftIDs required"));
    }
    for (const id of body.draftIDs) {
      await session.mr.client.deleteDraft(id);
    }
    sendJSON(res, 200, await mutationResult(body.fileIndex ?? null));
    return;
  }

  if (req.method === "POST" && urlPath === "/api/mr/publish") {
    if (!session?.mr) return sendError(res, new Error("not an MR session"));
    const body = (await readBody(req)) as { fileIndex?: number };
    await session.mr.client.publishDrafts();
    sendJSON(res, 200, await mutationResult(body.fileIndex ?? null));
    return;
  }

  sendJSON(res, 404, { error: `unknown endpoint: ${req.method} ${urlPath}` });
}

async function main(): Promise<void> {
  try {
    await buildInitialState();
  } catch (err) {
    fail(err instanceof Error ? err.message : String(err));
  }

  if (dumpMode) {
    await dump(session!);
    return;
  }

  const server = createServer((req, res) => {
    void (async () => {
      const url = new URL(req.url ?? "/", "http://localhost");
      const urlPath = decodeURIComponent(url.pathname);
      try {
        if (urlPath.startsWith("/api/")) {
          await handleAPI(req, res, urlPath);
          return;
        }
        if (req.method === "GET" && (await serveStatic(res, urlPath))) return;
        // SPA fallback: unknown non-API GET paths serve the app shell.
        if (req.method === "GET" && (await serveStatic(res, "/"))) return;
        sendJSON(res, 404, { error: "not found" });
      } catch (err) {
        if (!res.headersSent) sendError(res, err);
        else res.end();
      }
    })();
  });

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(requestedPort ?? 0, "127.0.0.1", () => resolve());
  });
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  const url = `http://127.0.0.1:${port}/`;
  process.stderr.write(`diffy: ${session ? session.title : "branch wizard"} — ${url}\n`);

  if (autoOpen) {
    const opener = process.platform === "darwin" ? "open" : process.platform === "win32" ? "cmd" : "xdg-open";
    const openerArgs = process.platform === "win32" ? ["/c", "start", "", url] : [url];
    execFile(opener, openerArgs, () => { /* best effort */ });
  }
}

await main();
