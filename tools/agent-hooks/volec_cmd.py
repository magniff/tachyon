"""Finding the volec invocations in a shell command line, shared by the
hooks (query-first.py, check-after-edit.py) and tools/agent-tool-usage.py.

Agents do not always type `volec`: they run copies whose own builds do
not replace them (`target/tc0`, `target/tools/volec`) and keep the path
in a shell variable (`T=target/tc0; $T query show x`). 0.14's hook missed
those (51 tool edits and about 280 queries; docs/tool-gaps-014.md, gap 10).
Here a command is volec when its program

- has a basename starting with `volec` (any path, any suffix);
- has a basename starting with `tc` (`tc0`, `tc-new`) and is followed by a
  volec subcommand or a `.vl` file (so `tclsh`, `tcpdump` are not);
- is a shell variable (`$T`, `${T}`, `"$T"`) assigned one of those
  earlier in the same command line, or, unassigned there (set in an
  earlier call), followed by a volec subcommand.

Development tooling only: Python stdlib, no state.
"""
import os
import re
import shlex

SUBCOMMANDS = {"query", "edit", "refactor", "rewrite", "check", "fix", "undo", "fmt",
               "explain", "guide", "lint", "same-output", "test", "try", "batch"}
# Commands that run another command named by their arguments.
WRAPPERS = {"time", "env", "nice", "command", "exec", "timeout", "gtimeout", "then", "do",
            "else", "if", "while", "until", "!"}
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\s*(\n|$)", re.S)
ASSIGN = re.compile(r"^([A-Za-z_]\w*)=(.*)$", re.S)
VAR = re.compile(r"^\$(?:\{(\w+)\}|(\w+))$")


def segments(command):
    """The simple commands of a command line: split at `;`, `|`, `&`, `||`,
    `&&`, newlines and parentheses outside quotes; comments and
    here-document bodies left out."""
    body = HEREDOC.sub("<<HEREDOC\n", command)
    return [body[s:e] for s, e in _spans(body)]


def segment_spans(command):
    """(0.17, chained rewrites) [(start, end)] of each simple command of
    segments(command) in command itself, so that one command of a line can
    be replaced and the rest kept as typed; None for a line with a
    here-document (its body is not split)."""
    if "<<" in command and HEREDOC.search(command):
        return None
    return _spans(command)


def _spans(body):
    out, start, end, quote, i = [], None, 0, None, 0

    def take(a, b):
        nonlocal start, end
        if start is None:
            start = a
        end = b

    def cut():
        nonlocal start
        if start is not None:
            s, e = start, end
            while s < e and body[s].isspace():
                s += 1
            while e > s and body[e - 1].isspace():
                e -= 1
            if e > s:
                out.append((s, e))
        start = None
    while i < len(body):
        c = body[i]
        if quote:
            take(i, i + 1)
            if c == "\\" and quote == '"' and i + 1 < len(body):
                take(i, i + 2)
                i += 1
            elif c == quote:
                quote = None
        elif c == "\\" and i + 1 < len(body):
            take(i, i + 2)
            i += 1
        elif c in "'\"":
            quote = c
            take(i, i + 1)
        elif c == "#" and (start is None or body[end - 1] in " \t"):
            while i < len(body) and body[i] != "\n":
                i += 1
            continue
        elif c == "$" and body[i + 1:i + 2] in ("{", "("):
            # ${VAR} stays one word; $(...) is a command of its own
            if body[i + 1] == "{":
                j = body.find("}", i)
                j = len(body) - 1 if j < 0 else j
                take(i, j + 1)
                i = j
            else:
                cut()
                i += 1
        elif c == "&" and ((start is not None and body[end - 1] in "<>") or body[i + 1:i + 2] == ">"):
            take(i, i + 1)  # (2>&1, &>)
        elif c in ";|&\n()`":
            cut()
        else:
            take(i, i + 1)
        i += 1
    cut()
    return out


def words_of(segment):
    """The words of one simple command (from segments(), which leaves the
    comments out: a `#` inside a word, `guide std#Vec`, is the word's)."""
    try:
        return shlex.split(segment)
    except ValueError:
        return segment.split()


def _looks_volec(path, rest):
    base = os.path.basename(path)
    if base.startswith("volec"):
        return True
    if re.match(r"^tc[\w.+-]*$", base):
        return bool(rest) and (rest[0] in SUBCOMMANDS or any(a.endswith(".vl") for a in rest))
    return False


