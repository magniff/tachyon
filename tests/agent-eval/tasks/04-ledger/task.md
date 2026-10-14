# Bank ledger

Process a list of bank commands on named accounts, one per line, and
print errors, balances and reports.

## Input

One command per line. Tokens are separated by one or more spaces; a line
may start or end with spaces. Blank lines (empty or only spaces) are
ignored. The input may end with or without a final newline. The commands:

| command | effect |
|---|---|
| `open NAME` | opens an account with balance 0 |
| `deposit NAME AMOUNT` | adds AMOUNT to the balance |
| `withdraw NAME AMOUNT` | takes AMOUNT from the balance |
| `transfer FROM TO AMOUNT` | moves AMOUNT from account FROM to account TO |
| `close NAME` | closes the account; its name can be opened again later, as a new account |
| `balance NAME` | prints `NAME BALANCE TXNS` |
| `report` | prints the report (below) |

- NAME is 1 to 16 characters, each a lowercase letter `a`-`z`, a digit or
  `_`.
- AMOUNT is 1 to 12 decimal digits and is not zero (`007` is 7).
- TXNS of an account is the number of successful `deposit`, `withdraw`
  and `transfer` commands that changed it since it was opened (a
  transfer counts for both accounts).

## Errors

A command that fails prints one line and changes nothing. Check in this
order and print the first that applies:

1. `error: bad command`: the first token is not one of the commands
   above (they are lowercase), or the number of arguments is wrong;
2. `error: bad name`: a NAME is not valid;
3. `error: bad amount`: the AMOUNT is not valid;
4. `error: account exists` (`open` of an open account), or
   `error: no such account` (any other command naming an account that is
   not open; for `transfer`, FROM is checked before TO);
5. `error: same account`: `transfer` with FROM equal to TO;
6. `error: insufficient funds`: `withdraw` or `transfer` of more than the
   balance (the balance never goes below 0);
7. `error: balance not zero`: `close` of an account whose balance is not 0.

Successful `open`, `deposit`, `withdraw`, `transfer` and `close` print
nothing.

## Report

`report` prints a header line `accounts: K, total: T`, where K is the
number of open accounts and T the sum of their balances, then one line
`NAME BALANCE TXNS` per open account, sorted by name (byte order: `_`
sorts before `a`, digits before `_`).

## Example

Input:

```
open alice
open bob
deposit alice 100
transfer alice bob 30
withdraw bob 50
open alice
deposit carol 5
deposit bob 0
Transfer alice bob 1
balance bob
close alice
report
```

Output:

```
error: insufficient funds
error: account exists
error: no such account
error: bad amount
error: bad command
bob 30 1
error: balance not zero
accounts: 2, total: 100
alice 70 2
bob 30 1
```

## Notes

- Up to 100000 commands and tens of thousands of accounts: look accounts
  up by name in a hash map (or something equally fast), not by scanning.
- Balances stay below 10^17, so they fit in a signed 64-bit integer.
- Lines contain only printable ASCII and spaces.
