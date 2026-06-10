import Foundation

// MARK: - Models

struct MRRef {
    let host: String          // e.g. gitlab.example.com
    let projectPath: String   // e.g. group/project
    let iid: Int

    var encodedProject: String {
        projectPath.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? projectPath
    }

    /// Parses https://host/group/project/-/merge_requests/123[/diffs...]
    static func parse(_ urlString: String) -> MRRef? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        let path = url.path
        guard let range = path.range(of: "/-/merge_requests/") else { return nil }
        let project = String(path[path.index(after: path.startIndex)..<range.lowerBound])
        let rest = String(path[range.upperBound...])
        let iidString = rest.split(separator: "/").first.map(String.init) ?? rest
        guard let iid = Int(iidString), !project.isEmpty else { return nil }
        return MRRef(host: host, projectPath: project, iid: iid)
    }
}

struct GitLabMR {
    let iid: Int
    let title: String
    let state: String
    let sourceBranch: String
    let targetBranch: String
    let baseSha: String
    let startSha: String
    let headSha: String
    let webURL: String
}

struct MRPosition {
    let oldPath: String
    let newPath: String
    let oldLine: Int?
    let newLine: Int?
}

struct MRNote {
    let id: Int
    let author: String
    let body: String
    let createdAt: String
    let system: Bool
}

struct MRThread {
    let id: String
    let notes: [MRNote]
    let position: MRPosition?
    let resolved: Bool
}

struct GitLabError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// MARK: - Token discovery

enum GitLabToken {

    /// Collects candidate tokens without ever printing them: env vars,
    /// ~/.config/diffy/gitlab-token, and any gitlab MCP server configured in
    /// ~/.claude.json (so an existing Claude Code GitLab setup just works).
    /// MCP entries whose API URL matches `host` are preferred. The client
    /// tries candidates in order and skips ones the server rejects (stale
    /// tokens in the environment are common).
    static func candidates(host: String) -> [String] {
        var tokens: [String] = []
        func add(_ t: String?) {
            guard let t = t?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !t.isEmpty, !tokens.contains(t) else { return }
            tokens.append(t)
        }

        let env = ProcessInfo.processInfo.environment
        add(env["DIFFY_GITLAB_TOKEN"])

        let home = FileManager.default.homeDirectoryForCurrentUser
        add(try? String(contentsOf: home.appendingPathComponent(".config/diffy/gitlab-token"),
                        encoding: .utf8))

        // gitlab MCP servers from ~/.claude.json, host-matching entries first
        let claudeConfig = home.appendingPathComponent(".claude.json")
        if let data = try? Data(contentsOf: claudeConfig),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var serverDicts: [[String: Any]] = []
            if let servers = json["mcpServers"] as? [String: Any] {
                serverDicts.append(contentsOf: servers.values.compactMap { $0 as? [String: Any] })
            }
            if let projects = json["projects"] as? [String: Any] {
                for project in projects.values {
                    if let servers = (project as? [String: Any])?["mcpServers"] as? [String: Any] {
                        serverDicts.append(contentsOf: servers.values.compactMap { $0 as? [String: Any] })
                    }
                }
            }
            var matching: [String] = []
            var other: [String] = []
            for server in serverDicts {
                guard let env = server["env"] as? [String: String],
                      let t = env["GITLAB_PERSONAL_ACCESS_TOKEN"], !t.isEmpty else { continue }
                let url = env["GITLAB_API_URL"] ?? env["GITLAB_URL"] ?? ""
                if url.contains(host) { matching.append(t) } else { other.append(t) }
            }
            matching.forEach { add($0) }
            other.forEach { add($0) }
        }

        add(env["GITLAB_TOKEN"])
        add(env["GITLAB_PERSONAL_ACCESS_TOKEN"])
        return tokens
    }
}

// MARK: - API client

final class GitLabClient {
    let ref: MRRef
    private var tokens: [String]
    private var tokenIndex = 0

    init(ref: MRRef) throws {
        let tokens = GitLabToken.candidates(host: ref.host)
        guard !tokens.isEmpty else {
            throw GitLabError(message: """
                no GitLab token found. Provide one via the GITLAB_TOKEN environment \
                variable, ~/.config/diffy/gitlab-token, or a gitlab MCP server in ~/.claude.json
                """)
        }
        self.ref = ref
        self.tokens = tokens
    }

    private func request(method: String, path: String,
                         query: [String: String] = [:],
                         jsonBody: [String: Any]? = nil) throws -> Data {
        // Build the URL manually: URLComponents would re-encode the %2F in the
        // URL-encoded project id.
        guard let url = URL(string: "https://\(ref.host)/api/v4/projects/\(ref.encodedProject)\(path)"
            + (query.isEmpty ? "" : "?" + query.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))) else {
            throw GitLabError(message: "bad URL")
        }
        // Try token candidates in order; skip ones the server rejects.
        while true {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue(tokens[tokenIndex], forHTTPHeaderField: "PRIVATE-TOKEN")
            if let body = jsonBody {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
            }

            var result: Data?
            var error: Error?
            var status = 0
            let semaphore = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: req) { data, response, err in
                result = data
                error = err
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 30)

