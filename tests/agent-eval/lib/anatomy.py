"""(0.17) A run's anatomy, from its transcript and logs: what the agent
spent its calls on, which errors it met, how it recovered.

`for_run(rdir, res, starter, final)` returns result.json's `anatomy`:

- `tokens`: turns, output, fresh / cache-write / cache-read input, cost,
  the first turn's prompt and the median prompt per turn (fresh + cache
  write + cache read of one model call);
- `roles`: calls by role (`lookup`: guide, query, explain, Read/Grep/Glob,
  shell reads; `edit`: Write/Edit, tachyonc edit/refactor/fix/rewrite/undo,
  sed -i, perl -pi, a heredoc into a source file; `verify`: check, build,
  run, test, suite, cmp/diff, sh SCRIPT; `other`), one role per call (edit
  over verify over lookup); `segment_roles` counts every command of a
  call (they add up to tool_calls_by_kind's total); `first_edit_call`;
- `errors`: the compile errors the agent saw (in tool results and, through
  lib/hook-tee.py, in the hooks' output), each `{class, code, msg, habit,
  call}`, distinct per run (same class and message with names and numbers
  masked); `classes` and `habits` count them;
- `repair`: episodes from a call that showed errors to the next clean
  build, check or checked edit: their calls, and calls per distinct error;
- `edit_recovery`: failed edits (patch.no-match, edit.breaks, an Edit tool
  miss, ...) and whether the next edit succeeded;
- `denials`: each denied call's primary cause (`file-outside`, `heredoc`,
  `subst`, `var`, `loop`, `cd`, `unlisted`, `chain`, `pipe`, `redirect`,
  `other`) and all the forms it has;
- `ngrams`: the run's call sequence as tokens (`Write`, `build`, `run`,
  `query:show`, `edit:patch`, ...), its top bigrams and trigrams;
- `guide_topics`: `tachyonc guide` topics and `--find` words fetched;
- `erosion` (intent erosion): items, test files and assert-like lines of
  the starter that are gone at the end (programs: starter against the
  final workspace; compiler tasks: changes.patch);
- `query_hook`: blocked commands and whether the next call ran the
  suggested query (from hook-output.jsonl).

Nothing here changes a run's grading; errors in the analysis are kept as
`anatomy.error`."""

import json
import os
import re
import statistics
from collections import Counter

from lib.toolkinds import _words, classify_call, split_commands

ROLE_ORDER = ("edit", "verify", "lookup", "other")

# ---------------------------------------------------------------- transcript


def _text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(c.get("text", "") if isinstance(c, dict) else str(c) for c in content)
    return str(content or "")


DENIED_RE = re.compile(r"^Permission for this tool use was denied|requires approval|"
                       r"haven't granted it yet|permission to use .* was denied", re.I)


def load(rdir):
    """(calls, msgs, results) of transcript.jsonl: calls in order, each
    {id, tool, input, text, is_error, denied, ts}; msgs: the usage of each
    model call (by message id, in order); results: the result events."""
    calls, by_id, msgs, results = [], {}, [], []
    seen = {}
    path = os.path.join(rdir, "transcript.jsonl")
    if not os.path.exists(path):
        return calls, msgs, results
    with open(path, "rb") as fh:
        for raw in fh:
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            t = d.get("type")
            if t == "assistant" and d.get("parent_tool_use_id") is None:
                m = d.get("message") or {}
                mid = m.get("id")
                if mid and m.get("usage"):
                    if mid not in seen:
                        seen[mid] = len(msgs)
                        msgs.append(m["usage"])
                    else:
                        msgs[seen[mid]] = m["usage"]
                for c in m.get("content") or []:
                    if c.get("type") == "tool_use":
                        call = {"id": c.get("id"), "tool": c.get("name"),
                                "input": c.get("input") or {}, "text": "", "is_error": False,
                                "denied": False, "ts": None}
                        calls.append(call)
                        by_id[call["id"]] = call
            elif t == "user":
                m = d.get("message") or {}
                for c in m.get("content") or [] if isinstance(m.get("content"), list) else []:
                    if isinstance(c, dict) and c.get("type") == "tool_result":
                        call = by_id.get(c.get("tool_use_id"))
                        if call is None:
                            continue
                        call["text"] = _text(c.get("content"))
                        call["is_error"] = bool(c.get("is_error"))
                        call["ts"] = d.get("timestamp")
                        if call["is_error"] and DENIED_RE.search(call["text"][:300]):
                            call["denied"] = True
            elif t == "result":
                results.append(d)
    for r in results:
        for x in r.get("permission_denials") or []:
            call = by_id.get(x.get("tool_use_id"))
            if call is not None:
                call["denied"] = True
    return calls, msgs, results


