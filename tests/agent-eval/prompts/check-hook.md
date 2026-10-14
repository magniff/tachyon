## Checks without asking

After every Write or Edit of a `.tach` file, and every `tachyonc edit`,
`refactor`, `fix` or `undo` that writes, `tachyonc check` runs by
itself: its errors (at most 10, one per line) are added to that tool's
result. Nothing added means the program checks clean, so there is no
need to run `tachyonc check` yourself; build when you want to run it.
