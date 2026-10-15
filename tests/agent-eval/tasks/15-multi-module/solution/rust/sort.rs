// A stable merge sort of output rows by their ORDER BY keys.

use crate::table::{compare, Value};

// Row i's keys are keys[i * nkeys .. (i + 1) * nkeys]; desc[j] reverses
// key j.
fn compare_rows(keys: &[Value], desc: &[bool], a: usize, b: usize) -> i32 {
    let nkeys = desc.len();
    for j in 0..nkeys {
        let mut c = compare(&keys[a * nkeys + j], &keys[b * nkeys + j]);
        if desc[j] {
            c = -c;
        }
        if c != 0 {
            return c;
        }
    }
    0
}

// The rows 0..n in sorted order; equal rows keep their order.
pub fn sorted_order(keys: &[Value], desc: &[bool], n: usize) -> Vec<usize> {
    let mut order: Vec<usize> = Vec::with_capacity(n);
    for i in 0..n {
        order.push(i);
    }
    if desc.is_empty() {
        return order;
    }
    let mut tmp: Vec<usize> = vec![0; n];
    let mut width = 1;
    while width < n {
        let mut lo = 0;
        while lo < n {
            let mid = if lo + width < n { lo + width } else { n };
            let hi = if lo + 2 * width < n { lo + 2 * width } else { n };
            let mut i = lo;
            let mut j = mid;
            let mut k = lo;
            while i < mid && j < hi {
                if compare_rows(keys, desc, order[j], order[i]) < 0 {
                    tmp[k] = order[j];
                    j += 1;
                } else {
                    tmp[k] = order[i];
                    i += 1;
                }
                k += 1;
            }
            while i < mid {
                tmp[k] = order[i];
                i += 1;
                k += 1;
            }
            while j < hi {
                tmp[k] = order[j];
                j += 1;
                k += 1;
            }
            lo = hi;
        }
        for i in 0..n {
            order[i] = tmp[i];
        }
        width *= 2;
    }
    order
}