def load_hook_output(rdir):
    path = os.path.join(rdir, "hook-output.jsonl")
    out = []
    if os.path.exists(path):
        with open(path) as fh:
            for line in fh:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass
    return out


# ---------------------------------------------------------------- roles

LOOKUP_SHELL = {"cat", "head", "tail", "grep", "egrep", "rg", "awk", "less", "more", "nl",
                "wc", "ls", "find", "tree", "file", "stat", "xxd", "od", "hexdump"}
VERIFY_SHELL = {"cmp", "diff", "sh", "bash", "time", "timeout", "hyperfine"}
SOURCE_EXT = (".tach", ".rs")


def segment_role(kind, seg):
    if kind.startswith("tachyonc:"):
        sub = kind[9:]
        if sub in ("guide", "query", "explain", "other"):
            return "lookup"
        if sub in ("edit", "refactor", "fix", "rewrite", "fmt", "undo"):
            return "edit"
        return "verify"  # check, build, test, lint, same-output, try
    if kind in ("rustc", "run", "suite", "compiler:build", "compiler:gate"):
        return "verify"
    if kind.startswith("file:"):
        t = kind[5:]
        if t in ("Read", "Grep", "Glob", "read_file"):
            return "lookup"
        return "edit"
    if kind.startswith("shell:"):
        cmd = kind[6:]
        if cmd in ("sed", "perl") and re.search(r"(^|\s)-[a-zA-Z]*i", seg):
            return "edit"
        if re.search(r">\s*\S+(%s)\b" % "|".join(re.escape(e) for e in SOURCE_EXT), seg):
            return "edit"
        if cmd in LOOKUP_SHELL or cmd == "sed":
            return "lookup"
        if cmd in VERIFY_SHELL:
            return "verify"
    return "other"


def call_kinds(call):
    """[(kind, segment text)] of one call."""
    name, inp = call["tool"], call["input"]
    if name in ("Bash", "bash"):
        segs = split_commands(inp.get("command", ""))
        out = []
        for s in segs:
            k = classify_call(name, {"command": s})
            k = [x for x in k if x != "shell:?"]
            if k:
                out.append((k[0], s))
        return out or [("shell:?", inp.get("command", ""))]
    return [(k, "") for k in classify_call(name, inp)]


def call_role(kinds):
    roles = {segment_role(k, s) for k, s in kinds}
    for r in ROLE_ORDER:
        if r in roles:
            return r
    return "other"


def call_token(call, kinds):
    """The call as one n-gram token."""
    name = call["tool"]
    if name not in ("Bash", "bash"):
        return name
    best = None
    for k, s in kinds:
        role = segment_role(k, s)
        if best is None or ROLE_ORDER.index(role) < ROLE_ORDER.index(best[0]):
            best = (role, k, s)
    if not best:
        return "shell"
    _, k, s = best
    if k.startswith("tachyonc:"):
        sub = k[9:]
        if sub in ("query", "edit", "refactor", "fix"):
            w = [x for x in _words(s) if not x.startswith("-")]
            i = next((j for j, x in enumerate(w) if x == sub), None)
            if i is not None and i + 1 < len(w) and re.match(r"^[a-z][a-z-]*$", w[i + 1]):
                return "%s:%s" % (sub, w[i + 1])
            return sub
        return sub
    if k.startswith("shell:"):
        return k[6:]
    return k.replace("compiler:", "")


# ---------------------------------------------------------------- errors

