## A program the lexer cannot read (unlexed/): nothing to answer with,
## and the first error.
$ def main
error query.program-errors: 1 error in the program; nothing to answer with; first: unlexed/main.vl:3:27: error[tokenizer error] newline in string literal
try: volec --diagnostics=short unlexed/main.vl -c -o /dev/null
[exit 1]
