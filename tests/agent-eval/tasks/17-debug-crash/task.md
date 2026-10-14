# Fix the event aggregator

The workspace holds an event log aggregator of about 700 lines, split
into five files:

| file | what it holds |
|---|---|
| `main` | reading stdin line by line, the settings, accepting or rejecting each line, the `State` |
| `table` | a hash table from keys to group numbers (open addressing) |
| `stats` | `Group`, the events of one key, and what is computed from them: mean, busiest window, recent window, median, the ranking |
| `report` | the report printed at the end |
| `text` | splitting lines into words, reading integers, digit groups, wrapping words to a width |

It builds and works on most inputs, but **on some inputs it crashes,
prints wrong output, or never finishes.** The hidden tests check the
behaviour described below; find and fix what is wrong. Keep the
program's structure and output format: change what is wrong, not the
design. A fix must not make the program slow: the hidden tests include
inputs of close to 1 MB with over ten thousand keys, and each test has a
time limit of a few seconds.

## Input (stdin)

One item per line. A line may end in `\r\n`. Words are separated by runs
of spaces and tabs; leading and trailing spaces and tabs are ignored.

- A line with no words is skipped, and so is a line whose first word
  starts with `#` (a comment).
- `SPAN n`: the length of the windows below (default 60), n at least 1.
- `WIDTH n`: the width for wrapping text (default 40), n at least 1.
- `TOP n`: how many keys the ranking shows (default 0: no ranking), n at
  least 0.
- `NOTE word...`: its words (all after `NOTE`, possibly none) are added
  to the notes, in order.
- `TIME KEY VALUE`: an event. TIME is at least 0 and not smaller than
  the time of the last accepted event; KEY is any word (bytes, case
  sensitive; two keys are the same key only when they are the same
  bytes); VALUE may be negative.

A setting may appear anywhere; the last valid one of each kind is the
one used, since the report is computed at the end.

An integer is an optional `-` followed by 1 to 18 decimal digits and
nothing else (`+5`, `--5`, `5x`, `-` are not integers; `000123` is 123).
In the tests, values are between -10^9 and 10^9.

A line is **bad** (counted, otherwise ignored) when:

- it is `SPAN`, `WIDTH` or `TOP` without exactly one more word, or that
  word is not an integer, or it is out of range (below 1, or below 0 for
  `TOP`);
- it is anything else (not `NOTE`, not a comment) without exactly three
  words, or its TIME or VALUE is not an integer, or TIME is negative or
  smaller than the time of the last accepted event. Keywords are upper
  case: `span 5` is a bad event line.

## The report

Let `now` be the time of the last accepted event (0 when there is none).
The report has, in order:

1. `events E, keys K, bad B`: accepted events, distinct keys, bad lines.
2. For each key, in the order of its first accepted event:
   - `KEY: count C, sum S, min A, max Z, mean M`: over all its events;
     S is written with digit groups (`1,234,567`, `-1,234`, `999`), the
     other numbers plainly; M is S / C truncated toward zero.
   - `  busiest N in [T, U)`: of the windows `[t, t + SPAN)` with `t`
     the time of one of the key's events, the one holding the most of
     its events; on a tie the earliest `t`. U is T + SPAN.
   - `  recent N: min A, median D, max Z`: over its events with a time
     greater than `now - SPAN`. The median of an even number of values is
     the mean of the two middle ones, truncated toward zero. When the key
     has no such event, the line is `  recent none` instead, and the key
     is **quiet**.
3. Only when TOP is at least 1 and there is a key: `top N by sum:`, N the
   smaller of TOP and the number of keys, then the N keys with the
   largest sums, `  R. KEY S` (R from 1, S with digit groups); keys with
   equal sums in the order of their first accepted event.
4. Only when some key is quiet: `quiet:`, then the quiet keys (in the
   order of step 2) wrapped as below.
5. Only when there is a note word: `notes:`, then all note words wrapped.

Wrapping a list of words to WIDTH: each line is two spaces followed by
words joined by single spaces; a line takes as many of the next words as
fit in WIDTH bytes (the two leading spaces do not count); a word longer
than WIDTH is put alone on a line of its own, unbroken.

## Examples

Input:

```
# requests per service
SPAN 30
TOP 2
10 api 120
12 db 7
15 api 80
20 api 1500
21 db 13
41 db 3
40 api 9
55 api -40
62 db 2000000
NOTE disk near full on db
```

Output (`40 api 9` is bad: 40 is before 41):

```
events 8, keys 2, bad 1
api: count 4, sum 1,660, min -40, max 1500, mean 415
  busiest 3 in [10, 40)
  recent 1: min -40, median -40, max -40
db: count 4, sum 2,000,023, min 3, max 2000000, mean 500005
  busiest 3 in [12, 42)
  recent 2: min 3, median 1000001, max 2000000
top 2 by sum:
  1. db 2,000,023
  2. api 1,660
notes:
  disk near full on db
```

Input:

```
SPAN 10
WIDTH 16
5 old 1
6 old 2
30 new 5
31 new 6
40 new 7
NOTE the old key went quiet
```

Output:

```
events 5, keys 2, bad 0
old: count 2, sum 3, min 1, max 2, mean 1
  busiest 2 in [5, 15)
  recent none
new: count 3, sum 18, min 5, max 7, mean 6
  busiest 2 in [30, 40)
  recent 2: min 6, median 6, max 7
quiet:
  old
notes:
  the old key went
  quiet
```

The hidden tests cover every kind of bad line, comments, blank lines,
tabs and `\r\n`, settings given late or more than once, ties in the
ranking and TOP larger than the number of keys, SPAN 1, equal times,
even counts and negative medians, quiet keys, many distinct keys of the
same length, words and
keys longer than the width (WIDTH 1 included) and words exactly as long
as it, and two large inputs (thousands of keys, tens of thousands of
events).
