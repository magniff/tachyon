"""The prompt: a preamble per language and condition, then task.md
(conditions: lib/conds.py)."""

import os

from lib.common import PROMPTS_DIR, base_env, run_proc
from lib.conds import GUIDE_CORE, Cond

# What a dry run puts where a condition's file has not landed yet.
STUB = "(placeholder: %s does not exist yet; a hosted run refuses this condition)"


def _read(name):
    with open(os.path.join(PROMPTS_DIR, name)) as fh:
        return fh.read().strip()


def guide_text(tach_bin, which="full"):
    """`tachyonc guide` from the binary under test. which="full": the long
    core, the 0.16 control (`guide --full` where the compiler has it, 0.17;
    plain `guide` before); which="core": the short core (`tachyonc guide`
    of a compiler that has `--full`; SystemExit otherwise)."""
    env = base_env(tach_bin)
    rc, out, err, _ = run_proc(["tachyonc", "guide", "--full"], tach_bin, env, 60)
    has_full = rc == 0 and out.strip()
    if which == "full":
        if not has_full:
            rc, out, err, _ = run_proc(["tachyonc", "guide"], tach_bin, env, 60)
    else:
        if not has_full:
            raise SystemExit("guide-core: this compiler has no short core (`tachyonc guide "
                             "--full` fails, so `tachyonc guide` is the old one)")
        rc, out, err, _ = run_proc(["tachyonc", "guide"], tach_bin, env, 60)
    if rc != 0 or not out.strip():
        raise SystemExit("tachyonc guide failed: %s" % err.decode()[:400])
    return out.decode("utf-8").strip()


def guide_core_text(core=None):
    """(0.17) The core guide condition's text: the intro (prompts/
    guide-core.md, from the core-guide work) and the short core; a stub
    when either is missing (dry runs only)."""
    intro = (open(GUIDE_CORE).read().strip() if os.path.isfile(GUIDE_CORE)
             else STUB % "prompts/guide-core.md")
    return intro + "\n\n" + (core or STUB % "a compiler with the short core")


def preamble(cond, guide=None, env_note=None, check_hook=False, guide_core=None):
    c = Cond(cond) if isinstance(cond, str) else cond
    if c.lang == "rust":
        parts = [_read("rust.md")]
    else:
        parts = [_read("tach-bare.md")]
        if c.guide == "full":
            parts.append(_read("guide-intro.md") + "\n\n" + guide)
        elif c.guide == "core":
            parts.append(guide_core_text(guide_core))
        if c.pairs:
            parts.append(_read("rust-pairs.md"))
        if c.tools == "full":
            parts.append(_read("tools.md"))
        elif c.tools == "core":
            parts.append(_read("tools-core.md"))
        if c.test:
            parts.append(_read("test.md"))
        if check_hook:
            parts.append(_read("check-hook.md"))
    if env_note:  # what the backend's harness allows
        parts.append(_read(env_note))
    parts.append(_read("ending.md"))
    return "\n\n".join(parts)


def build_prompt(cond, task_text, guide=None, env_note=None, check_hook=False, guide_core=None):
    c = Cond(cond) if isinstance(cond, str) else cond
    tail = ("\n\n" + _read("recite.md")) if c.recite else ""
    return (preamble(c, guide, env_note, check_hook, guide_core) + "\n\n---\n\n"
            + task_text.strip() + tail + "\n")


def compiler_prompt(cond, task_text, agents_text, env_note=None):
    """(0.16) A compiler task's prompt: the repository, its AGENTS.md for the
    condition (lib/ctasks.agents_md), how to build and test in the copy,
    the shell note (Claude), for the compiler-tools conditions the check
    hook (and with +test the test command), the closing instructions,
    then task.md."""
    c = Cond(cond) if isinstance(cond, str) else cond
    parts = [_read("compiler-intro.md"), "<AGENTS.md>\n" + agents_text.strip() + "\n</AGENTS.md>",
             _read("compiler-env.md")]
    if c.query_hook:
        parts.append(_read("check-hook.md"))
    if c.test:
        parts.append(_read("compiler-test.md"))
    if env_note:
        parts.append(_read(env_note))
    parts.append(_read("compiler-ending.md"))
    tail = ("\n\n" + _read("recite.md")) if c.recite else ""
    return "\n\n".join(parts) + "\n\n---\n\n" + task_text.strip() + tail + "\n"
