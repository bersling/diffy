// Port of Sources/Syntax.swift — keyword/comment/string tokenizer for diff
// lines. Character indices are code-point offsets (JS [...str]), which the
// frontend mirrors when slicing. Runs on the server (per-file highlight).
import type { LineTokenJSON } from "./model.ts";

interface LangSpec {
  keywords: Set<string>;
  caseInsensitiveKeywords: boolean;
  lineComments: string[];
  blockComments: [string, string][];
  nestedBlockComments: boolean;
  /** Ordered longest-first at use site. Multi-char entries like `"""` first. */
  stringDelimiters: string[];
  /** Delimiters whose strings may span lines (e.g. `"""`, `` ` ``, `'''`). */
  multilineStrings: Set<string>;
  attributePrefixes: Set<string>;
  highlightCapitalizedAsType: boolean;
  /** Crude tag-name highlighting for XML/HTML. */
  tagHighlighting: boolean;
}

type LangSpecInput = Omit<Partial<LangSpec>, "keywords"> & { keywords?: string[] };

function spec(partial: LangSpecInput): LangSpec {
  return {
    keywords: new Set(partial.keywords ?? []),
    caseInsensitiveKeywords: partial.caseInsensitiveKeywords ?? false,
    lineComments: partial.lineComments ?? [],
    blockComments: partial.blockComments ?? [],
    nestedBlockComments: partial.nestedBlockComments ?? false,
    stringDelimiters: partial.stringDelimiters ?? ['"'],
    multilineStrings: partial.multilineStrings ?? new Set(),
    attributePrefixes: partial.attributePrefixes ?? new Set(),
    highlightCapitalizedAsType: partial.highlightCapitalizedAsType ?? true,
    tagHighlighting: partial.tagHighlighting ?? false,
  };
}

const swift = spec({
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
  blockComments: [["/*", "*/"]], nestedBlockComments: true,
  stringDelimiters: ['"""', '"'], multilineStrings: new Set(['"""']),
  attributePrefixes: new Set(["@", "#"]),
});

const kotlin = spec({
  keywords: ["fun", "val", "var", "if", "else", "when", "for", "while", "do", "return",
    "break", "continue", "import", "package", "class", "interface", "object",
    "data", "sealed", "enum", "annotation", "companion", "init", "constructor",
    "this", "super", "null", "true", "false", "throw", "try", "catch", "finally",
    "in", "is", "as", "by", "out", "reified", "inline", "noinline", "crossinline",
    "suspend", "override", "open", "final", "abstract", "private", "public",
    "internal", "protected", "lateinit", "typealias", "where", "it", "vararg",
    "tailrec", "operator", "infix", "external", "const", "expect", "actual"],
  lineComments: ["//"],
  blockComments: [["/*", "*/"]], nestedBlockComments: true,
  stringDelimiters: ['"""', '"'], multilineStrings: new Set(['"""']),
  attributePrefixes: new Set(["@"]),
});

const java = spec({
  keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
    "class", "const", "continue", "default", "do", "double", "else", "enum",
    "extends", "final", "finally", "float", "for", "goto", "if", "implements",
    "import", "instanceof", "int", "interface", "long", "native", "new", "package",
    "private", "protected", "public", "return", "short", "static", "strictfp",
    "super", "switch", "synchronized", "this", "throw", "throws", "transient",
    "try", "void", "volatile", "while", "var", "record", "sealed", "permits",
    "true", "false", "null", "def", "trait", "in", "it"],
  lineComments: ["//"],
  blockComments: [["/*", "*/"]],
  stringDelimiters: ['"""', '"', "'"], multilineStrings: new Set(['"""']),
  attributePrefixes: new Set(["@"]),
});

const javascript = spec({
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
  blockComments: [["/*", "*/"]],
  stringDelimiters: ['"', "'", "`"], multilineStrings: new Set(["`"]),
  attributePrefixes: new Set(["@"]),
});

const python = spec({
  keywords: ["False", "None", "True", "and", "as", "assert", "async", "await", "break",
    "class", "continue", "def", "del", "elif", "else", "except", "finally", "for",
    "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
    "or", "pass", "raise", "return", "try", "while", "with", "yield", "match",
    "case", "self", "cls"],
  lineComments: ["#"],
  stringDelimiters: ['"""', "'''", '"', "'"], multilineStrings: new Set(['"""', "'''"]),
  attributePrefixes: new Set(["@"]),
});

