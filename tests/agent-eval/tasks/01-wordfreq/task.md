# Word frequencies

Read a text from standard input and print its `N` most frequent words.

## Input

- The first line holds one integer `N` (0 <= N <= 100000).
- Everything after the first line is the text. It may be empty, span many
  lines and contain any bytes.

A *word* is a maximal run of ASCII letters (`A`-`Z`, `a`-`z`). Every
other byte (digits, punctuation, spaces, `_`, `'`, bytes >= 128)
separates words. Words are compared case-insensitively: convert them to
lowercase.

## Output

The words ordered by count, highest first; words with the same count in
alphabetical (byte) order. Print the first `N` of them, one per line, as
the word, one space, its count. If the text has fewer than `N` distinct
words, print all of them. Print nothing if there are no words or `N` is 0.

## Example

Input:

```
3
The cat and the hat.
THE END, and that's that!
```

Output:

```
the 3
and 2
that 2
```

(`that's` is the two words `that` and `s`; `cat`, `end`, `hat` and `s`
have count 1 and do not make the top 3.)

## Notes

- Inputs are up to 1 MB, with up to 100000 distinct words: the program
  must not be quadratic in the number of words.
- The text may end with or without a newline, and may contain blank
  lines, tabs and `\r`.
- Words can be long (thousands of letters).
