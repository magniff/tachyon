# The shell

Shell commands run without asking, inside a sandbox that allows writes
only in the current directory and the temporary directory. The harness
refuses some command lines because of their form, not their purpose:
lines with shell variables (`$x`, `$?`), loops, heredocs, or several
commands chained with `&&`, `;` or `cd`. When that happens, do not give
up and do not stop: write a script file with the Write tool and run it
with `sh script.sh`, or run one simple command at a time. A command
that runs longer than two minutes (the whole test suite) can be given a
longer timeout.