const go = spec({
  keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else",
    "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
    "map", "package", "range", "return", "select", "struct", "switch", "type",
    "var", "nil", "true", "false", "iota", "make", "new", "len", "cap", "append",
    "error", "string", "int", "int64", "int32", "uint", "byte", "rune", "bool",
    "float64", "float32", "any"],
  lineComments: ["//"],
  blockComments: [["/*", "*/"]],
  stringDelimiters: ['"', "'", "`"], multilineStrings: new Set(["`"]),
});

const rust = spec({
  keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
    "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
    "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self",
    "static", "struct", "super", "trait", "true", "type", "unsafe", "use",
    "where", "while", "union"],
  lineComments: ["//"],
  blockComments: [["/*", "*/"]], nestedBlockComments: true,
  stringDelimiters: ['"'],
  attributePrefixes: new Set(["#"]),
});

const cFamily = spec({
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
  blockComments: [["/*", "*/"]],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["@", "#"]),
});

const csharp = spec({
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
  blockComments: [["/*", "*/"]],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["#"]),
});

const ruby = spec({
  keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined?", "do",
    "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module",
    "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self",
    "super", "then", "true", "undef", "unless", "until", "when", "while", "yield",
    "require", "require_relative", "attr_accessor", "attr_reader", "attr_writer",
    "lambda", "proc", "raise", "new", "puts"],
  lineComments: ["#"],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["@", ":"]),
});

const php = spec({
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
  blockComments: [["/*", "*/"]],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["$", "#"]),
});

const shell = spec({
  keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
    "case", "esac", "function", "in", "select", "time", "return", "exit", "break",
    "continue", "local", "export", "readonly", "declare", "unset", "shift",
    "eval", "exec", "set", "trap", "source", "alias", "echo", "printf", "read",
    "cd", "test", "true", "false", "sudo"],
  lineComments: ["#"],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["$"]),
  highlightCapitalizedAsType: false,
});

const sql = spec({
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
  blockComments: [["/*", "*/"]],
  stringDelimiters: ["'", '"'],
  highlightCapitalizedAsType: false,
});

const yaml = spec({
  keywords: ["true", "false", "null", "yes", "no", "on", "off"],
  caseInsensitiveKeywords: true,
  lineComments: ["#"],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["&", "*"]),
  highlightCapitalizedAsType: false,
});

const json = spec({
  keywords: ["true", "false", "null"],
  stringDelimiters: ['"'],
  highlightCapitalizedAsType: false,
});

const css = spec({
  lineComments: ["//"],
  blockComments: [["/*", "*/"]],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["@", "$", "#"]),
  highlightCapitalizedAsType: false,
});

const xml = spec({
  blockComments: [["<!--", "-->"]],
  stringDelimiters: ['"', "'"],
  highlightCapitalizedAsType: false,
  tagHighlighting: true,
});

const iniConfig = spec({
  keywords: ["true", "false"],
  caseInsensitiveKeywords: true,
  lineComments: ["#", ";"],
  stringDelimiters: ['"', "'"],
  highlightCapitalizedAsType: false,
});

const hashConfig = spec({
  keywords: ["true", "false", "null", "resource", "variable", "module", "provider",
    "output", "data", "locals", "terraform", "end", "do", "source", "group"],
  lineComments: ["#"],
  blockComments: [["/*", "*/"]],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["$"]),
  highlightCapitalizedAsType: false,
});

const dockerfile = spec({
  keywords: ["from", "run", "cmd", "copy", "add", "env", "arg", "workdir", "expose",
    "entrypoint", "volume", "user", "label", "onbuild", "stopsignal",
    "healthcheck", "shell", "as"],
  caseInsensitiveKeywords: true,
  lineComments: ["#"],
  stringDelimiters: ['"', "'"],
  attributePrefixes: new Set(["$"]),
  highlightCapitalizedAsType: false,
});

