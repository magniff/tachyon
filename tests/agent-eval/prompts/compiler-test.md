## Testing

`target/tools/volec test FILTER...` runs `tests/run.sh FILTER...` and
prints the summary line first, then the failed cases' first lines
(`--full` for the whole table): use it instead of `tests/run.sh ... |
tail`. After an edit that checks clean, the hook also runs the tests
that name the edited module and adds their summary line.
