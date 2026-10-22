"""Classifies an agent's tool calls: volec subcommands, builds, runs,
shell reads, file tools."""

import os
import re

TACH_SUBS = {"query", "edit", "refactor", "check", "fix", "explain", "guide",
             "undo", "rewrite", "fmt", "lint", "same-output"}
# The volec subcommands that read or change code (the "tools").
TACH_TOOL_SUBS = TACH_SUBS - {"guide"}
SHELL_READS = {"cat", "head", "tail", "sed", "grep", "egrep", "rg", "awk",
               "less", "more", "nl", "wc", "cut"}
FILE_TOOLS = {"Read", "Write", "Edit", "MultiEdit", "Glob", "Grep",
              "read_file", "write_file", "edit_file"}
PREFIXES = {"time", "timeout", "gtimeout", "env", "nice", "command", "exec",
            "sudo", "then", "do", "else", "if", "while", "!"}

_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def _strip_heredocs(cmd):
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        delims = [m.group(2) for m in _HEREDOC.finditer(line)]
        i += 1
        for d in delims:
            while i < len(lines) and lines[i].strip() != d:
                i += 1
            i += 1
    return "\n".join(out)


def split_commands(cmd):
    """The simple commands of a shell line, roughly: split at newlines,
    ; && || | & outside quotes, heredoc bodies dropped."""
    s = _strip_heredocs(cmd)
    segs, cur, q, i = [], [], None, 0
    while i < len(s):
        c = s[i]
        if q:
            cur.append(c)
            if c == q:
                q = None
            elif c == "\\" and q == '"' and i + 1 < len(s):
                cur.append(s[i + 1])
                i += 1
        elif c in "'\"":
            q = c
            cur.append(c)
        elif c == "\\" and i + 1 < len(s):
            if s[i + 1] != "\n":
                cur.append(s[i:i + 2])
            i += 1
        elif c == "$" and s[i + 1:i + 2] == "{":
            j = s.find("}", i)
            j = len(s) - 1 if j < 0 else j
            cur.append(s[i:j + 1])
            i = j
        elif c == "&" and ((i > 0 and s[i - 1] in "<>")
                           or (i + 1 < len(s) and s[i + 1] == ">")):
            cur.append(c)  # 2>&1, &>
        elif c in "\n;|&()`{}":
            segs.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    segs.append("".join(cur))
    return [x.strip() for x in segs if x.strip()]


def _words(seg):
    return re.findall(r"""'[^']*'|"(?:\\.|[^"])*"|\S+""", seg)


def classify_command(seg):
    w = _words(seg)
    while w and (w[0] in PREFIXES or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0])
                 or (w[0].replace(".", "").isdigit() and len(w) > 1)
                 or w[0].startswith("-")):
        w = w[1:]
    if not w:
        return None
    head = w[0].strip("'\"")
    base = os.path.basename(head)
    if base in ("sh", "bash") and len(w) > 1 and os.path.basename(w[1]) in (
            "eval-build.sh", "bootstrap.sh", "gate.sh", "run.sh"):
        w = w[1:]  # (sh bootstrap/eval-build.sh)
        head = w[0]
        base = os.path.basename(head)
    # (0.15) a copy (volec-old, tc0) or a variable ($T) running a
    # volec subcommand counts as volec
    sub_next = len(w) > 1 and w[1] in TACH_SUBS
    if (base.startswith("volec") or (re.match(r"^tc[\w.+-]*$", base) and sub_next)
            or (re.match(r"^\$\{?\w+\}?$", head) and sub_next)):
        for a in w[1:]:
            if a.startswith("-"):
                continue
            return "volec:" + a if a in TACH_SUBS else "volec:build"
        return "volec:other"  # --version, --help
    if base == "rustc":
        return "rustc"
    # (0.16) the compiler tasks: building the compiler, the test suite
    if base in ("eval-build.sh", "bootstrap.sh"):
        return "compiler:build"
    if base == "gate.sh":
        return "compiler:gate"
    if base == "run.sh" and "tests/" in head:
        return "suite"
    if head.startswith("./") or head.startswith("/") and base == "prog":
        return "run"
    if base in ("for", "in", "done", "fi", "esac", "case", "until"):
        return None
    return "shell:" + base


def classify_call(tool, args):
    """[kind] for one tool call (a bash line may hold several commands)."""
    if tool in ("Bash", "bash"):
        cmd = (args or {}).get("command", "")
        kinds = [k for k in (classify_command(s) for s in split_commands(cmd)) if k]
        return kinds or ["shell:?"]
    return ["file:" + tool]


def is_tach_tool(kind):
    return kind.startswith("volec:") and kind[9:] in TACH_TOOL_SUBS


def is_plain_code_access(kind):
    """Reading or changing code without volec: file tools, shell reads."""
    if kind.startswith("file:"):
        return True
    return kind.startswith("shell:") and kind[6:] in SHELL_READS
