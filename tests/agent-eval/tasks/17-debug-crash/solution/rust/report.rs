// The report printed after the last line of input.

use crate::stats::ranking;
use crate::text::{push_grouped, push_int, wrap};
use crate::State;

pub fn write_report(st: &State, out: &mut Vec<u8>) {
    out.extend_from_slice(b"events ");
    push_int(out, st.events);
    out.extend_from_slice(b", keys ");
    push_int(out, st.table.len());
    out.extend_from_slice(b", bad ");
    push_int(out, st.bad);
    out.push(b'\n');

    let mut quiet: Vec<&[u8]> = Vec::new();
    for g in &st.groups {
        out.extend_from_slice(&g.key);
        out.extend_from_slice(b": count ");
        push_int(out, g.count);
        out.extend_from_slice(b", sum ");
        push_grouped(out, g.sum);
        out.extend_from_slice(b", min ");
        push_int(out, g.min);
        out.extend_from_slice(b", max ");
        push_int(out, g.max);
        out.extend_from_slice(b", mean ");
        push_int(out, g.mean());
        out.push(b'\n');

        let b = g.busiest(st.span);
        out.extend_from_slice(b"  busiest ");
        push_int(out, b.count);
        out.extend_from_slice(b" in [");
        push_int(out, b.start);
        out.extend_from_slice(b", ");
        push_int(out, b.start + st.span);
        out.extend_from_slice(b")\n");

        match g.recent(st.now, st.span) {
            Some(r) => {
                out.extend_from_slice(b"  recent ");
                push_int(out, r.n);
                out.extend_from_slice(b": min ");
                push_int(out, r.min);
                out.extend_from_slice(b", median ");
                push_int(out, r.median);
                out.extend_from_slice(b", max ");
                push_int(out, r.max);
                out.push(b'\n');
            }
            None => {
                out.extend_from_slice(b"  recent none\n");
                quiet.push(&g.key);
            }
        }
    }

    write_top(st, out);

    if !quiet.is_empty() {
        out.extend_from_slice(b"quiet:\n");
        wrap(&quiet, st.width, out);
    }
    if !st.notes.is_empty() {
        let mut notes: Vec<&[u8]> = Vec::new();
        for n in &st.notes {
            notes.push(n);
        }
        out.extend_from_slice(b"notes:\n");
        wrap(&notes, st.width, out);
    }
}

// The `top` groups with the largest sums.
fn write_top(st: &State, out: &mut Vec<u8>) {
    if st.top == 0 || st.groups.is_empty() {
        return;
    }
    let order = ranking(&st.groups);
    let k = if st.top < order.len() as i64 { st.top } else { order.len() as i64 };
    out.extend_from_slice(b"top ");
    push_int(out, k);
    out.extend_from_slice(b" by sum:\n");
    for rank in 0..k {
        let g = &st.groups[order[rank as usize] as usize];
        out.extend_from_slice(b"  ");
        push_int(out, rank + 1);
        out.extend_from_slice(b". ");
        out.extend_from_slice(&g.key);
        out.push(b' ');
        push_grouped(out, g.sum);
        out.push(b'\n');
    }
}
