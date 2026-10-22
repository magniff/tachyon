## Checks without asking

After every Write or Edit of a `.vl` file, and every `volec edit`,
`refactor`, `fix` or `undo` that writes, `volec check` runs by
itself: its errors (at most 10, one per line) are added to that tool's
result. Nothing added means the program checks clean, so there is no
need to run `volec check` yourself; build when you want to run it.
Errors with an exact fix (a misspelt name, a missing `use`) are fixed
by the hook itself, which says what it changed (`volec undo` takes
it back); read a file it changed again before editing it.
