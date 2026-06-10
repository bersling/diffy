import Foundation

enum TokenKind {
    case keyword
    case string
    case comment
    case number
    case typeName
    case attribute
}

typealias LineToken = (range: Range<Int>, kind: TokenKind)

// MARK: - Language specification

struct LangSpec {
    var keywords: Set<String> = []
    var caseInsensitiveKeywords = false
    var lineComments: [String] = []
    var blockComments: [(open: String, close: String)] = []
    var nestedBlockComments = false
    /// Ordered longest-first at use site. Multi-char entries like `"""` first.
    var stringDelimiters: [String] = ["\""]
    /// Delimiters whose strings may span lines (e.g. `"""`, `` ` ``, `'''`).
    var multilineStrings: Set<String> = []
    var attributePrefixes: Set<Character> = []
    var highlightCapitalizedAsType = true
    /// Crude tag-name highlighting for XML/HTML.
    var tagHighlighting = false
}

enum Syntax {

    static func spec(forPath path: String) -> LangSpec? {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name == "makefile" || name == "dockerfile" || name == "gemfile" || name == "rakefile" {
            return name == "dockerfile" ? dockerfile : hashConfig
        }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return swift
        case "kt", "kts": return kotlin
        case "java", "groovy", "gradle", "scala": return java
        case "js", "jsx", "ts", "tsx", "mjs", "cjs", "mts", "cts": return javascript
        case "py", "pyi": return python
        case "go": return go
        case "rs": return rust
        case "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "m", "mm", "proto": return cFamily
        case "cs": return csharp
        case "rb": return ruby
        case "php": return php
        case "sh", "bash", "zsh", "fish", "bats": return shell
        case "sql", "ddl", "dml": return sql
        case "yaml", "yml": return yaml
        case "json", "jsonc", "json5": return json
        case "css", "scss", "less", "sass": return css
        case "html", "htm", "xml", "svg", "vue", "plist", "xib", "storyboard", "xsl": return xml
        case "toml", "ini", "conf", "cfg", "properties", "env", "editorconfig": return iniConfig
        case "tf", "hcl", "tfvars": return hashConfig
        case "dockerfile": return dockerfile
        default: return nil
        }
    }

    // MARK: specs

    static let swift = LangSpec(
        keywords: ["func", "let", "var", "if", "else", "for", "while", "repeat", "return", "guard",
                   "switch", "case", "default", "break", "continue", "import", "class", "struct",
                   "enum", "protocol", "extension", "init", "deinit", "self", "Self", "super",
                   "nil", "true", "false", "throws", "throw", "try", "catch", "do", "defer", "in",
                   "where", "as", "is", "any", "some", "static", "final", "private", "public",
                   "internal", "fileprivate", "open", "override", "mutating", "lazy", "weak",
                   "unowned", "typealias", "associatedtype", "inout", "indirect", "convenience",
                   "required", "subscript", "get", "set", "willSet", "didSet", "async", "await",
                   "actor", "nonisolated", "operator", "precedencegroup", "fallthrough"],
        lineComments: ["//"],
        blockComments: [("/*", "*/")], nestedBlockComments: true,
        stringDelimiters: ["\"\"\"", "\""], multilineStrings: ["\"\"\""],
        attributePrefixes: ["@", "#"])

    static let kotlin = LangSpec(
        keywords: ["fun", "val", "var", "if", "else", "when", "for", "while", "do", "return",
                   "break", "continue", "import", "package", "class", "interface", "object",
                   "data", "sealed", "enum", "annotation", "companion", "init", "constructor",
                   "this", "super", "null", "true", "false", "throw", "try", "catch", "finally",
                   "in", "is", "as", "by", "out", "reified", "inline", "noinline", "crossinline",
                   "suspend", "override", "open", "final", "abstract", "private", "public",
                   "internal", "protected", "lateinit", "typealias", "where", "it", "vararg",
                   "tailrec", "operator", "infix", "external", "const", "expect", "actual"],
        lineComments: ["//"],
        blockComments: [("/*", "*/")], nestedBlockComments: true,
        stringDelimiters: ["\"\"\"", "\""], multilineStrings: ["\"\"\""],
        attributePrefixes: ["@"])

    static let java = LangSpec(
        keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
                   "class", "const", "continue", "default", "do", "double", "else", "enum",
                   "extends", "final", "finally", "float", "for", "goto", "if", "implements",
                   "import", "instanceof", "int", "interface", "long", "native", "new", "package",
                   "private", "protected", "public", "return", "short", "static", "strictfp",
                   "super", "switch", "synchronized", "this", "throw", "throws", "transient",
                   "try", "void", "volatile", "while", "var", "record", "sealed", "permits",
                   "true", "false", "null", "def", "trait", "in", "it"],
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["\"\"\"", "\"", "'"], multilineStrings: ["\"\"\""],
        attributePrefixes: ["@"])

    static let javascript = LangSpec(
        keywords: ["abstract", "any", "as", "async", "await", "boolean", "break", "case", "catch",
                   "class", "const", "continue", "debugger", "declare", "default", "delete", "do",
                   "else", "enum", "export", "extends", "false", "finally", "for", "from",
                   "function", "get", "if", "implements", "import", "in", "infer", "instanceof",
                   "interface", "is", "keyof", "let", "namespace", "never", "new", "null",
                   "number", "object", "of", "private", "protected", "public", "readonly",
                   "return", "satisfies", "set", "static", "string", "super", "switch", "symbol",
                   "this", "throw", "true", "try", "type", "typeof", "undefined", "unknown",
                   "var", "void", "while", "with", "yield"],
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["\"", "'", "`"], multilineStrings: ["`"],
        attributePrefixes: ["@"])

    static let python = LangSpec(
        keywords: ["False", "None", "True", "and", "as", "assert", "async", "await", "break",
                   "class", "continue", "def", "del", "elif", "else", "except", "finally", "for",
                   "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
                   "or", "pass", "raise", "return", "try", "while", "with", "yield", "match",
                   "case", "self", "cls"],
        lineComments: ["#"],
        stringDelimiters: ["\"\"\"", "'''", "\"", "'"], multilineStrings: ["\"\"\"", "'''"],
        attributePrefixes: ["@"])

    static let go = LangSpec(
        keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else",
                   "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
                   "map", "package", "range", "return", "select", "struct", "switch", "type",
                   "var", "nil", "true", "false", "iota", "make", "new", "len", "cap", "append",
                   "error", "string", "int", "int64", "int32", "uint", "byte", "rune", "bool",
                   "float64", "float32", "any"],
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["\"", "'", "`"], multilineStrings: ["`"])

    static let rust = LangSpec(
        keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
                   "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
                   "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self",
                   "static", "struct", "super", "trait", "true", "type", "unsafe", "use",
                   "where", "while", "union"],
        lineComments: ["//"],
        blockComments: [("/*", "*/")], nestedBlockComments: true,
        stringDelimiters: ["\""],
        attributePrefixes: ["#"])

    static let cFamily = LangSpec(
        keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do",
                   "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
                   "int", "long", "register", "return", "short", "signed", "sizeof", "static",
                   "struct", "switch", "typedef", "union", "unsigned", "void", "volatile",
                   "while", "class", "namespace", "template", "typename", "using", "virtual",
                   "override", "public", "private", "protected", "new", "delete", "this",
                   "nullptr", "true", "false", "bool", "constexpr", "noexcept", "try", "catch",
                   "throw", "friend", "operator", "explicit", "mutable", "id", "instancetype",
                   "self", "super", "nil", "YES", "NO", "strong", "nonatomic", "atomic", "copy",
                   "readonly", "readwrite", "weak", "assign", "message", "repeated", "optional",
                   "service", "rpc", "returns", "syntax"],
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["@", "#"])

    static let csharp = LangSpec(
        keywords: ["abstract", "as", "async", "await", "base", "bool", "break", "byte", "case",
                   "catch", "char", "checked", "class", "const", "continue", "decimal", "default",
                   "delegate", "do", "double", "else", "enum", "event", "explicit", "extern",
                   "false", "finally", "fixed", "float", "for", "foreach", "get", "goto", "if",
                   "implicit", "in", "int", "interface", "internal", "is", "lock", "long",
                   "namespace", "new", "null", "object", "operator", "out", "override", "params",
                   "private", "protected", "public", "readonly", "record", "ref", "return",
                   "sbyte", "sealed", "set", "short", "sizeof", "stackalloc", "static", "string",
                   "struct", "switch", "this", "throw", "true", "try", "typeof", "uint", "ulong",
                   "unchecked", "unsafe", "ushort", "using", "var", "virtual", "void", "volatile",
                   "when", "where", "while", "yield"],
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["#"])

    static let ruby = LangSpec(
        keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined?", "do",
                   "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module",
                   "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self",
                   "super", "then", "true", "undef", "unless", "until", "when", "while", "yield",
                   "require", "require_relative", "attr_accessor", "attr_reader", "attr_writer",
                   "lambda", "proc", "raise", "new", "puts"],
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["@", ":"])

    static let php = LangSpec(
        keywords: ["abstract", "and", "array", "as", "break", "callable", "case", "catch",
                   "class", "clone", "const", "continue", "declare", "default", "do", "echo",
                   "else", "elseif", "empty", "enum", "extends", "final", "finally", "fn", "for",
                   "foreach", "function", "global", "goto", "if", "implements", "include",
                   "instanceof", "insteadof", "interface", "isset", "list", "match", "namespace",
                   "new", "or", "print", "private", "protected", "public", "readonly", "require",
                   "require_once", "return", "static", "switch", "throw", "trait", "try", "unset",
                   "use", "var", "while", "xor", "yield", "true", "false", "null", "this"],
        caseInsensitiveKeywords: true,
        lineComments: ["//", "#"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["$", "#"])

    static let shell = LangSpec(
        keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
                   "case", "esac", "function", "in", "select", "time", "return", "exit", "break",
                   "continue", "local", "export", "readonly", "declare", "unset", "shift",
                   "eval", "exec", "set", "trap", "source", "alias", "echo", "printf", "read",
                   "cd", "test", "true", "false", "sudo"],
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["$"],
        highlightCapitalizedAsType: false)

    static let sql = LangSpec(
        keywords: ["select", "from", "where", "insert", "into", "values", "update", "delete",
                   "create", "table", "index", "view", "drop", "alter", "add", "column",
                   "primary", "key", "foreign", "references", "unique", "not", "null", "default",
                   "and", "or", "in", "is", "like", "between", "exists", "join", "inner", "left",
                   "right", "full", "outer", "on", "as", "order", "by", "group", "having",
                   "limit", "offset", "union", "all", "distinct", "count", "sum", "avg", "min",
                   "max", "case", "when", "then", "else", "end", "begin", "commit", "rollback",
                   "transaction", "grant", "revoke", "constraint", "cascade", "if", "returning",
                   "with", "varchar", "integer", "bigint", "boolean", "text", "timestamp",
                   "serial", "numeric"],
        caseInsensitiveKeywords: true,
        lineComments: ["--"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["'", "\""],
        highlightCapitalizedAsType: false)

    static let yaml = LangSpec(
        keywords: ["true", "false", "null", "yes", "no", "on", "off"],
        caseInsensitiveKeywords: true,
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["&", "*"],
        highlightCapitalizedAsType: false)

    static let json = LangSpec(
        keywords: ["true", "false", "null"],
        stringDelimiters: ["\""],
        highlightCapitalizedAsType: false)

    static let css = LangSpec(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["@", "$", "#"],
        highlightCapitalizedAsType: false)

    static let xml = LangSpec(
        blockComments: [("<!--", "-->")],
        stringDelimiters: ["\"", "'"],
        highlightCapitalizedAsType: false,
        tagHighlighting: true)

    static let iniConfig = LangSpec(
        keywords: ["true", "false"],
        caseInsensitiveKeywords: true,
        lineComments: ["#", ";"],
        stringDelimiters: ["\"", "'"],
        highlightCapitalizedAsType: false)

    static let hashConfig = LangSpec(
        keywords: ["true", "false", "null", "resource", "variable", "module", "provider",
                   "output", "data", "locals", "terraform", "end", "do", "source", "group"],
        lineComments: ["#"],
        blockComments: [("/*", "*/")],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["$"],
        highlightCapitalizedAsType: false)

    static let dockerfile = LangSpec(
        keywords: ["from", "run", "cmd", "copy", "add", "env", "arg", "workdir", "expose",
                   "entrypoint", "volume", "user", "label", "onbuild", "stopsignal",
                   "healthcheck", "shell", "as"],
        caseInsensitiveKeywords: true,
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["$"],
        highlightCapitalizedAsType: false)

    // MARK: - Entry point

    /// Tokenizes all lines of a file (display text, tabs already expanded).
    /// Returns nil when the language is unknown — caller renders plain text.
    static func highlight(lines: [String], path: String) -> [[LineToken]]? {
        guard let spec = spec(forPath: path) else { return nil }
        let tokenizer = Tokenizer(spec: spec)
        return lines.map { tokenizer.tokenizeLine($0) }
    }
}

