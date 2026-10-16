## Reading source

Shell reads of large `.tach` files are answered with the matching query
(`sed -n`, `head`, `tail`: `tachyonc query text`; `cat`: `tachyonc query
items`; `grep`: `tachyonc query refs` or `tachyonc query grep`), each
command of a line on its own; the result says what ran.
