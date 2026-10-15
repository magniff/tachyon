# Port a C program: LZSS

The workspace holds `reference.c`, a small LZSS compressor and
decompressor written in C (about 400 lines with comments). **Port it**:
write a program, `main` at the root of the workspace (other modules next
to it if you like), that behaves exactly like `reference.c`: for every
input, the same output, byte for byte, and exit status 0.

The port must stand on its own: it must not use, include, link or call
the C file or any C code built from it, and it must still build and work
with `reference.c` deleted (this is checked). Calling the C standard
library for input and output is fine.

`reference.c` is the specification: where this text and the C program
seem to differ, the C program is right. The summary below is to help you
read it.

## What the program does

It reads all of stdin. The first line, up to the first `\n` (a `\r`
before that `\n` is dropped), is the mode: exactly `compress` or
`decompress` (case-sensitive; anything else prints
`error: unknown mode`). Everything after that first `\n`, byte for byte,
is the input; with no `\n` at all the input is empty.

- `compress`: the input is raw data (any bytes). Output: one stats line,

  ```
  compressed N -> M bytes (L literals, K matches), crc32 XXXXXXXX
  ```

  (N the data's length, M the stream's length, the counts of the two
  kinds of token, the data's CRC-32 in 8 lowercase hex digits), then the
  stream in lowercase hex, 32 bytes (64 digits) per line, the last line
  possibly shorter.
- `decompress`: the input is a stream in hex (upper or lower case);
  spaces, tabs, `\r` and `\n` anywhere are ignored. Output: one line
  `decompressed M -> N bytes, crc32 XXXXXXXX`, then the data itself,
  raw.

Every problem prints exactly one line instead (and nothing else), in the
order the C program checks them: `error: bad hex character at offset I`
(I counts bytes of the input, after the mode line), `error: odd number
of hex digits`, `error: truncated header`, `error: bad magic`,
`error: truncated stream at byte P`, `error: bad distance D at byte P`,
`error: match overruns the data at byte P`, `error: T trailing bytes`,
`error: crc mismatch: stored XXXXXXXX, computed YYYYYYYY` (P is a 0-based
position in the decoded stream).

## The stream

- Bytes 0-1: `L` `Z`; byte 2: version 1; bytes 3-6: the data's length;
  bytes 7-10: its CRC-32 (zlib's: reflected, polynomial `0xEDB88320`);
  both 32-bit little-endian.
- Then groups of up to 8 tokens, each led by a flag byte whose bit i
  (least significant first) says whether token i of the group is a
  literal (0: one byte, copied to the output) or a match (1: two bytes
  `b0 b1`; distance - 1 = `b0 | (b1 >> 4) << 8`, length - 3 = `b1 & 15`;
  copy `length` bytes starting `distance` bytes back in the output, byte
  by byte, so a copy may overlap what it writes). Distances are 1 to
  4096, lengths 3 to 18.

The compressor's choices are what make the output exact: hash chains
over 3-byte prefixes (a 13-bit multiplicative hash with 32-bit wrapping
arithmetic), at most 64 candidates per position, newest first, a
candidate kept only when strictly longer than the best so far (so the
nearest wins ties), and one step of lazy matching (a match is not taken
if the match at the next position is strictly longer). Read
`find_match`, `insert` and `compress` closely.

## Example

Input:

```
compress
abracadabra abracadabra abracadabra
```

Output:

```
compressed 36 -> 28 bytes (9 literals, 3 matches), crc32 469f40d7
4c5a0124000000d7409f468061627261636164060106200b0f0b020a
```

Input:

```
decompress
4c5a0124000000d7409f468061627261636164060106200b0f0b020a
```

Output:

```
decompressed 28 -> 36 bytes, crc32 469f40d7
abracadabra abracadabra abracadabra
```

## Edge cases the tests cover

- empty data (a mode line with no `\n`, ending in `\r`), an unknown mode;
- long runs of one byte and of short patterns (overlapping matches, the
  18-byte limit, the lazy step), matches at distances 4095, 4096 and
  4097, data much longer than the window;
- bytes of every value (including 0, `\r` and 0x80-0xff), in the data
  and in decompressed output;
- a 400 KB compress and a 600 KB (of hex) decompress (each test has a
  time limit of a few seconds; the C program takes milliseconds);
- decompressing upper-case hex broken over lines with spaces and tabs,
  and streams with a bad hex character, a bad distance, a truncated
  match, a wrong CRC, trailing bytes, and a match running past the
  stored length.