def program(words, assigns):
    """(program, the words after it, whether it is volec, the path it
    resolves to) of one simple command's words; VAR=value prefixes and
    wrappers (time, env, ...) skipped. `assigns` maps the shell variables
    assigned earlier on the line to their values."""
    w = list(words)
    while w and (w[0] in WRAPPERS or ASSIGN.match(w[0]) or (w[0].startswith("-") and len(w) > 1)
                 or re.match(r"^\d+(\.\d+)?[smh]?$", w[0])):
        w = w[1:]
    if not w:
        return "", [], False, ""
    head, rest = w[0], w[1:]
    m = VAR.match(head)
    if m:
        name = m.group(1) or m.group(2)
        value = assigns.get(name)
        if value is not None and "$" not in value:
            return value, rest, _looks_volec(value, rest), value
        return head, rest, bool(rest) and rest[0] in SUBCOMMANDS, ""
    return head, rest, _looks_volec(head, rest), head


def expand(word, assigns):
    """word with `$VAR`, `${VAR}` assigned earlier on the line (and a
    leading `~`) replaced; None when it names a variable not assigned
    there (its value is not known)."""
    if word.startswith("~"):
        word = os.path.expanduser(word)
    unknown = []

    def sub(m):
        name = m.group(1) or m.group(2)
        if name in assigns and "$" not in assigns[name]:
            return assigns[name]
        unknown.append(name)
        return m.group(0)
    out = re.sub(r"\$(?:\{(\w+)\}|(\w+))", sub, word)
    return None if unknown else out


def located(command, cwd):
    """[(segment, words, the directory it runs in, assigns)] of each simple
    command of command: a `cd DIR` (DIR relative to the directory before it,
    `$VAR` assigned earlier on the line expanded) moves the commands after
    it, so `cd WORKTREE && volec edit ...` runs in WORKTREE (0.17). A cd
    whose directory is not known (`cd $X` set in an earlier call, `cd -`)
    leaves the directory as it was."""
    assigns, out, here = {}, [], os.path.abspath(cwd or os.getcwd())
    for seg in segments(command):
        words = words_of(seg)
        if words and words[0] in ("export", "local", "declare", "readonly"):
            words = words[1:]
        if words and all(ASSIGN.match(x) for x in words):
            for x in words:
                name, value = ASSIGN.match(x).groups()
                assigns[name] = value
            out.append((seg, words, here, with_pwd(assigns, here)))
            continue
        out.append((seg, words, here, with_pwd(assigns, here)))
        if words and words[0] in ("cd", "pushd") and len(words) <= 2:
            target = expand(words[1], with_pwd(assigns, here)) if len(words) == 2 else os.path.expanduser("~")
            if target and target != "-":
                here = os.path.normpath(os.path.join(here, target))
    return out


def with_pwd(assigns, here):
    """assigns with `PWD` (the directory a command runs in, unless the line
    assigns it): `cd "$PWD" && ...` stays where it is, `$PWD/x.vl` is
    known."""
    out = dict(assigns)
    out.setdefault("PWD", here)
    return out


def calls_at(command, cwd):
    """calls(command), each with the directory it runs in: [(subcommand,
    words, path, segment, directory)]."""
    found = []
    for seg, words, here, assigns in located(command, cwd):
        if words and all(ASSIGN.match(x) for x in words):
            continue
        _, rest, is_tc, path = program(words, assigns)
        if not is_tc:
            continue
        sub = next((a for a in rest if not a.startswith("-")), "")
        if sub not in SUBCOMMANDS:
            sub = "build" if any(a.endswith(".vl") for a in rest) else "other"
        found.append((sub, rest, path, seg, here))
    return found


def calls(command):
    """[(subcommand, words after the program, resolved path, segment)] of
    each volec invocation in command; the subcommand is `build` for a
    compile (a .vl operand), `other` otherwise (--version, no
    arguments)."""
    assigns, found = {}, []
    for seg in segments(command):
        words = words_of(seg)
        if words and words[0] in ("export", "local", "declare", "readonly"):
            words = words[1:]
        if words and all(ASSIGN.match(x) for x in words):
            for x in words:
                name, value = ASSIGN.match(x).groups()
                assigns[name] = value
            continue
        _, rest, is_tc, path = program(words, assigns)
        if not is_tc:
            continue
        sub = next((a for a in rest if not a.startswith("-")), "")
        if sub not in SUBCOMMANDS:
            sub = "build" if any(a.endswith(".vl") for a in rest) else "other"
        found.append((sub, rest, path, seg))
    return found


def program_name(segment, assigns):
    """The program of one simple command, `volec` for any volec
    (a copy, a variable), for tallies; `assigns` is updated with the
    command's assignments."""
    words = words_of(segment)
    if words and all(ASSIGN.match(x) for x in words):
        for x in words:
            name, value = ASSIGN.match(x).groups()
            assigns[name] = value
        return ""
    head, rest, is_tc, _ = program(words, assigns)
    if is_tc:
        return "volec"
    return os.path.basename(head)