function specForPath(path: string): LangSpec | null {
  const name = path.split("/").pop()!.toLowerCase();
  if (name === "makefile" || name === "dockerfile" || name === "gemfile" || name === "rakefile") {
    return name === "dockerfile" ? dockerfile : hashConfig;
  }
  const dot = name.lastIndexOf(".");
  const ext = dot >= 0 ? name.slice(dot + 1) : "";
  switch (ext) {
    case "swift": return swift;
    case "kt": case "kts": return kotlin;
    case "java": case "groovy": case "gradle": case "scala": return java;
    case "js": case "jsx": case "ts": case "tsx": case "mjs": case "cjs": case "mts": case "cts":
      return javascript;
    case "py": case "pyi": return python;
    case "go": return go;
    case "rs": return rust;
    case "c": case "h": case "cpp": case "cc": case "cxx": case "hpp": case "hh":
    case "m": case "mm": case "proto": return cFamily;
    case "cs": return csharp;
    case "rb": return ruby;
    case "php": return php;
    case "sh": case "bash": case "zsh": case "fish": case "bats": return shell;
    case "sql": case "ddl": case "dml": return sql;
    case "yaml": case "yml": return yaml;
    case "json": case "jsonc": case "json5": return json;
    case "css": case "scss": case "less": case "sass": return css;
    case "html": case "htm": case "xml": case "svg": case "vue": case "plist":
    case "xib": case "storyboard": case "xsl": return xml;
    case "toml": case "ini": case "conf": case "cfg": case "properties": case "env":
    case "editorconfig": return iniConfig;
    case "tf": case "hcl": case "tfvars": return hashConfig;
    case "dockerfile": return dockerfile;
    default: return null;
  }
}

const RE_LETTER = /\p{L}/u;
const RE_NUMBER = /\p{N}/u;
const RE_HEX = /[0-9a-fA-F]/;
const RE_UPPER = /\p{Lu}/u;
const RE_LOWER = /\p{Ll}/u;

type State =
  | { kind: "code" }
  | { kind: "blockComment"; which: number; depth: number }
  | { kind: "multiString"; delim: string[] };

class Tokenizer {
  private lang: LangSpec;
  private stringDelims: string[][]; // longest first
  private lineComments: string[][];
  private blockOpens: string[][];
  private blockCloses: string[][];
  private state: State = { kind: "code" };

  constructor(lang: LangSpec) {
    this.lang = lang;
    this.stringDelims = [...lang.stringDelimiters]
      .sort((a, b) => b.length - a.length)
      .map((s) => [...s]);
    this.lineComments = lang.lineComments.map((s) => [...s]);
    this.blockOpens = lang.blockComments.map(([o]) => [...o]);
    this.blockCloses = lang.blockComments.map(([, c]) => [...c]);
  }

