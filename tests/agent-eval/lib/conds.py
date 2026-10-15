"""(0.17) Conditions: a base name and modifiers, `BASE[+MOD...]`.

Program tasks (tasks/):

- `bare`, `guide`, `tools`, `both`, `rust` (0.13-0.16): the language
  preamble; `guide` inlines `tachyonc guide` (today's core topic, ~7k
  tokens); `tools` the tools table (prompts/tools.md); `both` the two;
  `rust` the control.
- `guide-core`: bare + the ~2k-token example-first core guide: the intro
  prompts/guide-core.md and the output of `tachyonc guide` from a compiler
  whose core is the short one (0.17: it also has `tachyonc guide --full`,
  the old ~7k core, which the `guide` condition then inlines so that it
  stays the 0.16 control; a compiler without `--full` runs guide-core only
  as a dry run).
- `tools-core`: bare + the tiered tools preamble (prompts/tools-core.md:
  eight rows, `query context` first, and where the rest is).
- `both-core`: guide-core + tools-core (what a user gets once both land).
- `guide-mini` (0.17 iterations): bare + prompts/guide-mini.md, a ~600-token
  always-loaded core (the main Rust differences in one compiled example,
  then the lookup lines); with `+readfirst` the iteration-1 cell.
- `rust-pairs`: bare + paired Rust -> tachyon lines (prompts/rust-pairs.md),
  about the core guide's budget: the differences shown as pairs instead
  of tachyon-only examples.

Compiler tasks (ctasks/):

- `compiler-tools`, `compiler-plain` (0.16): AGENTS.md as it is with the
  hooks; AGENTS.md without the tools table, no hooks.
- `compiler-tools-core`: the base's AGENTS.md with its "Read source
  through the compiler" section replaced by this checkout's (0.17: the
  tiered eight-row core), the hooks as in compiler-tools. (The task's base
  is v0.16.0, so `compiler-tools` keeps 0.16's full table: the control.)

Modifiers, any order after the base:

- `+hook`: the check hook (tools/agent-hooks/check-after-edit.py after
  every change to a .tach file) and its prompt note; what `--check-hook`
  does for tools/both, for any tachyon condition. Always on in the
  compiler-tools conditions.
- `+test`: `tachyonc test` named in the prompt (prompts/test.md) and the
  hooks of tools/agent-hooks/settings-eval.json (the check hook that also
  runs the tests); until that file exists the condition runs only as a
  dry run. Needs a compiler with `tachyonc test` (the self-check probes it).
- `+turn-end`: the Stop hook (tools/agent-hooks/turn-end.py: a check of
  what changed when the agent stops; errors block the stop once); with
  +hook the check hook too (settings-eval.json's `hook+turn-end`), alone
  only the Stop hook (`turn-end`). +test includes it.
- `+recite`: one line after the task (prompts/recite.md): look a construct
  up with `guide --find` / `guide TOPIC#SECTION` before writing it (the
  research plan's item 9; the guide-core intro already says it).
- `+readfirst` (0.17 iterations): prompts/readfirst.md after the guide:
  read the code in the directory first, follow its patterns, look up
  (`guide --find`, `guide TOPIC#SECTION`) only what the code does not show.

`both+hook+test` is the rerun matrix's row D cell; `compiler-tools-core+test`
the compiler one.

(0.17) Every hook a condition registers but the query-first hook comes
from tools/agent-hooks/settings-eval.json, the condition's entry of it
named by `settings_key` (`hook`, `hook+test`, `hook+turn-end`,
`turn-end`): the hooks' own definition of each condition."""

import os

from lib.common import HOOKS_DIR, PROMPTS_DIR

PROGRAM_BASES = ("bare", "guide", "tools", "both", "guide-core", "tools-core", "both-core",
                 "rust-pairs", "guide-mini", "rust")
COMPILER_BASES = ("compiler-tools", "compiler-plain", "compiler-tools-core")
BASES = PROGRAM_BASES + COMPILER_BASES
MODS = ("hook", "test", "turn-end", "recite", "readfirst")

