# The shell

Shell commands run without asking, inside a sandbox that allows writes
only in the current directory. A command line that uses shell variables
(`$x`, `for f in ...; do ... $f ...`) is refused by the harness: put such
logic in a script file in the current directory and run it with
`sh script.sh`.