TACH_DIAG = re.compile(r"^(?:\S+?:\d+:\d+: )?error\[([^\]]+)\]:? (.+)$")
TOOL_ERR = re.compile(r"^(?:error|warning) ([a-z][a-z0-9_-]*\.[a-z0-9_.-]+): (.+)$")
RUST_DIAG = re.compile(r"^error\[(E\d{4})\]: (.+)$")
RUST_PLAIN = re.compile(r"^error: (.+)$")
RUST_SKIP = re.compile(r"aborting due to|could not compile|warnings emitted|"
                       r"^Process completed|^linking with", re.I)

CLASS_PATTERNS = [
    ("own", re.compile(r"\bown\.|use after (free|move)|outlives?\b|dangling|"
                       r"value (was )?moved", re.I)),
    ("match", re.compile(r"non-exhaustive|not covered|unreachable pattern", re.I)),
    ("unsafe", re.compile(r"\bunsafe\b", re.I)),
    ("alloc", re.compile(r"allocation is explicit|allocator|pass an alloc|\bgpa\b", re.I)),
    ("syntax", re.compile(r"^expected |unexpected|unterminated|invalid (token|character|literal)|"
                          r"not allowed here|reserved", re.I)),
    ("name", re.compile(r"unknown (module|type|function|field|variant|name|trait|method)|"
                        r"undefined (variable|function|name)|no method|no field|no variant|"
                        r"unresolved|is private|not found|cannot find|duplicate|"
                        r"has no member|no associated|is not a (module|type|trait)", re.I)),
    ("effects", re.compile(r"#\[pure\]|no_alloc|\beffect", re.I)),
]

RUST_CODE_CLASS = {}
for _c in ("E0425 E0433 E0412 E0432 E0599 E0609 E0603 E0560 E0574 E0422 E0423 E0405 E0407 "
           "E0428 E0424 E0434 E0583 E0255 E0252 E0559 E0026 E0027").split():
    RUST_CODE_CLASS[_c] = "name"
for _c in ("E0308 E0277 E0061 E0282 E0283 E0369 E0614 E0600 E0604 E0605 E0606 E0618 E0620 "
           "E0070 E0053 E0050 E0107 E0191 E0220 E0229 E0271 E0608 E0610 E0689 E0040").split():
    RUST_CODE_CLASS[_c] = "type"
for _c in "E0004 E0005 E0297".split():
    RUST_CODE_CLASS[_c] = "match"
RUST_CODE_CLASS["E0133"] = "unsafe"
for _c in ("E0382 E0499 E0502 E0505 E0506 E0507 E0515 E0716 E0597 E0596 E0384 E0381 E0373 "
           "E0106 E0495 E0621 E0623 E0508 E0509 E0594 E0712 E0713 E0503 E0501").split():
    RUST_CODE_CLASS[_c] = "own"

# Rust habits in tachyon errors: (tag, pattern on the message)
HABITS = [
    ("String/&str", re.compile(r"'(&?str|String|&str|&String)'|\bString\b")),
    ("Box/Rc/Arc", re.compile(r"'(Box|Rc|Arc|RefCell|Cell)'")),
    ("char", re.compile(r"unknown type 'char'")),
    ("std paths", re.compile(r"unknown module '(io|collections|fmt|cmp|mem|env|process|iter|"
                             r"str|string|vec|ops|convert)'|std::(io|collections|fmt)")),
    ("macro", re.compile(r"[a-z_]+!\s*\(|\bmacro|'!'", re.I)),
    ("len() on a slice", re.compile(r"no method 'len' on '\[")),
    ("Vec::new / implicit alloc", re.compile(r"allocation is explicit|'new' .*Vec|Vec::new\b")),
    ("C call without unsafe", re.compile(r"calling a C function is unsafe")),
    ("raw pointer without unsafe", re.compile(r"raw pointer.*unsafe|unsafe.*raw pointer")),
    ("wildcard import", re.compile(r"wildcard|use .*::\*|glob import", re.I)),
    ("& references", re.compile(r"'&(mut )?self'|&mut\b|got '&'|got 'mut'")),
    ("dyn/where/impl Trait", re.compile(r"'(dyn|where|impl)'|\bdyn\b")),
    ("string pattern", re.compile(r"strings are not patterns|string pattern", re.I)),
    ("Rust iterator/number method", re.compile(
        r"no method '(iter_mut|rev|step_by|abs|pow|min|max|to_string|as_str|chars|bytes|"
        r"to_owned|clone_from|lines|parse|unwrap_or_default|to_vec)'")),
    ("usize/char literals", re.compile(r"'usize'.*'i64'|'i64'.*'usize'")),
]

