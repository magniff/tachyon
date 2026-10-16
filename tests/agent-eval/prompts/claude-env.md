# The shell

Shell commands run without asking, inside a sandbox that allows writes
only in the current directory. The harness refuses some command lines
because of their form, not their purpose: lines with shell variables
(`$x`, `$?`), loops, heredocs, or several commands chained with `&&`,
`;` or `cd`. When that happens, do not give up and do not stop: write
files with the Write tool (a script, a test input), then run one simple
command at a time, e.g. `tachyonc main.tach -o prog`, `sh check.sh`,
`./prog < input.txt`.

Change files with the Edit tool. This is macOS: BSD `sed -i` needs an
empty suffix (`sed -i '' 's/a/b/' f`) and has no `\b`.

The program reads standard input: run it as `./prog < input.txt`; a
bare `./prog` waits for input that never comes until the command times
out.
