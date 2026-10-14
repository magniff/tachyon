"""The prompt: a preamble per language and condition, then task.md."""

import os

from lib.common import PROMPTS_DIR, base_env, run_proc


def _read(name):
    with open(os.path.join(PROMPTS_DIR, name)) as fh:
        return fh.read().strip()


def guide_text(tach_bin):
    """`tachyonc guide` (the core topic) from the binary under test."""
    rc, out, err, _ = run_proc(["tachyonc", "guide"], tach_bin,
                               base_env(tach_bin), 60)
    if rc != 0 or not out.strip():
        raise SystemExit("tachyonc guide failed: %s" % err.decode()[:400])
    return out.decode("utf-8").strip()


def preamble(cond, guide=None, env_note=None, check_hook=False):
    if cond == "rust":
        parts = [_read("rust.md")]
    else:
        parts = [_read("tach-bare.md")]
        if cond in ("guide", "both"):
            parts.append(_read("guide-intro.md") + "\n\n" + guide)
        if cond in ("tools", "both"):
            parts.append(_read("tools.md"))
            if check_hook:
                parts.append(_read("check-hook.md"))
    if env_note:  # what the backend's harness allows
        parts.append(_read(env_note))
    parts.append(_read("ending.md"))
    return "\n\n".join(parts)


def build_prompt(cond, task_text, guide=None, env_note=None, check_hook=False):
    return (preamble(cond, guide, env_note, check_hook) + "\n\n---\n\n"
            + task_text.strip() + "\n")