_MASK = re.compile(r"'[^']*'|\"[^\"]*\"|`[^`]*`|\b\d+\b")


SPECIFIC = ("own", "match", "unsafe", "alloc", "effects")


def classify_message(kind, msg):
    pats = dict(CLASS_PATTERNS)
    for cls in SPECIFIC:
        if pats[cls].search(msg):
            return cls
    if pats["name"].search(msg):
        return "name"
    k = (kind or "").lower()
    if "parse" in k or "syntax" in k or "lex" in k:
        return "syntax"
    if "module" in k:
        return "name"
    if "unsafe" in k:
        return "unsafe"
    if "type" in k:
        return "type"
    if pats["syntax"].search(msg):
        return "syntax"
    return "other"


def habit_of(msg):
    for tag, pat in HABITS:
        if pat.search(msg):
            return tag
    return None


def errors_in(text, lang, rust_build=False):
    """[(class, code, message, habit)] in a tool result or hook output."""
    out = []
    for line in (text or "").splitlines():
        line = line.strip()
        if lang == "rust":
            m = RUST_DIAG.match(line)
            if m:
                code, msg = m.group(1), m.group(2)
                out.append((RUST_CODE_CLASS.get(code, "other"), code, msg, None))
                continue
            m = RUST_PLAIN.match(line)
            if m and rust_build and not RUST_SKIP.search(m.group(1)):
                msg = m.group(1)
                cls = classify_message("", msg)
                out.append(("syntax" if cls == "other" and "expected" in msg else cls,
                            "", msg, None))
            continue
        m = TACH_DIAG.match(line)
        if m:
            kind, msg = m.group(1), m.group(2)
            msg = re.split(r" \| help:|  \[(in|edited):", msg)[0].strip()
            out.append((classify_message(kind, msg), kind, msg, habit_of(msg)))
    return out


def tool_errors_in(text):
    """[(code, message)]: tachyonc tool problems (`error patch.no-match: ...`)."""
    out = []
    for line in (text or "").splitlines():
        m = TOOL_ERR.match(line.strip())
        if m and line.strip().startswith("error"):
            out.append((m.group(1), m.group(2)))
    return out


# ---------------------------------------------------------------- denials

def denial_causes(call, ws=None):
    """(primary cause, [every form]) of a denied call."""
    name, inp = call["tool"], call["input"]
    if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        p = inp.get("file_path") or ""
        if ws and not os.path.realpath(p).startswith(os.path.realpath(ws)):
            return "file-outside", ["file-outside"]
        if not ws and p.startswith(("/tmp/", "/private/", "/var/")):
            return "file-outside", ["file-outside"]
        return "file", ["file"]
    if name not in ("Bash", "bash"):
        return "tool:" + str(name), ["tool:" + str(name)]
    cmd = inp.get("command", "")
    forms = []
    if re.search(r"<<-?\s*['\"]?\w+", cmd):
        forms.append("heredoc")
    if re.search(r"\$\(|`", cmd):
        forms.append("subst")
    if re.search(r"\$[?#@*!$]|\$\{?[A-Za-z_]", re.sub(r"'[^']*'", "", cmd)):
        forms.append("var")
    if re.search(r"(^|[;&|\n]\s*|\s)(for|while|until)\s", cmd):
        forms.append("loop")
    if re.search(r"(^|[;&|\n(]\s*)cd\s", cmd):
        forms.append("cd")
    try:
        from lib.claude_backend import ALLOW
    except Exception:  # pragma: no cover
        ALLOW = []
    allowed = set(ALLOW)
    for seg in split_commands(cmd):
        w = _words(seg)
        while w and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0]):
            w = w[1:]
        if not w:
            continue
        head = w[0].strip("'\"")
        if head in ("for", "while", "until", "do", "done", "if", "then", "fi", "else", "in",
                    "case", "esac", "{", "}", "!"):
            continue
        if head.startswith("./") or head in allowed:
            continue
        if not any(head == a or head.startswith(a + " ") for a in allowed):
            forms.append("unlisted")
            break
    if re.search(r"&&|\|\||;|\n", re.sub(r"<<-?\s*['\"]?(\w+)['\"]?.*?^\1$", "", cmd,
                                          flags=re.S | re.M)):
        forms.append("chain")
    if re.search(r"(?<![|])\|(?![|])", cmd):
        forms.append("pipe")
    if re.search(r"(?<![0-9&])>{1,2}\s*[^&\s]", cmd):
        forms.append("redirect")
    order = ("heredoc", "subst", "var", "loop", "cd", "unlisted", "chain", "pipe", "redirect")
    for f in order:
        if f in forms:
            return f, forms
    return "other", forms or ["other"]