            if let error = error {
                throw GitLabError(message: "GitLab request failed: \(error.localizedDescription)")
            }
            guard let data = result else {
                throw GitLabError(message: "GitLab request timed out")
            }
            if status == 401, tokenIndex + 1 < tokens.count {
                tokenIndex += 1
                continue
            }
            guard (200..<300).contains(status) else {
                let snippet = String(decoding: data.prefix(300), as: UTF8.self)
                throw GitLabError(message: "GitLab API \(method) \(path) returned \(status): \(snippet)")
            }
            return data
        }
    }

    func fetchMR() throws -> GitLabMR {
        let data = try request(method: "GET", path: "/merge_requests/\(ref.iid)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String,
              let source = json["source_branch"] as? String,
              let target = json["target_branch"] as? String,
              let diffRefs = json["diff_refs"] as? [String: Any],
              let base = diffRefs["base_sha"] as? String,
              let start = diffRefs["start_sha"] as? String,
              let head = diffRefs["head_sha"] as? String else {
            throw GitLabError(message: "unexpected MR response from GitLab")
        }
        return GitLabMR(iid: ref.iid, title: title,
                        state: json["state"] as? String ?? "unknown",
                        sourceBranch: source, targetBranch: target,
                        baseSha: base, startSha: start, headSha: head,
                        webURL: json["web_url"] as? String ?? "")
    }

    func fetchDiscussions() throws -> [MRThread] {
        var threads: [MRThread] = []
        var page = 1
        while true {
            let data = try request(method: "GET",
                                   path: "/merge_requests/\(ref.iid)/discussions",
                                   query: ["per_page": "100", "page": "\(page)"])
            guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw GitLabError(message: "unexpected discussions response")
            }
            for item in items {
                guard let id = item["id"] as? String,
                      let noteDicts = item["notes"] as? [[String: Any]] else { continue }
                var notes: [MRNote] = []
                var position: MRPosition?
                var resolved = false
                for n in noteDicts {
                    let system = n["system"] as? Bool ?? false
                    guard let noteID = n["id"] as? Int,
                          let body = n["body"] as? String else { continue }
                    let author = (n["author"] as? [String: Any])?["name"] as? String ?? "?"
                    notes.append(MRNote(id: noteID, author: author, body: body,
                                        createdAt: n["created_at"] as? String ?? "",
                                        system: system))
                    if position == nil, let p = n["position"] as? [String: Any],
                       (p["position_type"] as? String ?? "text") == "text" {
                        position = MRPosition(oldPath: p["old_path"] as? String ?? "",
                                              newPath: p["new_path"] as? String ?? "",
                                              oldLine: p["old_line"] as? Int,
                                              newLine: p["new_line"] as? Int)
                    }
                    if n["resolvable"] as? Bool == true {
                        resolved = n["resolved"] as? Bool ?? false
                    }
                }
                let userNotes = notes.filter { !$0.system }
                if !userNotes.isEmpty {
                    threads.append(MRThread(id: id, notes: userNotes,
                                            position: position, resolved: resolved))
                }
            }
            if items.count < 100 { break }
            page += 1
        }
        return threads
    }

    func postReply(discussionID: String, body: String) throws {
        _ = try request(method: "POST",
                        path: "/merge_requests/\(ref.iid)/discussions/\(discussionID)/notes",
                        jsonBody: ["body": body])
    }

    func postThread(mr: GitLabMR, body: String, position: MRPosition) throws {
        var pos: [String: Any] = [
            "position_type": "text",
            "base_sha": mr.baseSha,
            "start_sha": mr.startSha,
            "head_sha": mr.headSha,
            "old_path": position.oldPath,
            "new_path": position.newPath,
        ]
        if let l = position.oldLine { pos["old_line"] = l }
        if let l = position.newLine { pos["new_line"] = l }
        _ = try request(method: "POST",
                        path: "/merge_requests/\(ref.iid)/discussions",
                        jsonBody: ["body": body, "position": pos])
    }
}

// MARK: - MR session context

final class MRContext {
    let client: GitLabClient
    let mr: GitLabMR
    var threads: [MRThread]

    init(client: GitLabClient, mr: GitLabMR, threads: [MRThread]) {
        self.client = client
        self.mr = mr
        self.threads = threads
    }

    func refresh() {
        if let fresh = try? client.fetchDiscussions() {
            threads = fresh
        }
    }

    /// Positioned, non-empty threads for one changed file.
    func threads(for file: ChangedFile) -> [MRThread] {
        threads.filter { thread in
            guard let pos = thread.position else { return false }
            return (!file.newPath.isEmpty && pos.newPath == file.newPath)
                || (!file.oldPath.isEmpty && pos.oldPath == file.oldPath)
        }
    }
}
