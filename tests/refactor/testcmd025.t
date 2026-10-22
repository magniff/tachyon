## (0.25) a contract whose requires the smallest values rarely meet:
## -O0 runs the first 20 cases, which discard more than -O2's 100 do;
## the discards are judged at -O2, not compared (no DIFF). A #[property]
## takes the test's allocator, `gpa: Gpa`, which is not generated.
$ test
test main.vl: 2 passed (1 #[property], 1 contract; -O0 and -O2 agree)
## `volec check` reports a test's signature as `volec test` does
$ check bad.vl
bad.vl:2:4: error[test.signature] 'takes' is a #[test] with parameters: a #[test] takes nothing or `gpa: Gpa` | help: a function of generated arguments is a #[property]
[exit 1]