# ---------------------------------------------------------------- erosion

ITEM_RE = {
    ".tach": re.compile(r"^\s*(?:pub\s+)?(?:unsafe\s+)?(fn|struct|enum|trait|type|const|static)\s+"
                        r"(?:mut\s+)?([A-Za-z_][A-Za-z0-9_]*)", re.M),
    ".rs": re.compile(r"^\s*(?:pub(?:\([a-z]+\))?\s+)?(?:unsafe\s+)?(fn|struct|enum|trait|type|"
                      r"const|static)\s+(?:mut\s+)?([A-Za-z_][A-Za-z0-9_]*)", re.M),
}
ASSERT_RE = re.compile(r"\bassert|\bexpect\b|//\s*(expect|out|check)|#\[test\]|\btest_", re.I)


def _sources(d):
    out = {}
    if not d or not os.path.isdir(d):
        return out
    for root, dirs, files in os.walk(d):
        dirs[:] = [x for x in dirs if x not in (".git", "target")]
        for f in files:
            p = os.path.join(root, f)
            rel = os.path.relpath(p, d)
            try:
                with open(p, encoding="utf-8", errors="replace") as fh:
                    out[rel] = fh.read() if os.path.getsize(p) < 2 << 20 else ""
            except OSError:
                pass
    return out


def erosion_dirs(starter, final):
    a, b = _sources(starter), _sources(final)
    items_a, items_b = set(), set()
    for rel, text in a.items():
        ext = os.path.splitext(rel)[1]
        if ext in ITEM_RE:
            items_a |= {m.group(2) for m in ITEM_RE[ext].finditer(text)}
    for rel, text in b.items():
        ext = os.path.splitext(rel)[1]
        if ext in ITEM_RE:
            items_b |= {m.group(2) for m in ITEM_RE[ext].finditer(text)}
    gone_files = sorted(r for r in a if r not in b)
    gone_tests = [r for r in gone_files if "test" in r.lower() or r.endswith((".in", ".out"))]
    asserts_a = Counter(l.strip() for t in a.values() for l in t.splitlines() if ASSERT_RE.search(l))
    asserts_b = Counter(l.strip() for t in b.values() for l in t.splitlines() if ASSERT_RE.search(l))
    gone_asserts = sum((asserts_a - asserts_b).values())
    gone_items = sorted(items_a - items_b)
    return {"items_removed": len(gone_items), "items": gone_items[:20],
            "files_removed": len(gone_files), "test_files_removed": len(gone_tests),
            "asserts_removed": gone_asserts}