// MARK: - Tokenizer

final class Tokenizer {
    private let spec: LangSpec
    private let stringDelims: [[Character]]   // longest first
    private let lineComments: [[Character]]
    private let blockOpens: [[Character]]
    private let blockCloses: [[Character]]

    private enum State {
        case code
        case blockComment(which: Int, depth: Int)
        case multiString(delim: [Character])
    }
    private var state: State = .code

    init(spec: LangSpec) {
        self.spec = spec
        self.stringDelims = spec.stringDelimiters
            .sorted { $0.count > $1.count }
            .map(Array.init)
        self.lineComments = spec.lineComments.map(Array.init)
        self.blockOpens = spec.blockComments.map { Array($0.open) }
        self.blockCloses = spec.blockComments.map { Array($0.close) }
    }

    func tokenizeLine(_ text: String) -> [LineToken] {
        let chars = Array(text)
        let n = chars.count
        if n == 0 || n > 2000 { return [] }
        var tokens: [LineToken] = []
        var i = 0

        func matches(_ pattern: [Character], at pos: Int) -> Bool {
            guard pos + pattern.count <= n else { return false }
            for (k, ch) in pattern.enumerated() where chars[pos + k] != ch { return false }
            return true
        }

        func isWordChar(_ c: Character) -> Bool {
            c.isLetter || c.isNumber || c == "_"
        }

        // Resume multi-line constructs.
        while i < n {
            switch state {
            case .blockComment(let which, var depth):
                let start = i
                let close = blockCloses[which]
                let open = blockOpens[which]
                var terminated = false
                while i < n {
                    if matches(close, at: i) {
                        depth -= 1
                        i += close.count
                        if depth == 0 { terminated = true; break }
                    } else if spec.nestedBlockComments && matches(open, at: i) {
                        depth += 1
                        i += open.count
                    } else {
                        i += 1
                    }
                }
                state = terminated ? .code : .blockComment(which: which, depth: depth)
                tokens.append((start..<i, .comment))

            case .multiString(let delim):
                let start = i
                var terminated = false
                while i < n {
                    if chars[i] == "\\" { i = min(i + 2, n); continue }
                    if matches(delim, at: i) { i += delim.count; terminated = true; break }
                    i += 1
                }
                if terminated { state = .code }
                tokens.append((start..<i, .string))

            case .code:
                let c = chars[i]
                if c == " " || c == "\t" {
                    i += 1
                    continue
                }

                // Line comment → rest of line
                if let _ = lineComments.first(where: { matches($0, at: i) }) {
                    tokens.append((i..<n, .comment))
                    i = n
                    continue
                }

                // Block comment
                if let which = blockOpens.indices.first(where: { matches(blockOpens[$0], at: i) }) {
                    let start = i
                    i += blockOpens[which].count
                    var depth = 1
                    var terminated = false
                    while i < n {
                        if matches(blockCloses[which], at: i) {
                            depth -= 1
                            i += blockCloses[which].count
                            if depth == 0 { terminated = true; break }
                        } else if spec.nestedBlockComments && matches(blockOpens[which], at: i) {
                            depth += 1
                            i += blockOpens[which].count
                        } else {
                            i += 1
                        }
                    }
                    if !terminated { state = .blockComment(which: which, depth: depth) }
                    tokens.append((start..<i, .comment))
                    continue
                }

                // String
                if let delim = stringDelims.first(where: { matches($0, at: i) }) {
                    let start = i
                    i += delim.count
                    var terminated = false
                    while i < n {
                        if chars[i] == "\\" { i = min(i + 2, n); continue }
                        if matches(delim, at: i) { i += delim.count; terminated = true; break }
                        i += 1
                    }
                    if !terminated && spec.multilineStrings.contains(String(delim)) {
                        state = .multiString(delim: delim)
                    }
                    tokens.append((start..<i, .string))
                    continue
                }

                // Attribute / decorator / variable prefix
                if spec.attributePrefixes.contains(c), i + 1 < n,
                   chars[i + 1].isLetter || chars[i + 1] == "_" || chars[i + 1] == "{" {
                    let start = i
                    i += 1
                    if i < n && chars[i] == "{" {  // ${var}
                        while i < n && chars[i] != "}" { i += 1 }
                        if i < n { i += 1 }
                    } else {
                        while i < n && isWordChar(chars[i]) { i += 1 }
                    }
                    tokens.append((start..<i, .attribute))
                    continue
                }

                // Number
                if c.isNumber || (c == "." && i + 1 < n && chars[i + 1].isNumber) {
                    let start = i
                    i += 1
                    while i < n {
                        let ch = chars[i]
                        if ch.isHexDigit || ch == "." || ch == "_" || ch == "x" || ch == "X"
                            || ch == "b" || ch == "o" || ch == "e" || ch == "E" {
                            i += 1
                        } else if (ch == "+" || ch == "-"),
                                  chars[i - 1] == "e" || chars[i - 1] == "E" {
                            i += 1
                        } else {
                            break
                        }
                    }
                    tokens.append((start..<i, .number))
                    continue
                }

                // Tag names: <name, </name
                if spec.tagHighlighting && c == "<" {
                    var j = i + 1
                    if j < n && chars[j] == "/" { j += 1 }
                    let nameStart = j
                    while j < n && (isWordChar(chars[j]) || chars[j] == "-" || chars[j] == ":" || chars[j] == "!") {
                        j += 1
                    }
                    if j > nameStart {
                        tokens.append((nameStart..<j, .keyword))
                        i = j
                        continue
                    }
                }

                // Identifier / keyword / type
                if c.isLetter || c == "_" {
                    let start = i
                    while i < n && isWordChar(chars[i]) { i += 1 }
                    var word = String(chars[start..<i])
                    if i < n && chars[i] == "?" && spec.keywords.contains(word + "?") {
                        i += 1
                        word += "?"  // ruby defined?
                    }
                    let key = spec.caseInsensitiveKeywords ? word.lowercased() : word
                    if spec.keywords.contains(key) {
                        tokens.append((start..<i, .keyword))
                    } else if spec.highlightCapitalizedAsType, let first = word.first,
                              first.isUppercase, word.count > 1,
                              word.contains(where: { $0.isLowercase }) {
                        tokens.append((start..<i, .typeName))
                    }
                    continue
                }

                i += 1
            }
        }
        return tokens
    }
}
