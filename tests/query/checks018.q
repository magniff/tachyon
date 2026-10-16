## The run-time checks of a function after -O2 (0.18): left, or removed
## by the range analysis (the loop bounds prove the requires).
$ checks sum
checks018/main.tach:13:14	sum	contract	removed (ranges)
checks018/main.tach:13:14	sum	contract	removed (ranges)
checks018/main.tach:6:5	sum	index	removed (ranges)
checks: 0 left, 3 removed
$ checks pick
checks018/main.tach:20:5	pick	contract	left
checks018/main.tach:20:5	pick	contract	left
checks018/main.tach:6:5	pick	index	removed (ranges)
checks: 2 left, 1 removed
