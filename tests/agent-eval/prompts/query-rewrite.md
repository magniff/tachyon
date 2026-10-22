## Reading source

Shell reads of large `.vl` files are answered with the matching query
(`sed -n`, `head`, `tail`: `volec query text`; `cat`: `volec query
items`; `grep`: `volec query refs` or `volec query grep`), each
command of a line on its own; the result says what ran.