def erosion_patch(patch_path):
    if not patch_path or not os.path.exists(patch_path):
        return None
    with open(patch_path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    removed_items, added_items = set(), set()
    gone_files, gone_tests, gone_asserts = [], [], 0
    cur = None
    added_lines, removed_lines = Counter(), Counter()
    for line in text.splitlines():
        if line.startswith("diff --git"):
            cur = line.split(" b/", 1)[-1]
        elif line.startswith("deleted file mode") and cur:
            gone_files.append(cur)
            if cur.startswith("tests/"):
                gone_tests.append(cur)
        elif line.startswith("-") and not line.startswith("---"):
            removed_lines[line[1:].strip()] += 1
            m = ITEM_RE[".tach"].match(line[1:])
            if m:
                removed_items.add(m.group(2))
        elif line.startswith("+") and not line.startswith("+++"):
            added_lines[line[1:].strip()] += 1
            m = ITEM_RE[".tach"].match(line[1:])
            if m:
                added_items.add(m.group(2))
    for l, n in (removed_lines - added_lines).items():
        if ASSERT_RE.search(l):
            gone_asserts += n
    gone_items = sorted(removed_items - added_items)
    return {"items_removed": len(gone_items), "items": gone_items[:20],
            "files_removed": len(gone_files), "test_files_removed": len(gone_tests),
            "asserts_removed": gone_asserts}


# ---------------------------------------------------------------- the run

EDIT_FAIL = re.compile(r"error (patch|edit|refactor|rewrite|fix)\.[a-z.-]+:|"
                       r"String to replace not found|old_string.*not found|"
                       r"File has not been read yet|has been modified since read|"
                       r"Found \d+ matches of the string", re.I)


def _ngrams(seq, n):
    return Counter(" > ".join(seq[i:i + n]) for i in range(len(seq) - n + 1))


def for_run(rdir, res, starter=None, final=None):
    lang = res.get("lang") or ("rust" if res.get("cond") == "rust" else "tach")
    calls, msgs, results = load(rdir)
    hooks = load_hook_output(rdir)
    hook_by_id = {}
    for h in hooks:
        if h.get("tool_use_id"):
            hook_by_id.setdefault(h["tool_use_id"], []).append(h)
    a = {"version": 1}

    # tokens and turns
    prompts = [(u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
               + (u.get("cache_read_input_tokens") or 0) for u in msgs]
    a["tokens"] = {
        "turns": res.get("turns"), "model_calls": len(msgs),
        "output": res.get("output_tokens"),
        "fresh": (res.get("input_tokens") or 0) - (res.get("cache_read_tokens") or 0)
        - (res.get("cache_creation_tokens") or 0),
        "cache_write": res.get("cache_creation_tokens"), "cache_read": res.get("cache_read_tokens"),
        "cost": res.get("cost_usd"),
        "first_prompt": prompts[0] if prompts else None,
        "median_prompt": int(statistics.median(prompts)) if prompts else None,
        "max_prompt": max(prompts) if prompts else None,
    }

    # roles, tokens, guide topics
    roles, seg_roles, seq, topics = Counter(), Counter(), [], []
    first_edit = None
    per_call = []
    for i, c in enumerate(calls, 1):
        kinds = call_kinds(c)
        role = call_role(kinds)
        roles[role] += 1
        for k, s in kinds:
            seg_roles[segment_role(k, s)] += 1
            if k == "tachyonc:guide":
                w = [x for x in _words(s)]
                j = w.index("guide") if "guide" in w else -1
                topics.append(" ".join(x.strip("'\"") for x in w[j + 1:j + 4]) or "core")
        tok = call_token(c, kinds)
        seq.append(tok)
        if role == "edit" and first_edit is None and not c["denied"]:
            first_edit = i
        per_call.append((c, kinds, role, tok))
    a["roles"] = dict(roles)
    a["segment_roles"] = dict(seg_roles)
    a["first_edit_call"] = first_edit
    a["calls"] = len(calls)
    a["guide_topics"] = topics

    # errors: tool results (and the hooks' output for that call)
    errs, distinct, seen_err = [], {}, set()
    tool_errs = Counter()
    repair, open_ep = [], None
    edit_fail, edit_next = [], []
    pending_fail = None
    for i, (c, kinds, role, tok) in enumerate(per_call, 1):
        # the guide and explain print example diagnostics: not errors met
        reads_docs = any(k in ("tachyonc:guide", "tachyonc:explain") for k, _ in kinds) or (
            c["tool"] == "Read" and not str(c["input"].get("file_path", "")).endswith(SOURCE_EXT))
        texts = ([] if reads_docs else [c["text"]]) + [
            h.get("stdout", "") + "\n" + h.get("stderr", "") for h in hook_by_id.get(c["id"], [])]
        rust_build = any(k == "rustc" for k, _ in kinds)
        found = []
        for t in texts:
            found += errors_in(t, lang if lang in ("rust", "tach") else "tach", rust_build)
            # the check hook's additionalContext is JSON in stdout
            if t.lstrip().startswith("{") and "additionalContext" in t:
                try:
                    ctxt = json.loads(t.strip().splitlines()[0])["hookSpecificOutput"][
                        "additionalContext"]
                    found += errors_in(ctxt, "tach")
                except (ValueError, KeyError, IndexError, TypeError):
                    pass
        for code, _ in tool_errors_in(c["text"]):
            tool_errs[code] += 1
        for cls, code, msg, habit in found:
            key = (cls, _MASK.sub("_", msg)[:120])
            errs.append({"class": cls, "code": code, "msg": msg[:160], "habit": habit, "call": i})
            if key not in seen_err:
                seen_err.add(key)
                distinct[key] = {"class": cls, "code": code, "msg": msg[:160], "habit": habit,
                                 "call": i}
        verify_like = role in ("verify", "edit") and any(
            k in ("tachyonc:check", "tachyonc:build", "rustc", "tachyonc:test")
            or k.startswith("file:Write") or k.startswith("file:Edit")
            or k in ("tachyonc:edit", "tachyonc:refactor", "tachyonc:fix")
            for k, _ in kinds)
        if found and not c["denied"]:
            if open_ep is None:
                open_ep = {"start": i, "errors": set()}
            open_ep["errors"] |= {(e[0], _MASK.sub("_", e[2])[:120]) for e in found}
        elif open_ep is not None and verify_like and not c["denied"] and not (
                c["is_error"] and any(k in ("tachyonc:build", "rustc", "tachyonc:check")
                                      for k, _ in kinds)):
            repair.append({"calls": i - open_ep["start"], "errors": len(open_ep["errors"])})
            open_ep = None
        # edit recovery
        if role == "edit" and not c["denied"]:
            failed = bool(EDIT_FAIL.search(c["text"] or "")) or (
                c["is_error"] and c["tool"] in ("Edit", "Write", "MultiEdit"))
            if pending_fail is not None:
                edit_next.append(not failed)
                pending_fail = None
            if failed:
                m = EDIT_FAIL.search(c["text"] or "")
                edit_fail.append((m.group(0)[:40] if m else "tool error").rstrip(":"))
                pending_fail = i
    if open_ep is not None:
        repair.append({"calls": None, "errors": len(open_ep["errors"])})
    a["errors"] = list(distinct.values())[:80]
    a["errors_seen"] = len(errs)
    a["classes"] = dict(Counter(e["class"] for e in distinct.values()))
    a["habits"] = dict(Counter(e["habit"] for e in distinct.values() if e["habit"]))
    a["tool_errors"] = dict(tool_errs)
    closed = [r for r in repair if r["calls"] is not None]
    a["repair"] = {"episodes": len(repair), "unclosed": len(repair) - len(closed),
                   "calls": sum(r["calls"] for r in closed),
                   "errors_fixed": sum(r["errors"] for r in closed),
                   "calls_per_error": round(sum(r["calls"] for r in closed)
                                            / max(1, sum(r["errors"] for r in closed)), 2)
                   if closed else None}
    a["edit_recovery"] = {"failures": len(edit_fail), "by": dict(Counter(edit_fail)),
                          "next_ok": sum(1 for x in edit_next if x),
                          "next_failed": sum(1 for x in edit_next if not x)}

    # denials
    ws = final if final and os.path.isdir(final) else None
    den = []
    for c in calls:
        if c["denied"]:
            primary, forms = denial_causes(c, ws)
            den.append({"cause": primary, "forms": forms,
                        "input": json.dumps(c["input"])[:160]})
    a["denials"] = {"count": len(den), "by_cause": dict(Counter(d["cause"] for d in den)),
                    "by_form": dict(Counter(f for d in den for f in d["forms"])),
                    "examples": den[:8]}

    # n-grams
    a["sequence"] = seq[:400]
    a["ngrams"] = {"2": dict(_ngrams(seq, 2).most_common(12)),
                   "3": dict(_ngrams(seq, 3).most_common(12))}

    # query hook: blocks and whether the suggestion was followed
    blocks = []
    order = {c["id"]: i for i, c in enumerate(calls)}
    for h in hooks:
        if h.get("hook") == "query-first.py" and h.get("exit") == 2:
            m = re.search(r"try: ([^|\n]+)", h.get("stderr", "") + h.get("stdout", ""))
            sug = m.group(1).strip() if m else ""
            i = order.get(h.get("tool_use_id"))
            nxt = calls[i + 1]["input"].get("command", "") if i is not None and i + 1 < len(
                calls) else ""
            sw = sug.split()[:3]
            followed = bool(sw) and all(w in nxt for w in sw[1:3]) if len(sw) >= 3 else False
            blocks.append({"suggested": sug[:160], "followed": followed})
    if blocks:
        a["query_hook"] = {"blocks": len(blocks),
                           "followed": sum(1 for b in blocks if b["followed"]),
                           "examples": blocks[:6]}

    # intent erosion
    if res.get("lang") == "compiler":
        a["erosion"] = erosion_patch(os.path.join(rdir, "changes.patch"))
    elif starter and final:
        a["erosion"] = erosion_dirs(starter, final)
    return a


def safe_for_run(rdir, res, starter=None, final=None):
    try:
        return for_run(rdir, res, starter, final)
    except Exception as e:  # the analysis never fails a run
        return {"error": repr(e)[:300]}


# ---------------------------------------------------------------- run.py analyze

def analyze_main(args):
    """run.py analyze RUNDIR...: computes `anatomy` for finished runs (the
    0.16 round's too); --write stores it in result.json; --check reconciles
    the role totals with tool_calls_by_kind and prints the error classes."""
    import shutil
    import tarfile
    import tempfile
    from lib.common import EVAL_DIR, write_json
    tmp = tempfile.mkdtemp(prefix="tachyon-eval-analyze-")
    n = bad = 0
    classes, habits, msgs = Counter(), Counter(), Counter()
    try:
        for top in args.rundirs:
            for root, _, files in os.walk(top):
                if "result.json" not in files:
                    continue
                with open(os.path.join(root, "result.json")) as fh:
                    res = json.load(fh)
                starter = final = None
                if res.get("lang") in ("tach", "rust") and "workspace.tar.gz" in files:
                    tdir = os.path.join(EVAL_DIR, "tasks", res["task"], res["lang"])
                    if os.path.isdir(tdir):
                        starter = tdir
                        fdir = os.path.join(tmp, "ws")
                        shutil.rmtree(fdir, ignore_errors=True)
                        os.makedirs(fdir)
                        with tarfile.open(os.path.join(root, "workspace.tar.gz")) as tf:
                            tf.extractall(fdir)
                        top_ = os.listdir(fdir)
                        final = os.path.join(fdir, top_[0]) if len(top_) == 1 else fdir
                a = safe_for_run(root, res, starter, final)
                n += 1
                if args.check and "error" not in a:
                    total = sum((res.get("tool_calls_by_kind") or {}).values())
                    seg = sum(a["segment_roles"].values())
                    if total != seg:
                        bad += 1
                        print("MISMATCH %s: tool_calls_by_kind %d, segments %d" % (root, total, seg))
                if "error" in a:
                    print("ERROR %s: %s" % (root, a["error"]))
                    continue
                if res.get("lang") != "rust":
                    for e in a["errors"]:
                        classes[e["class"]] += 1
                        if e["habit"]:
                            habits[e["habit"]] += 1
                        msgs[_MASK.sub("_", e["msg"])[:70]] += 1
                if args.write:
                    res["anatomy"] = a
                    write_json(os.path.join(root, "result.json"), res)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    tot = sum(classes.values()) or 1
    print("%d runs analysed%s" % (n, ", %d mismatched" % bad if args.check else ""))
    print("tachyon distinct errors by class (per run, summed): " + ", ".join(
        "%s %d (%.0f%%)" % (k, v, 100.0 * v / tot) for k, v in classes.most_common()))
    print("Rust habits: " + ", ".join("%s %d" % kv for kv in habits.most_common()))
    print("top messages:")
    for m, k in msgs.most_common(args.top):
        print("  %4d  %s" % (k, m))
    return 1 if bad else 0
