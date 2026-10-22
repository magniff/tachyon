# Merge conflicts

`units` prints tables of everyday conversions (temperatures, distances,
weights), from `convert.vl`. Two branches change it at once:
`rounding` makes every conversion round to the nearest whole number and
adds pounds to kilograms; `main` names the metres in a mile and adds
miles to kilometres. `make-conflict.sh` makes both branches (with
`volec edit`, as an agent on each would) and merges them.

A file with conflict markers does not parse, so the usual queries and
edits cannot read the program. `query conflicts` and `edit resolve` read
the files as text: they list the regions with the items they fall in,
show each side, and resolve a region by name or line, journaled like any
edit. Every command below is run by `tests/walkthrough/run.sh` on a
fresh copy of this directory, and its output is checked against this
file.

## The merge

```console
$ sh make-conflict.sh
Auto-merging convert.vl
CONFLICT (content): Merge conflict in convert.vl
Auto-merging main.vl
CONFLICT (content): Merge conflict in main.vl
Automatic merge failed; fix conflicts and then commit the result.
[exit 1]
$ volec check 2>&1 | head -3
main.vl:5:1: error[parser error] expected an item ('fn', 'extern', 'struct', 'union', 'enum', 'impl', 'const', 'static' or 'type'), got '<<'
main.vl:7:1: error[parser error] expected an item ('fn', 'extern', 'struct', 'union', 'enum', 'impl', 'const', 'static' or 'type'), got '=='
main.vl:8:15: error[type error] 'c_to_f' is imported twice
```

Thirteen errors, every one caused by the markers. Nothing that reads the
program by name works until they are gone.

## 1. Where the conflicts are

One line per region: its lines, the items it touches (found from the
text), and each side's size and branch:

```console
$ volec query conflicts
convert.vl:22-31	mi_to_km	ours 6 lines (HEAD)	theirs 1 line (rounding)
main.vl:5-9	use	ours 1 line (HEAD)	theirs 1 line (rounding)
main.vl:24-32	main	ours 3 lines (HEAD)	theirs 3 lines (rounding)
```

`--show` prints the sides of a region (here every region of
`main.vl`):

```console
$ volec query conflicts main.vl --show
// main.vl:5-9	use
// ours (HEAD), line 6:
use convert::{c_to_f, f_to_c, kg_to_lb, km_to_mi, mi_to_km};
// theirs (rounding), line 8:
use convert::{c_to_f, f_to_c, kg_to_lb, km_to_mi, lb_to_kg};
// main.vl:24-32	main
// ours (HEAD), lines 25-27:
    println("miles  km");
    for mi in [1, 26, 100] {
        println(f"{mi:>5}  {mi_to_km(mi):>3}");
// theirs (rounding), lines 29-31:
    println("pounds  kg");
    for lb in [1, 100, 150] {
        println(f"{lb:>6}  {lb_to_kg(lb):>2}");
```

## 2. Resolve by name

The `use` lines: each side added one name. Keep ours; the name theirs
added comes back by itself below, once the code that uses it is in:

```console
$ volec edit resolve use --ours
resolved main.vl:5-9 (ours)	main.vl	+0 -4 lines
note conflict.left: 2 conflict regions left in 2 files
try: volec query conflicts
```

The body of `main`: each side added a table at the same place. Git
shares the closing `}` of the two loops, so `--both` (ours, then
theirs) would leave the first loop unclosed. The region's new text can
be given on stdin instead:

```console
$ volec edit resolve main --show <<'EOF'
>     println("miles  km");
>     for mi in [1, 26, 100] {
>         println(f"{mi:>5}  {mi_to_km(mi):>3}");
>     }
>     println("pounds  kg");
>     for lb in [1, 100, 150] {
>         println(f"{lb:>6}  {lb_to_kg(lb):>2}");
> EOF
resolved main.vl:20-28 (text)	main.vl	+1 -3 lines
// main.vl:20-26
20	    println("miles  km");
21	    for mi in [1, 26, 100] {
22	        println(f"{mi:>5}  {mi_to_km(mi):>3}");
23	    }
24	    println("pounds  kg");
25	    for lb in [1, 100, 150] {
26	        println(f"{lb:>6}  {lb_to_kg(lb):>2}");
note conflict.left: 1 conflict region left in 1 file
try: volec query conflicts
```

The last region is in `convert.vl`, around `km_to_mi` and the new
`mi_to_km`. Ours has the named constant and the new function; theirs
has the rounding. Take ours:

```console
$ volec edit resolve mi_to_km --ours
resolved convert.vl:22-31 (ours)	convert.vl	+0 -4 lines
main.vl:26:29: error[type error] undefined variable 'lb_to_kg' | help: add `use crate::convert::lb_to_kg;` | try: volec fix --suggested main.vl
warning conflict.check: the resolved program has errors (written; the merge may need more than one side)
try: volec check
```

With the last region resolved, `edit resolve` checks the program and
prints what is left: the import ours did not have.

## 3. Finish the merge with the ordinary tools

The program parses again, so everything works on it again. `fix` adds
the import; one `edit patch` with two targets puts theirs' rounding
into both functions, written with ours' constant:

```console
$ volec fix --only imports --show
fixed 1 missing import	main.vl	+1 -1 lines
// main.vl:5
5	use convert::{c_to_f, f_to_c, kg_to_lb, km_to_mi, lb_to_kg, mi_to_km};
$ volec edit patch km_to_mi --old 'km * 1000 / METRES_PER_MILE' --new 'round_div(km * 1000, METRES_PER_MILE)' --in mi_to_km --old 'mi * METRES_PER_MILE / 1000' --new 'round_div(mi * METRES_PER_MILE, 1000)' --show
patched crate::convert::mi_to_km, crate::convert::km_to_mi	convert.vl	+2 -2 lines
// convert.vl:22
22	    round_div(km * 1000, METRES_PER_MILE)
// convert.vl:27
27	    round_div(mi * METRES_PER_MILE, 1000)
$ volec check && volec main.vl -o units && ./units | tail -14
 42     26
100     62
miles  km
    1    2
   26   42
  100  161
pounds  kg
     1   0
   100  45
   150  68
kg  pounds
 1       2
50     110
70     154
ok: 0 errors in main.vl
ok: built units
$ git commit -q -a -m 'Merge rounding' && git log --format=%s
Merge rounding
Miles to kilometres
Round every conversion to the nearest whole number
start
```

## Why not by hand

- Conflict markers make the file unreadable to the compiler, and a
  search for `<<<<<<<` gives line numbers, not meaning. `query conflicts`
  says which items each region touches, which is the question that
  decides how to resolve it.
- Each resolution named its region by item (`use`, `main`, `mi_to_km`)
  and was journaled: a wrong choice is one `undo` away, which an editor
  session on a conflicted file does not give.
- The last resolution checked the program and named the one error left,
  with its fix; `fix` and `edit patch` did the rest, by name, checked.