  tokenizeLine(text: string): LineTokenJSON[] {
    const chars = [...text];
    const n = chars.length;
    if (n === 0 || n > 2000) return [];
    const tokens: LineTokenJSON[] = [];
    let i = 0;
    const lang = this.lang;

    const matches = (pattern: string[], pos: number): boolean => {
      if (pos + pattern.length > n) return false;
      for (let k = 0; k < pattern.length; k++) {
        if (chars[pos + k] !== pattern[k]) return false;
      }
      return true;
    };
    const isWordChar = (c: string): boolean =>
      RE_LETTER.test(c) || RE_NUMBER.test(c) || c === "_";

    while (i < n) {
      const st = this.state;
      if (st.kind === "blockComment") {
        const start = i;
        const close = this.blockCloses[st.which]!;
        const open = this.blockOpens[st.which]!;
        let depth = st.depth;
        let terminated = false;
        while (i < n) {
          if (matches(close, i)) {
            depth -= 1;
            i += close.length;
            if (depth === 0) { terminated = true; break; }
          } else if (lang.nestedBlockComments && matches(open, i)) {
            depth += 1;
            i += open.length;
          } else {
            i += 1;
          }
        }
        this.state = terminated
          ? { kind: "code" }
          : { kind: "blockComment", which: st.which, depth };
        tokens.push({ s: start, e: i, k: "comment" });
        continue;
      }
      if (st.kind === "multiString") {
        const start = i;
        const delim = st.delim;
        let terminated = false;
        while (i < n) {
          if (chars[i] === "\\") { i = Math.min(i + 2, n); continue; }
          if (matches(delim, i)) { i += delim.length; terminated = true; break; }
          i += 1;
        }
        if (terminated) this.state = { kind: "code" };
        tokens.push({ s: start, e: i, k: "string" });
        continue;
      }

      // code state
      const c = chars[i]!;
      if (c === " " || c === "\t") { i += 1; continue; }

      // Line comment → rest of line
      let handled = false;
      for (const lc of this.lineComments) {
        if (matches(lc, i)) {
          tokens.push({ s: i, e: n, k: "comment" });
          i = n;
          handled = true;
          break;
        }
      }
      if (handled) continue;
      if (i >= n) break;

      // Block comment
      for (let w = 0; w < this.blockOpens.length; w++) {
        if (!matches(this.blockOpens[w]!, i)) continue;
        const start = i;
        i += this.blockOpens[w]!.length;
        let depth = 1;
        let terminated = false;
        while (i < n) {
          if (matches(this.blockCloses[w]!, i)) {
            depth -= 1;
            i += this.blockCloses[w]!.length;
            if (depth === 0) { terminated = true; break; }
          } else if (lang.nestedBlockComments && matches(this.blockOpens[w]!, i)) {
            depth += 1;
            i += this.blockOpens[w]!.length;
          } else {
            i += 1;
          }
        }
        if (!terminated) this.state = { kind: "blockComment", which: w, depth };
        tokens.push({ s: start, e: i, k: "comment" });
        handled = true;
        break;
      }
      if (handled) continue;

      // String
      for (const delim of this.stringDelims) {
        if (!matches(delim, i)) continue;
        const start = i;
        i += delim.length;
        let terminated = false;
        while (i < n) {
          if (chars[i] === "\\") { i = Math.min(i + 2, n); continue; }
          if (matches(delim, i)) { i += delim.length; terminated = true; break; }
          i += 1;
        }
        if (!terminated && lang.multilineStrings.has(delim.join(""))) {
          this.state = { kind: "multiString", delim };
        }
        tokens.push({ s: start, e: i, k: "string" });
        handled = true;
        break;
      }
      if (handled) continue;

      // Attribute / decorator / variable prefix
      if (lang.attributePrefixes.has(c) && i + 1 < n &&
          (RE_LETTER.test(chars[i + 1]!) || chars[i + 1] === "_" || chars[i + 1] === "{")) {
        const start = i;
        i += 1;
        if (i < n && chars[i] === "{") { // ${var}
          while (i < n && chars[i] !== "}") i += 1;
          if (i < n) i += 1;
        } else {
          while (i < n && isWordChar(chars[i]!)) i += 1;
        }
        tokens.push({ s: start, e: i, k: "attribute" });
        continue;
      }

      // Number
      if (RE_NUMBER.test(c) || (c === "." && i + 1 < n && RE_NUMBER.test(chars[i + 1]!))) {
        const start = i;
        i += 1;
        while (i < n) {
          const ch = chars[i]!;
          if (RE_HEX.test(ch) || ch === "." || ch === "_" || ch === "x" || ch === "X" ||
              ch === "b" || ch === "o" || ch === "e" || ch === "E") {
            i += 1;
          } else if ((ch === "+" || ch === "-") &&
                     (chars[i - 1] === "e" || chars[i - 1] === "E")) {
            i += 1;
          } else {
            break;
          }
        }
        tokens.push({ s: start, e: i, k: "number" });
        continue;
      }

      // Tag names: <name, </name
      if (lang.tagHighlighting && c === "<") {
        let j = i + 1;
        if (j < n && chars[j] === "/") j += 1;
        const nameStart = j;
        while (j < n && (isWordChar(chars[j]!) || chars[j] === "-" || chars[j] === ":" || chars[j] === "!")) {
          j += 1;
        }
        if (j > nameStart) {
          tokens.push({ s: nameStart, e: j, k: "keyword" });
          i = j;
          continue;
        }
      }

      // Identifier / keyword / type
      if (RE_LETTER.test(c) || c === "_") {
        const start = i;
        while (i < n && isWordChar(chars[i]!)) i += 1;
        let word = chars.slice(start, i).join("");
        if (i < n && chars[i] === "?" && lang.keywords.has(word + "?")) {
          i += 1;
          word += "?"; // ruby defined?
        }
        const key = lang.caseInsensitiveKeywords ? word.toLowerCase() : word;
        if (lang.keywords.has(key)) {
          tokens.push({ s: start, e: i, k: "keyword" });
        } else if (lang.highlightCapitalizedAsType && word.length > 1 &&
                   RE_UPPER.test(word[0]!) && RE_LOWER.test(word)) {
          tokens.push({ s: start, e: i, k: "typeName" });
        }
        continue;
      }

      i += 1;
    }
    return tokens;
  }
}

/** Tokenizes all lines of a file (display text, tabs already expanded).
 *  Returns null when the language is unknown — caller renders plain text. */
export function highlightLines(lines: string[], path: string): LineTokenJSON[][] | null {
  const lang = specForPath(path);
  if (!lang) return null;
  const tokenizer = new Tokenizer(lang);
  return lines.map((line) => tokenizer.tokenizeLine(line));
}
