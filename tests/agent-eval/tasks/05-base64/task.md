# Base64

Encode and decode base64 (RFC 4648, standard alphabet, with padding),
one request per line.

## Input

Lines, each a request. The input may end with or without a final
newline; a final newline does not start another request. A line is:

- `enc TEXT`: encode the bytes of TEXT, which is everything after the
  first four characters `enc ` (it may be empty, contain spaces, or bytes
  >= 128). The line `enc` alone also encodes the empty text;
- `dec DATA`: decode DATA, everything after `dec ` (the line `dec` alone
  decodes the empty string);
- anything else is a bad request.

Lines contain no `\r` and no NUL bytes.

## Base64

The alphabet is `A`-`Z` (values 0-25), `a`-`z` (26-51), `0`-`9` (52-61),
`+` (62) and `/` (63). Every 3 input bytes become 4 characters; a final
group of 1 or 2 bytes becomes 2 or 3 characters followed by `==` or `=`,
so an encoding's length is always a multiple of 4.

DATA is valid when all of these hold:

- its length is a multiple of 4 (the empty string is valid and decodes to
  nothing);
- it holds only alphabet characters, except that the last one or two
  characters may be `=` (no `=` anywhere else, at most two);
- the bits that padding leaves unused are zero: the character before
  `==` has a value whose low 4 bits are 0, and the character before a
  single `=` has a value whose low 2 bits are 0 (`QQ==` is valid, `QR==`
  is not; `QUE=` is valid, `QUF=` is not).

No spaces, newlines or other characters are allowed inside DATA.

## Output

One line per request:

- for `enc`: the encoding (an empty line for empty TEXT);
- for `dec` of valid DATA whose decoded bytes are all printable ASCII
  (32 to 126): those bytes as text (an empty line when they are none);
- for `dec` of valid DATA with any other byte: `hex:` followed by the
  bytes in lowercase hexadecimal, two digits each, no spaces
  (`hex:00ff0a`);
- for invalid DATA or a bad request: `invalid`.

## Example

Input:

```
enc hello world
enc
dec aGVsbG8gd29ybGQ=
dec AP8K
dec aGVsbG8
dec QR==
ENC x
enc Ma
```

Output:

```
aGVsbG8gd29ybGQ=

hello world
hex:00ff0a
invalid
invalid
invalid
TWE=
```

## Notes

- Input is up to 1 MB; lines can be tens of thousands of bytes long.
