# The style: volec fmt (0.25.1)

One layout, no options: `volec fmt FILE|MODULE` writes it, `--check`
lists the files not in it (exit 1), `--dry-run` shows the diff, `--all`
the tree. The edits of `edit`, `fix` and `refactor` land formatted. In
full: docs/style.md.

```text
use std::{HashMap, Vec};          // groups: std, crate, the rest; sorted, merged
use std::cli::Arg;

use crate::shapes::Point;

use super::helper;

fn main(gpa: Gpa) {
    let p = Point {
        x: 1,
        y: 2,                     // a closing bracket on its own line: a trailing comma
    };
    let t = pair(p.x, p.y);       // on one line: none (`(x,)` keeps its own)
}
```

- four spaces a level; 100 columns, a longer line broken at its loosest
  point (after `,`, before `else`, `||`, `&&`, a comparison, a chain's `.`);
- spaces around binary operators and after `,` `:`; `Vec<i64>` tight;
- at most one blank line; one around items of several lines; none
  after `{` or before `}`;
- comments kept as written; lines are never joined, only broken;
- fmt changes no token but trailing commas, and is idempotent.
