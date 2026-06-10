import Foundation

struct GitError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class Git {
    let repoRoot: String

    init(cwd: String) throws {
        let result = Git.run(["rev-parse", "--show-toplevel"], in: cwd)
        guard result.status == 0, let root = String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty else {
            throw GitError(message: "not a git repository (or any of the parent directories): \(cwd)")
        }
        self.repoRoot = root
    }

    @discardableResult
    static func run(_ args: [String], in dir: String) -> (status: Int32, stdout: Data, stderr: Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return (127, Data(), Data(error.localizedDescription.utf8))
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, stdout, stderr)
    }

    func run(_ args: [String]) -> (status: Int32, stdout: Data, stderr: Data) {
        Git.run(args, in: repoRoot)
    }

    func verifyRef(_ ref: String) throws {
        let r = run(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"])
        if r.status != 0 {
            throw GitError(message: "unknown revision: \(ref)")
        }
    }

    func mergeBase(_ a: String, _ b: String) throws -> String {
        let r = run(["merge-base", a, b])
        guard r.status == 0, let sha = String(data: r.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !sha.isEmpty else {
            throw GitError(message: "no merge base between \(a) and \(b)")
        }
        return sha
    }

    /// Changed files between two refs (or vs the working tree when rightRef is nil).
    func changedFiles(leftRef: String, rightRef: String?, paths: [String]) throws -> [ChangedFile] {
        var args = ["diff", "--name-status", "-M", "-z", leftRef]
        if let right = rightRef { args.append(right) }
        if !paths.isEmpty { args.append(contentsOf: ["--"] + paths) }
        let r = run(args)
        if r.status != 0 {
            let msg = String(data: r.stderr, encoding: .utf8) ?? "git diff failed"
            throw GitError(message: msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Git.parseNameStatus(r.stdout)
    }

    static func parseNameStatus(_ data: Data) -> [ChangedFile] {
        let parts = data.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        var files: [ChangedFile] = []
        var i = 0
        while i < parts.count {
            let code = parts[i]
            if code.isEmpty { i += 1; continue }
            let status = FileStatus(code: code)
            if status == .renamed || status == .copied {
                guard i + 2 < parts.count else { break }
                files.append(ChangedFile(status: status, oldPath: parts[i + 1], newPath: parts[i + 2]))
                i += 3
            } else {
                guard i + 1 < parts.count else { break }
                let path = parts[i + 1]
                files.append(ChangedFile(status: status, oldPath: path, newPath: path))
                i += 2
            }
        }
        return files
    }

    /// Local branch names, most recently committed first.
    func localBranches() -> [String] {
        let r = run(["for-each-ref", "--sort=-committerdate", "refs/heads",
                     "--format=%(refname:short)"])
        guard r.status == 0 else { return [] }
        return String(decoding: r.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }

    func remotes() -> [String] {
        let r = run(["remote"])
        guard r.status == 0 else { return [] }
        return String(decoding: r.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }

    /// Branches of a remote as refs like "origin/master", most recent first.
    func remoteBranches(_ remote: String) -> [String] {
        let r = run(["for-each-ref", "--sort=-committerdate", "refs/remotes/\(remote)",
                     "--format=%(refname:short)"])
        guard r.status == 0 else { return [] }
        return String(decoding: r.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init)
            .filter { $0 != "\(remote)/HEAD" }
    }

    enum FetchResult {
        case ok
        case deletedOnRemote
        case failed(String)
    }

    /// Fetch a single branch (or everything) from a remote.
    func fetch(remote: String, branch: String?, prune: Bool = false) -> FetchResult {
        var args = ["fetch", "--quiet"]
        if prune { args.append("--prune") }
        args.append(remote)
        if let branch = branch { args.append(branch) }
        let r = run(args)
        if r.status == 0 { return .ok }
        let err = String(decoding: r.stderr, as: UTF8.self)
        if err.contains("couldn't find remote ref") || err.contains("Couldn't find remote ref") {
            return .deletedOnRemote
        }
        return .failed(err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func resolve(_ ref: String) -> String? {
        let r = run(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"])
        guard r.status == 0 else { return nil }
        let sha = String(decoding: r.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    func currentBranch() -> String? {
        let r = run(["symbolic-ref", "--short", "-q", "HEAD"])
        guard r.status == 0 else { return nil }
        let name = String(decoding: r.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Content of a file at a ref, or from the working tree when ref is nil.
    func content(ref: String?, path: String) -> Data {
        if path.isEmpty { return Data() }
        if let ref = ref {
            let r = run(["show", "\(ref):\(path)"])
            return r.status == 0 ? r.stdout : Data()
        } else {
            let url = URL(fileURLWithPath: repoRoot).appendingPathComponent(path)
            return (try? Data(contentsOf: url)) ?? Data()
        }
    }
}

// MARK: - Session: ties together the comparison the user asked for

final class DiffSession {
    let git: Git
    let leftRef: String        // resolved left ref (e.g. merge-base sha for "a...b")
    let rightRef: String?      // nil = working tree
    private(set) var leftLabel: String
    private(set) var rightLabel: String
    let files: [ChangedFile]
    private var cache: [Int: FileDiff] = [:]

    /// Fetches every `<remote>/<branch>` mentioned in the refs so the diff
    /// reflects the actual state on the remote, not a stale local snapshot.
    /// Returns refs whose branch no longer exists on the remote.
    private static func fetchRemoteRefs(git: Git, refs: [String]) -> Set<String> {
        var parts: [String] = []
        for ref in refs {
            if let r = ref.range(of: "...") {
                parts.append(String(ref[..<r.lowerBound]))
                parts.append(String(ref[r.upperBound...]))
            } else if let r = ref.range(of: "..") {
                parts.append(String(ref[..<r.lowerBound]))
                parts.append(String(ref[r.upperBound...]))
            } else {
                parts.append(ref)
            }
        }
        let remotes = Set(git.remotes())
        var deleted: Set<String> = []
        var seen: Set<String> = []
        for part in parts {
            guard let slash = part.firstIndex(of: "/") else { continue }
            let remote = String(part[..<slash])
            let branch = String(part[part.index(after: slash)...])
            guard remotes.contains(remote), !branch.isEmpty, seen.insert(part).inserted else { continue }
            FileHandle.standardError.write(Data("diffy: fetching \(part)…\n".utf8))
            switch git.fetch(remote: remote, branch: branch) {
            case .ok:
                break
            case .deletedOnRemote:
                deleted.insert(part)
                FileHandle.standardError.write(Data(
                    "diffy: warning: '\(branch)' no longer exists on \(remote) — showing the last locally known state\n".utf8))
            case .failed(let err):
                FileHandle.standardError.write(Data(
                    "diffy: warning: fetch of \(part) failed (offline?) — using local refs\n  \(err)\n".utf8))
            }
        }
        return deleted
    }

    /// Resolves the left side of a comparison. By default (`twoDot == false`)
    /// the left side is the merge base of base and target — GitLab-MR
    /// semantics: only changes made on the target side are shown, never
    /// commits the base branch is ahead by. `--two-dot` compares tips exactly.
    private static func leftSide(git: Git, base: String, target: String,
                                 twoDot: Bool) -> (ref: String, label: String) {
        guard !twoDot,
              let mergeBase = try? git.mergeBase(base, target),
              let baseSha = git.resolve(base) else {
            return (base, base)
        }
        if mergeBase == baseSha {
            return (base, base)  // base is an ancestor of target; identical result
        }
        return (mergeBase, "\(base) (merge base)")
    }

    init(cwd: String, refs: [String], paths: [String], twoDot: Bool = false,
         noFetch: Bool = false) throws {
        self.git = try Git(cwd: cwd)

        let deletedOnRemote = noFetch ? [] : DiffSession.fetchRemoteRefs(git: git, refs: refs)

        switch refs.count {
        case 0:
            leftRef = "HEAD"
            rightRef = nil
            leftLabel = "HEAD"
            rightLabel = "Working tree"
            try git.verifyRef("HEAD")
        case 1:
            let ref = refs[0]
            if let r = ref.range(of: "...") {
                let a = String(ref[..<r.lowerBound])
                let b = String(ref[r.upperBound...])
                guard !a.isEmpty, !b.isEmpty else { throw GitError(message: "invalid range: \(ref)") }
                try git.verifyRef(a)
                try git.verifyRef(b)
                leftRef = try git.mergeBase(a, b)
                rightRef = b
                leftLabel = "\(a) (merge base)"
                rightLabel = b
            } else if let r = ref.range(of: "..") {
                let a = String(ref[..<r.lowerBound])
                let b = String(ref[r.upperBound...])
                guard !a.isEmpty, !b.isEmpty else { throw GitError(message: "invalid range: \(ref)") }
                try git.verifyRef(a)
                try git.verifyRef(b)
                leftRef = a
                rightRef = b
                leftLabel = a
                rightLabel = b
            } else {
                try git.verifyRef(ref)
                let left = DiffSession.leftSide(git: git, base: ref, target: "HEAD", twoDot: twoDot)
                leftRef = left.ref
                leftLabel = left.label
                rightRef = nil
                rightLabel = "Working tree"
            }
        case 2:
            try git.verifyRef(refs[0])
            try git.verifyRef(refs[1])
            let left = DiffSession.leftSide(git: git, base: refs[0], target: refs[1], twoDot: twoDot)
            leftRef = left.ref
            leftLabel = left.label
            rightRef = refs[1]
            rightLabel = refs[1]
        default:
            throw GitError(message: "too many refs (expected at most 2)")
        }

        for ref in deletedOnRemote {
            leftLabel = leftLabel.replacingOccurrences(of: ref, with: "\(ref) ⚠︎ deleted on remote")
            rightLabel = rightLabel.replacingOccurrences(of: ref, with: "\(ref) ⚠︎ deleted on remote")
        }

        self.files = try git.changedFiles(leftRef: leftRef, rightRef: rightRef, paths: paths)
    }

    var title: String { "\(leftLabel) → \(rightLabel)" }

    func fileDiff(at index: Int) -> FileDiff {
        if let cached = cache[index] { return cached }
        let file = files[index]
        let oldData = file.status == .added
            ? Data()
            : git.content(ref: leftRef, path: file.oldPath)
        let newData = file.status == .deleted
            ? Data()
            : git.content(ref: rightRef, path: file.newPath)
        let diff = DiffEngine.makeFileDiff(file: file, oldContent: oldData, newContent: newData)
        cache[index] = diff
        return diff
    }
}
