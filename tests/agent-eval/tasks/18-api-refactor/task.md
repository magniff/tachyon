# Change an API across modules: the warehouse robot

The workspace holds a working program of about 700 lines: a warehouse
robot. It reads a map and then commands from stdin, moves the robot
around the map (pushing boxes, taking teleporters) and prints what the
commands ask for. It is split into modules:

| file | what it holds |
|---|---|
| `main` | reading the input, splitting it into lines, `parse_num`, and `run_commands`, one long function that splits each command line into words, checks its arguments and carries it out |
| `level` | the struct `Level` (the map's tiles, the robot's start, boxes, goals, teleporters), the error codes `ERR_...`, and `load_level`, which fills a `Level` from the map's lines and returns 0 or an error code, leaving the details of an error in the level's fields `error_at`, `error_tile` and `error_num` |
| `grid` | positions: `step`, `in_bounds`, `cell_index`, `tile_at`, `partner` (a teleporter's pair), `push_pos` (a position as text) |
| `world` | `World` (the robot, the boxes, marks, the undo history, counters), `Step` (one undoable step), and `distance` (a breadth-first search) |
| `report` | the text of a load error, the level summary, the status line, the map |

A position is a tuple `(i64, i64)`, (row, column), everywhere: in
fields, parameters, results, vectors of positions and literals.

The program is correct. Refactor it without changing its behaviour:

1. **A position type.** Define `struct Pos` with two fields, `row: i64`
   and `col: i64`, in `grid`, and use it for every position in every
   module, instead of `(i64, i64)`: struct fields, parameters, results,
   the vectors of positions, and where positions are built (`(r, c)`)
   or taken apart (`p.0`, `p.1`, `let (r, c) = p`). Give it whatever
   helpers you like (a constructor, equality).
2. **Split `run_commands`.** It is about 300 lines. Split it into three
   new functions, all three named exactly so:
   - `parse_command`: turns one line into a command (a value of a type
     you design, such as an enum), or the reason it is bad (a blank or
     comment line, bad arguments, a bad count, a bad position, an
     unknown command);
   - `apply_move`: carries out the commands that move the robot or the
     boxes (`N`, `S`, `E`, `W`, `UNDO`, `RESET`, `GOTO`);
   - `apply_query`: carries out the others (`WHERE`, `BOXES`, `MARK`,
     `MARKS`, `DIST`, `HISTORY`, `SHOW`, `STATUS`).

   `run_commands` stays in `main`, calls all three, and is at most 80
   lines long; none of the four functions is longer than 120 lines.
   (Lines are counted from the line of `fn NAME` to the line holding
   only its closing brace, at the same indentation as the `fn` line.)
3. **Errors as a type.** Replace the error codes with an enum
   `LoadError` in `level`, with exactly these variants (their fields are
   yours to choose: each must carry what its message needs):
   `EmptyMap`, `NoSeparator`, `RaggedRow`, `UnknownTile`, `NoRobot`,
   `SecondRobot`, `OddTeleporters`. `load_level` takes only the lines
   and returns `Result<Level, LoadError>`; the out-parameter (`dest`),
   the fields `error_at`, `error_tile`, `error_num` and the `ERR_...`
   constants are gone. `report` prints a `LoadError`.

Rules, checked after you finish:

- `(i64, i64)` does not appear anywhere in the source (spaces do not
  matter); `struct Pos` has the fields `row: i64` and `col: i64`;
  `grid`, `level` and `world` use `Pos`.
- The functions of step 2 exist with those names and lengths, and
  `run_commands` calls `parse_command`, `apply_move` and `apply_query`.
- `enum LoadError` has the seven variants; `fn load_level(...)` returns
  `Result<Level, LoadError>` and has no `Level` parameter; the words
  `dest`, `error_at`, `error_tile`, `error_num` and any `ERR_` name
  appear nowhere in the source.
- The modules `main`, `grid`, `level`, `world` and `report` still exist
  (you may add more).
- Output is byte for byte what it was: the hidden tests run the program
  on many inputs and compare with the original program's output.

## What the program does (for reference; do not change it)

The input is a map, a line `---`, then commands, one per line. Lines may
end in `\r\n`. Line numbers in messages count every line of the input
from 1. Positions are printed `row,col`, both from 0, row 0 at the top.

Map tiles: `#` wall, `.` floor, `@` the robot, `$` a box, `G` a goal,
`*` a box on a goal, `T` a teleporter. Outside the map is wall. The
teleporters pair up in reading order (the first with the second, the
third with the fourth, ...). Loading fails, printing one line and
nothing else, when there is no `---` line (`error: no '---' line after
the map`), no map lines or an empty first line (`error: the map is
empty`), a row of another length than the first (`error: row 2 has
length 6, expected 5`), any other character (`error: unknown tile 'x'
at 2,3`), a second robot (`error: second robot at 2,4`), no robot
(`error: no robot on the map`), or an odd number of teleporters
(`error: 3 teleporters, expected an even number`), checked in that
order, row by row and left to right. Otherwise it prints `level WxH, B
boxes, G goals, T teleporters`, runs the commands, then prints `final:`
and the status line.

Commands are words separated by runs of spaces. A blank line, or one
whose first word starts with `#`, is skipped. A count is 1 to 9 digits
and at least 1; a row or column is 1 to 9 digits.

- `N`, `S`, `E`, `W` with an optional count (default 1): up to that many
  steps. A step into a wall, or pushing a box into a wall or another
  box, is blocked and ends the command, printing `line L: blocked after
  D of K at r,c`. A box in the way is pushed one cell. A robot that
  steps onto a teleporter moves on to its pair unless a box is there.
- `UNDO` with an optional count: takes back up to that many steps
  (robot and pushed box); `line L: nothing to undo` if there are none.
- `RESET`: back to the start; no marks, no history, counters 0.
- `WHERE`: `robot at r,c`. `BOXES`: the boxes sorted by row then column,
  `boxes: r,c r,c` (`boxes: none`).
- `MARK`: remembers the robot's place, `mark K at r,c`. `MARKS`:
  `marks: 1=r,c 2=r,c` (`marks: none`).
- `DIST r c`: the fewest steps from the robot to there without pushing
  boxes, teleporters included, `dist r,c: D` or `dist r,c: unreachable`.
- `GOTO k`: walks to mark k by a shortest path: `goto k: D moves`, or
  `goto k: unreachable`, or `line L: no mark k`. The history is cleared.
- `HISTORY`: `history N`, the undoable steps. `SHOW`: the map, with `@`,
  `$` and `*`. `STATUS`: `moves M, pushes P, boxes on goals B/N`, and
  ` (solved)` when there are boxes and all are on goals.
- Errors: `line L: bad arguments` (a wrong number of words, or a GOTO
  argument that is not a number), `line L: bad count`, `line L: bad
  position` (DIST outside the map or not numbers), `line L: unknown
  command 'X'`.

Example input:

```
#######
#@.$.G#
#.T#T.#
#..*..#
#######
---
WHERE
E 3
STATUS
SHOW
W
S
MARK
N 2
UNDO 2
BOXES
DIST 3 5
GOTO 1
GOTO 4
MARKS
FOO bar
E x
```

Its output:

```
level 7x5, 2 boxes, 2 goals, 2 teleporters
robot at 1,1
moves 3, pushes 2, boxes on goals 2/2 (solved)
#######
#...@*#
#.T#T.#
#..*..#
#######
line 12: blocked after 0 of 1 at 1,3
mark 1 at 1,3
line 14: blocked after 0 of 2 at 1,3
boxes: 1,4 3,3
dist 3,5: 4
goto 1: 0 moves
line 19: no mark 4
marks: 1=1,3
line 21: unknown command 'FOO'
line 22: bad count
final: moves 2, pushes 1, boxes on goals 1/2
```

The hidden tests cover every load error, every command and its error
messages, comments, blank lines, runs of spaces, `\r\n` line ends, and
large inputs (25,000 commands on a 60x60 map).
