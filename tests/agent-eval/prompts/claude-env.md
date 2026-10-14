# The shell

Shell commands run without asking, inside a sandbox that allows writes
only in the current directory. The harness refuses some command lines
because of their form, not their purpose: lines with shell variables
(`$x`, `$?`), loops, heredocs, or several commands chained with `&&`,
`;` or `cd`. When that happens, do not give up and do not stop: write
files with the Write tool (a script, a test input), then run one simple
command at a time, e.g. `tachyonc main.tach -o prog`, `sh check.sh`,
`./prog < input.txt`.
