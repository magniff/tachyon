# A new instruction for the stack machine

The workspace holds a working stack machine. It reads a program from
stdin, checks it, prints a listing if the program asks for one, runs it,
and reports how it stopped. The modules:

| file | what it holds |
|---|---|
| `main` | reading stdin, `run_program` (the order of the steps and all output), `write_op` (an instruction in a listing) |
| `op` | the enum `Op` of instructions, `mnemonic`, `cost`, `kind` (stack, arith, control or io) |
| `parse` | the program's text to a list of `Op`s: `parse`, `parse_op` |
| `verify` | the check before running: `stack_effect`, `target`, `falls_through`, `verify` |
| `vm` | the machine: `Machine`, `step`, `run` |

Add one instruction, `pick n`: it pushes a copy of the value `n` places
below the top of the stack, so `pick 0` is like `dup` and `pick 1` like
`over`. Represent it as a new variant of `Op` that carries `n` (for
example `Pick(n)`), and give it its behaviour everywhere an `Op` is
handled:

- **parse**: `pick` takes one operand, a decimal integer. Without an
  operand the error is `missing operand`, with two `extra operand` (the
  same rules and messages as `push`); an operand that is not a number
  (a label, say) is `bad number '<word>'`; a negative one is
  `bad depth '<word>'`.
- **listing**: `pick n`, like `push n`.
- **cost**: 2. **kind**: stack.
- **verify**: `pick n` needs `n + 1` values on the stack (fewer is a
  `stack underflow`) and leaves one more (more than 64 is a
  `stack overflow`); it never jumps and always falls through to the next
  instruction.
- **run**: pushes a copy of the value `n` places below the top.

Nothing else changes: programs without `pick` behave as before.

## The machine (as it is)

A program is one instruction per line. `;` starts a comment; blank lines
are skipped; `name:` alone on a line is a label for the next instruction;
a line `.list` asks for a listing. Instructions: `push n`, `pop`, `dup`,
`swap`, `over`, `add`, `sub`, `mul`, `div`, `mod`, `lt`, `eq` (these pop
b, then a, and push `a op b`; integers are 64-bit and wrap), `jmp L`,
`jz L` (pops; jumps if zero), `print` (pops and prints the value on a
line), `halt`. A jump's operand is a label or an instruction number.

The output is either `parse error on line L: MESSAGE` (the first one), or
`verify error at PC: MESSAGE`, or: the listing (if asked), every printed
value, then three lines: how the machine stopped (`halted`, `division by
zero` or `out of steps` after 100000 steps), the stack from bottom to
top, and the steps run of each kind.

Example input:

```
.list
push 10
push 20
push 30
pick 0      ; like dup
pick 2      ; the 10
add
print
pick 1
print
```

Its output:

```
0: push 10
1: push 20
2: push 30
3: pick 0
4: pick 2
5: add
6: print
7: pick 1
8: print
50
20
halted at 9 after 9 steps, cost 20
stack: 10 20 30
steps: stack 6, arith 1, control 0, io 2
```

The hidden tests cover `pick` at depths 0 to 62, its parse errors with
their line numbers, underflow and overflow found by verify (also where
two paths meet), `pick` in loops, in a program that runs out of steps, and
before a division by zero, and a long program (60,000 instructions).
