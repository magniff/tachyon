# Fix: the largest integer

The program in this directory reads integers from standard input, one
per line, and prints the largest of them followed by a newline. It
builds, but users report wrong answers for some inputs. Find the bug and
fix it; keep the program's structure (the functions `read_all`,
`parse_numbers` and `largest`).

- Each non-blank line holds one decimal integer, possibly negative, with
  no other characters; blank lines are ignored.
- There is at least one integer; there can be up to 100 000.

Example input:

```
5
1
9
```

Output:

```
9
```
