// Port of Sources/Git.swift — thin async wrapper around the git CLI.
import { execFile } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import type { ChangedFile } from "./diff-engine.ts";
import { statusFromCode } from "./diff-engine.ts";

export class GitError extends Error {}

const MAX_BUFFER = 512 * 1024 * 1024;

export interface RunResult {
  status: number;
  stdout: Buffer;
  stderr: Buffer;
}

export class Git {
  readonly repoRoot: string;

  private constructor(repoRoot: string) {
    this.repoRoot = repoRoot;
  }

  static async open(cwd: string): Promise<Git> {
    const result = await Git.run(["rev-parse", "--show-toplevel"], cwd);
    const root = result.stdout.toString("utf8").trim();
    if (result.status !== 0 || !root) {
      throw new GitError(`not a git repository (or any of the parent directories): ${cwd}`);
    }
    return new Git(root);
  }

  static run(args: string[], dir: string): Promise<RunResult> {
    return new Promise((resolve) => {
      execFile(
        "git",
        args,
        { cwd: dir, maxBuffer: MAX_BUFFER, encoding: "buffer" },
        (error, stdout, stderr) => {
          if (error && (error as NodeJS.ErrnoException).code === "ENOENT") {
            resolve({ status: 127, stdout: Buffer.alloc(0), stderr: Buffer.from("git not found") });
            return;
          }
          // execFile reports non-zero exit as an error carrying code/stdout/stderr.
          const status = !error
            ? 0
            : typeof (error as { code?: unknown }).code === "number"
              ? (error as { code: number }).code
              : 1; // e.g. killed by a signal
          resolve({
            status,
            stdout: Buffer.isBuffer(stdout) ? stdout : Buffer.from(stdout ?? ""),
            stderr: Buffer.isBuffer(stderr) ? stderr : Buffer.from(stderr ?? ""),
          });
        },
      );
    });
  }

  run(args: string[]): Promise<RunResult> {
    return Git.run(args, this.repoRoot);
  }

  async verifyRef(ref: string): Promise<void> {
    const r = await this.run(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]);
    if (r.status !== 0) throw new GitError(`unknown revision: ${ref}`);
  }

  async mergeBase(a: string, b: string): Promise<string> {
    const r = await this.run(["merge-base", a, b]);
    const sha = r.stdout.toString("utf8").trim();
    if (r.status !== 0 || !sha) {
      throw new GitError(`no merge base between ${a} and ${b}`);
    }
    return sha;
  }

  /** Changed files between two refs (or vs the working tree when rightRef is null). */
  async changedFiles(leftRef: string, rightRef: string | null, paths: string[]): Promise<ChangedFile[]> {
    const args = ["diff", "--name-status", "-M", "-z", leftRef];
    if (rightRef !== null) args.push(rightRef);
    if (paths.length > 0) args.push("--", ...paths);
    const r = await this.run(args);
    if (r.status !== 0) {
      throw new GitError(r.stderr.toString("utf8").trim() || "git diff failed");
    }
    return Git.parseNameStatus(r.stdout);
  }

  static parseNameStatus(data: Buffer): ChangedFile[] {
    const parts = data.toString("utf8").split("\0");
    const files: ChangedFile[] = [];
    let i = 0;
    while (i < parts.length) {
      const code = parts[i]!;
      if (code.length === 0) { i += 1; continue; }
      const status = statusFromCode(code);
      if (status === "renamed" || status === "copied") {
        if (i + 2 >= parts.length) break;
        files.push({ status, oldPath: parts[i + 1]!, newPath: parts[i + 2]! });
        i += 3;
      } else {
        if (i + 1 >= parts.length) break;
        const p = parts[i + 1]!;
        files.push({ status, oldPath: p, newPath: p });
        i += 2;
      }
    }
    return files;
  }

  /** Local branch names, most recently committed first. */
  async localBranches(): Promise<string[]> {
    const r = await this.run(["for-each-ref", "--sort=-committerdate", "refs/heads", "--format=%(refname:short)"]);
    if (r.status !== 0) return [];
    return r.stdout.toString("utf8").split("\n").filter((s) => s.length > 0);
  }

  async remotes(): Promise<string[]> {
    const r = await this.run(["remote"]);
    if (r.status !== 0) return [];
    return r.stdout.toString("utf8").split("\n").filter((s) => s.length > 0);
  }

  /** Branches of a remote as refs like "origin/master", most recent first. */
  async remoteBranches(remote: string): Promise<string[]> {
    const r = await this.run(["for-each-ref", "--sort=-committerdate", `refs/remotes/${remote}`, "--format=%(refname:short)"]);
    if (r.status !== 0) return [];
    return r.stdout
      .toString("utf8")
      .split("\n")
      .filter((s) => s.length > 0 && s !== `${remote}/HEAD`);
  }

  /** Fetch a single branch (or everything) from a remote. */
  async fetch(
    remote: string,
    branch: string | null,
    prune = false,
  ): Promise<{ kind: "ok" } | { kind: "deletedOnRemote" } | { kind: "failed"; error: string }> {
    const args = ["fetch", "--quiet"];
    if (prune) args.push("--prune");
    args.push(remote);
    if (branch !== null) args.push(branch);
    const r = await this.run(args);
    if (r.status === 0) return { kind: "ok" };
    const err = r.stderr.toString("utf8");
    if (err.includes("couldn't find remote ref") || err.includes("Couldn't find remote ref")) {
      return { kind: "deletedOnRemote" };
    }
    return { kind: "failed", error: err.trim() };
  }

  async resolve(ref: string): Promise<string | null> {
    const r = await this.run(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]);
    if (r.status !== 0) return null;
    const sha = r.stdout.toString("utf8").trim();
    return sha.length > 0 ? sha : null;
  }

  async currentBranch(): Promise<string | null> {
    const r = await this.run(["symbolic-ref", "--short", "-q", "HEAD"]);
    if (r.status !== 0) return null;
    const name = r.stdout.toString("utf8").trim();
    return name.length > 0 ? name : null;
  }

  /** Content of a file at a ref, or from the working tree when ref is null. */
  async content(ref: string | null, filePath: string): Promise<Buffer> {
    if (filePath.length === 0) return Buffer.alloc(0);
    if (ref !== null) {
      const r = await this.run(["show", `${ref}:${filePath}`]);
      return r.status === 0 ? r.stdout : Buffer.alloc(0);
    }
    try {
      return await fs.readFile(path.join(this.repoRoot, filePath));
    } catch {
      return Buffer.alloc(0);
    }
  }
}