# What each base puts in the prompt: guide (None, "full": `tachyonc guide`,
# "core": prompts/guide-core.md), tools (None, "full": tools.md, "core":
# tools-core.md), pairs (rust-pairs.md), compiler (None, "full", "plain",
# "core": the AGENTS.md variant).
_PARTS = {
    "bare": {},
    "guide": {"guide": "full"},
    "tools": {"tools": "full"},
    "both": {"guide": "full", "tools": "full"},
    "guide-core": {"guide": "core"},
    "tools-core": {"tools": "core"},
    "both-core": {"guide": "core", "tools": "core"},
    "rust-pairs": {"pairs": True},
    "guide-mini": {"guide": "mini"},
    "rust": {},
    "compiler-tools": {"compiler": "full"},
    "compiler-plain": {"compiler": "plain"},
    "compiler-tools-core": {"compiler": "core"},
}

# Files a condition needs that other branches write; a hosted run refuses
# to start without them, a dry run uses a stub and says so.
GUIDE_CORE = os.path.join(PROMPTS_DIR, "guide-core.md")
SETTINGS_EVAL = os.path.join(HOOKS_DIR, "settings-eval.json")


class Cond:
    def __init__(self, name):
        parts = name.split("+")
        self.name = name
        self.base = parts[0]
        self.mods = tuple(parts[1:])
        if self.base not in BASES:
            raise ValueError("unknown condition %r (bases: %s)" % (name, ", ".join(BASES)))
        bad = [m for m in self.mods if m not in MODS]
        if bad or len(set(self.mods)) != len(self.mods):
            raise ValueError("condition %r: modifiers are +%s, each once" % (name, ", +".join(MODS)))
        p = _PARTS[self.base]
        self.guide = p.get("guide")
        self.tools = p.get("tools")
        self.pairs = bool(p.get("pairs"))
        self.compiler = p.get("compiler")
        self.is_compiler = self.compiler is not None
        self.lang = "compiler" if self.is_compiler else ("rust" if self.base == "rust" else "tach")
        self.test = "test" in self.mods
        self.recite = "recite" in self.mods
        self.readfirst = "readfirst" in self.mods
        self.turn_end = "turn-end" in self.mods or self.test
        if self.lang == "rust" and self.mods:
            raise ValueError("condition %r: rust takes no modifiers" % name)
        if self.compiler == "plain" and self.mods:
            raise ValueError("condition %r: compiler-plain takes no modifiers (no hooks)" % name)
        # the compiler-tools conditions: query-first and check hooks always
        self.query_hook = self.compiler in ("full", "core")
        self.hook = "hook" in self.mods or self.query_hook or self.test

    def check_hook(self, flag=False):
        """The check hook in this run: +hook, +test, the compiler-tools
        conditions, or (0.15's --check-hook) the tools and both conditions."""
        return self.hook or (flag and self.base in ("tools", "both", "tools-core", "both-core"))

    def settings_key(self, flag=False):
        """(0.17) The entry of settings-eval.json's `conditions` whose hooks
        this run registers (the query-first hook apart), or None."""
        if self.test:
            return "hook+test"
        check = self.check_hook(flag)
        if self.turn_end:
            return "hook+turn-end" if check else "turn-end"
        return "hook" if check else None

    def sort_key(self):
        return (BASES.index(self.base), self.mods)

    def needs(self):
        """[(file, what)] this condition reads that does not exist yet."""
        out = []
        if self.guide == "core" and not os.path.isfile(GUIDE_CORE):
            out.append((GUIDE_CORE, "the core guide's intro (from the core-guide work)"))
        if (self.test or self.turn_end) and not os.path.isfile(SETTINGS_EVAL):
            out.append((SETTINGS_EVAL, "the eval's hook settings with tests (from the "
                        "feedback work)"))
        return out

    def __str__(self):
        return self.name


def parse(name):
    return Cond(name)


def parse_list(text):
    out = []
    for c in (text or "").split(","):
        c = c.strip()
        if c:
            out.append(Cond(c))
    return out


def lang_of(name):
    return Cond(name).lang if "+" in name or name in BASES else (
        "rust" if name == "rust" else "tach")


def is_compiler(name):
    try:
        return Cond(name).is_compiler
    except ValueError:
        return name.startswith("compiler-")


def sort_key(name):
    try:
        return Cond(name).sort_key()
    except ValueError:
        return (99, (name,))


def help_text():
    return ("BASE[+MOD...]: bases %s; modifiers +hook, +test, +turn-end, +recite, +readfirst"
            % ", ".join(BASES))
