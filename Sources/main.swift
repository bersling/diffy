import AppKit
import Foundation

let usage = """
diffy — native macOS side-by-side diff viewer for git

USAGE:
  diffy [options] [<ref> [<ref>]] [-- <path>...]

EXAMPLES:
  diffy                          open the branch-selection wizard
  diffy <gitlab-mr-url>          open a GitLab MR with inline review comments
  diffy HEAD                     HEAD vs working tree
  diffy master                   your work vs master (since you diverged from it)
  diffy master develop           changes in develop since it diverged from master
  diffy origin/master origin/develop
  diffy master develop -- src/   limit to paths

  Comparisons use the merge base by default (GitLab-MR semantics): commits
  the base branch is ahead by are NOT shown. To compare branch tips exactly:
  diffy --two-dot master develop (or: diffy master..develop)

  Remote refs (origin/...) are fetched automatically before comparing, so the
  diff reflects the actual state on the remote. Skip with --no-fetch.

  GitLab: run inside the repo checkout with the MR URL to see the MR's exact
  diff plus its review comments inline; right-click a line to add a comment.
  The token is read from $GITLAB_TOKEN, ~/.config/diffy/gitlab-token, or an
  existing gitlab MCP server entry in ~/.claude.json. under src/

KEYS:
  n / p (or ⌘J / ⌘K)             next / previous change
  ] / [ (or ⌘↓ / ⌘↑)             next / previous file

OPTIONS:
  --two-dot            compare tips exactly instead of using the merge base
  --no-fetch           skip fetching; compare local snapshots of remote refs
  --dump               print the computed diff as text and exit (no GUI)
  --screenshot <path>  render the window to a PNG and exit
  -h, --help           show this help
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("diffy: \(message)\n".utf8))
    exit(1)
}

// MARK: - Parse arguments

var refs: [String] = []
var paths: [String] = []
var dumpMode = false
var screenshotPath: String? = nil
var initialFileIndex = 0
var initialChangeJumps = 0
var forcedAppearance: String? = nil
var autoConfirm = false
var expandAllOnLaunch = false
var collapseFoldersOnLaunch = false
var twoDot = false
var noFetch = false
var copyLinesRange: ClosedRange<Int>? = nil
var mentionUITestPath: String? = nil
var fileFilterQuery: String? = nil
var showCommentsOnLaunch = false

var args = Array(CommandLine.arguments.dropFirst())
var afterDoubleDash = false
var i = 0
while i < args.count {
    let arg = args[i]
    if afterDoubleDash {
        paths.append(arg)
    } else if arg == "--" {
        afterDoubleDash = true
    } else if arg == "-h" || arg == "--help" {
        print(usage)
        exit(0)
    } else if arg == "--dump" {
        dumpMode = true
    } else if arg == "--screenshot" {
        i += 1
        guard i < args.count else { fail("--screenshot requires a path") }
        screenshotPath = args[i]
    } else if arg == "--select" {
        i += 1
        guard i < args.count, let n = Int(args[i]) else { fail("--select requires a number") }
        initialFileIndex = n
    } else if arg == "--change" {
        i += 1
        guard i < args.count, let n = Int(args[i]) else { fail("--change requires a number") }
        initialChangeJumps = n
    } else if arg == "--appearance" {
        i += 1
        guard i < args.count else { fail("--appearance requires light or dark") }
        forcedAppearance = args[i]
    } else if arg == "--auto-confirm" {
        autoConfirm = true
    } else if arg == "--expand-all" {
        expandAllOnLaunch = true
    } else if arg == "--two-dot" {
        twoDot = true
    } else if arg == "--no-fetch" {
        noFetch = true
    } else if arg == "--test-mention" {
        // Headless self-test of @mention prefix matching.
        i += 1
        guard i < args.count else { fail("--test-mention requires a query") }
        let sample = [
            GitLabUser(username: "jost", name: "Jost Joller"),
            GitLabUser(username: "portmann", name: "Samuel Portmann"),
            GitLabUser(username: "jo", name: "Jo Helmuth"),
            GitLabUser(username: "zeljko", name: "Zeljko Antic"),
            GitLabUser(username: "sniederhauser", name: "Stefan Niederhauser"),
        ]
        for u in MentionTextView.match(sample, prefix: args[i]) {
            print("@\(u.username)  \(u.name)")
        }
        exit(0)
    } else if arg == "--test-mention-ui" {
        i += 1
        guard i < args.count else { fail("--test-mention-ui requires a PNG path") }
        mentionUITestPath = args[i]
    } else if arg == "--filter-files" {
        i += 1
        guard i < args.count else { fail("--filter-files requires a query") }
        fileFilterQuery = args[i]
    } else if arg == "--show-comments" {
        showCommentsOnLaunch = true
    } else if arg == "--collapse-folders" {
        collapseFoldersOnLaunch = true
    } else if arg == "--copy-lines" {
        i += 1
        guard i < args.count else { fail("--copy-lines requires a row range like 5-8") }
        let parts = args[i].split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[0] <= parts[1] else { fail("--copy-lines requires a row range like 5-8") }
        copyLinesRange = parts[0]...parts[1]
    } else if arg.hasPrefix("-") {
        fail("unknown option: \(arg)\n\n\(usage)")
    } else {
        refs.append(arg)
    }
    i += 1
}

// MARK: - @mention popup UI test (headless screenshot)

if let path = mentionUITestPath {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    if let forced = forcedAppearance {
        app.appearance = NSAppearance(named: forced == "light" ? .aqua : .darkAqua)
    }
    let delegate = MentionUITestDelegate(screenshotPath: path)
    app.delegate = delegate
    app.run()
    exit(0)
}

// MARK: - Build session (or defer to the branch wizard)

// Plain `diffy` opens the branch-selection wizard; `diffy HEAD` etc. go
// straight to the viewer. Dump mode keeps HEAD-vs-worktree for scripting.
// A GitLab MR URL opens that MR's diff with review comments.
let mrRef = refs.lazy.compactMap(MRRef.parse).first
let wizardMode = refs.isEmpty && !dumpMode

var session: DiffSession? = nil
var wizardGit: Git? = nil
do {
    if let mrRef = mrRef {
        let client = try GitLabClient(ref: mrRef)
        FileHandle.standardError.write(Data("diffy: loading MR !\(mrRef.iid) from \(mrRef.host)…\n".utf8))
        let mr = try client.fetchMR()
        let git = try Git(cwd: FileManager.default.currentDirectoryPath)
        if !noFetch {
            for branch in [mr.targetBranch, mr.sourceBranch] {
                FileHandle.standardError.write(Data("diffy: fetching origin/\(branch)…\n".utf8))
                _ = git.fetch(remote: "origin", branch: branch)
            }
            // GitLab keeps every MR's head reachable via a special ref even
            // after squash-merges or source-branch deletion.
            _ = git.fetch(remote: "origin", branch: "refs/merge-requests/\(mrRef.iid)/head")
        }
        for sha in [mr.baseSha, mr.headSha] where git.resolve(sha) == nil {
            throw GitError(message: """
                commit \(sha) from the MR is not present locally — \
                is this the right repository checkout for \(mrRef.projectPath)?
                """)
        }
        let s = try DiffSession(cwd: git.repoRoot,
                                refs: [mr.baseSha, mr.headSha], paths: paths,
                                twoDot: true, noFetch: true,
                                labels: ("\(mr.targetBranch) (MR base)", mr.sourceBranch))
        let threads = try client.fetchDiscussions()
        let drafts = (try? client.fetchDraftNotes()) ?? []
        let context = MRContext(client: client, mr: mr, threads: threads, drafts: drafts)
        context.loadMembersAsync()
        s.mr = context
        session = s
    } else if wizardMode {
        wizardGit = try Git(cwd: FileManager.default.currentDirectoryPath)
    } else {
        session = try DiffSession(cwd: FileManager.default.currentDirectoryPath,
                                  refs: refs, paths: paths, twoDot: twoDot, noFetch: noFetch)
    }
} catch {
    fail("\(error)")
}

if let session = session, session.files.isEmpty {
    print("diffy: no differences between \(session.leftLabel) and \(session.rightLabel)")
    exit(0)
}

// MARK: - Dump mode (headless, for testing/scripting)

if dumpMode, let session = session {
    print("== \(session.title) — \(session.files.count) changed file(s) ==")
    for (idx, file) in session.files.enumerated() {
        let diff = session.fileDiff(at: idx)
        let pathDesc = file.status == .renamed || file.status == .copied
            ? "\(file.oldPath) -> \(file.newPath)"
            : file.displayPath
        print("\n[\(file.status.letter)] \(pathDesc)  (+\(diff.additions) -\(diff.deletions))\(diff.isBinary ? " [binary]" : "")")
        for row in diff.rows {
            let kindChar: String
            switch row.kind {
            case .context: kindChar = " "
            case .addition: kindChar = "+"
            case .deletion: kindChar = "-"
            case .modification: kindChar = "~"
            case .message: kindChar = "!"
            }
            let ln = row.left.map { String(format: "%4d", $0.number) } ?? "    "
            let rn = row.right.map { String(format: "%4d", $0.number) } ?? "    "
            let lt = row.left?.text ?? ""
            let rt = row.right?.text ?? ""
            print("\(kindChar) \(ln) | \(lt.padding(toLength: min(max(lt.count, 38), 38), withPad: " ", startingAt: 0)) || \(rn) | \(rt)")
        }
    }
    exit(0)
}

// MARK: - Launch GUI

let app = NSApplication.shared
app.setActivationPolicy(.regular)
if let forced = forcedAppearance {
    app.appearance = NSAppearance(named: forced == "light" ? .aqua : .darkAqua)
}
let delegate = AppDelegate(session: session, wizardGit: wizardGit, paths: paths,
                           noFetch: noFetch,
                           screenshotPath: screenshotPath,
                           initialFileIndex: initialFileIndex,
                           initialChangeJumps: initialChangeJumps,
                           autoConfirm: autoConfirm,
                           expandAllOnLaunch: expandAllOnLaunch,
                           collapseFoldersOnLaunch: collapseFoldersOnLaunch,
                           copyLinesRange: copyLinesRange,
                           fileFilterQuery: fileFilterQuery,
                           showCommentsOnLaunch: showCommentsOnLaunch)
app.delegate = delegate
app.run()
