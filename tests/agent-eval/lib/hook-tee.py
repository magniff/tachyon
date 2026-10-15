"""(0.17, agent eval) Runs a hook script and logs what it told the agent.

    python3 -I hook-tee.py SCRIPT [ARGS...]
    python3 -I hook-tee.py --sh 'COMMAND LINE'     (a hook given as a shell line)

Claude Code's stream-json does not carry a hook's `additionalContext` or
its blocking message, so the transcript does not show the errors the check
hook reported or the query the query-first hook suggested. This wrapper
passes the event (stdin) to the real hook unchanged, passes its stdout,
stderr and exit status back unchanged, and appends one JSON line to
$EVAL_HOOK_OUTPUT_LOG: the hook, the event, the tool, the command or file,
the exit status and the text it returned (lib/anatomy.py reads it: error
messages by class, blocks and the suggestions followed)."""

import json
import os
import subprocess
import sys
import time


def main():
    if len(sys.argv) < 2:
        return 0
    data = sys.stdin.buffer.read()
    t0 = time.time()
    if sys.argv[1] == "--sh" and len(sys.argv) > 2:
        line = sys.argv[2]
        script = next((w for w in line.split() if w.strip("'\"").endswith(".py")), line)
        script = script.strip("'\"")
        p = subprocess.run(["/bin/sh", "-c", line], input=data, capture_output=True)
    else:
        script, args = sys.argv[1], sys.argv[2:]
        p = subprocess.run([sys.executable, "-I", script] + args, input=data,
                           capture_output=True)
    ms = int((time.time() - t0) * 1000)
    log = os.environ.get("EVAL_HOOK_OUTPUT_LOG")
    if log and (p.stdout.strip() or p.stderr.strip() or p.returncode):
        try:
            ev = json.loads(data or b"{}")
        except ValueError:
            ev = {}
        ti = ev.get("tool_input") or {}
        rec = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "ms": ms,
               "hook": os.path.basename(script), "event": ev.get("hook_event_name"),
               "tool": ev.get("tool_name"), "tool_use_id": ev.get("tool_use_id"),
               "input": (ti.get("command") or ti.get("file_path") or "")[:400],
               "exit": p.returncode,
               "stdout": p.stdout.decode("utf-8", "replace")[:6000],
               "stderr": p.stderr.decode("utf-8", "replace")[:3000]}
        try:
            with open(log, "a") as fh:
                fh.write(json.dumps(rec) + "\n")
        except OSError:
            pass
    sys.stdout.buffer.write(p.stdout)
    sys.stdout.flush()
    sys.stderr.buffer.write(p.stderr)
    sys.stderr.flush()
    return p.returncode


if __name__ == "__main__":
    sys.exit(main())
