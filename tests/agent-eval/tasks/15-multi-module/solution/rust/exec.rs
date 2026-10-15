// Runs a checked query: filters the rows, groups and aggregates them,
// orders, limits and prints the result.

use std::collections::HashMap;

use crate::check::{Arg, Cond, Expr, Plan};
use crate::parser::{AggKind, CmpOp};
use crate::sort::sorted_order;
use crate::table::{compare, is_null, Table, Value};

fn arg_value(t: &Table, row: usize, a: &Arg) -> Value {
    match a {
        Arg::Col(c) => t.cell(row, *c).clone(),
        Arg::Lit(v) => v.clone(),
    }
}

// Whether condition node i holds for the row.
fn holds(p: &Plan, t: &Table, i: usize, row: usize) -> bool {
    match &p.conds[i] {
        Cond::Or(a, b) => holds(p, t, *a, row) || holds(p, t, *b, row),
        Cond::And(a, b) => holds(p, t, *a, row) && holds(p, t, *b, row),
        Cond::Not(a) => !holds(p, t, *a, row),
        Cond::IsNull(a, negated) => is_null(&arg_value(t, row, a)) != *negated,
        Cond::Cmp(a, op, b) => {
            let x = arg_value(t, row, a);
            let y = arg_value(t, row, b);
            if is_null(&x) || is_null(&y) {
                return false;
            }
            let c = compare(&x, &y);
            match op {
                CmpOp::Eq => c == 0,
                CmpOp::Ne => c != 0,
                CmpOp::Lt => c < 0,
                CmpOp::Le => c <= 0,
                CmpOp::Gt => c > 0,
                CmpOp::Ge => c >= 0,
            }
        }
    }
}

pub struct Groups {
    // The first row of each group, in order of first appearance.
    pub first: Vec<usize>,
    // The group of each kept row.
    pub group_of: Vec<usize>,
}

fn make_groups(p: &Plan, t: &Table, rows: &[usize]) -> Groups {
    let mut gs = Groups { first: Vec::new(), group_of: Vec::new() };
    let g = match p.group {
        Some(g) => g,
        None => {
            // one group of every kept row, even when there are none
            gs.first.push(0);
            for _ in rows {
                gs.group_of.push(0);
            }
            return gs;
        }
    };
    let mut ints: HashMap<i64, usize> = HashMap::new();
    let mut strs: HashMap<Vec<u8>, usize> = HashMap::new();
    let mut null_group: Option<usize> = None;
    for &r in rows {
        let next = gs.first.len();
        let found = match t.cell(r, g) {
            Value::Null => match null_group {
                Some(k) => Some(k),
                None => {
                    null_group = Some(next);
                    None
                }
            },
            Value::Int(v) => match ints.get(v) {
                Some(k) => Some(*k),
                None => {
                    ints.insert(*v, next);
                    None
                }
            },
            Value::Str(s) => match strs.get(s) {
                Some(k) => Some(*k),
                None => {
                    strs.insert(s.clone(), next);
                    None
                }
            },
        };
        match found {
            Some(k) => gs.group_of.push(k),
            None => {
                gs.first.push(r);
                gs.group_of.push(next);
            }
        }
    }
    gs
}

// The aggregates of every group: group k's are at [k * naggs ..].
fn aggregate(p: &Plan, t: &Table, rows: &[usize], gs: &Groups) -> Vec<Value> {
    let naggs = p.aggs.len();
    let mut vals: Vec<Value> = Vec::new();
    for _ in 0..gs.first.len() {
        for a in &p.aggs {
            vals.push(match a.kind {
                AggKind::CountStar | AggKind::Count => Value::Int(0),
                _ => Value::Null,
            });
        }
    }
    for k in 0..rows.len() {
        let base = gs.group_of[k] * naggs;
        for j in 0..naggs {
            let a = p.aggs[j];
            if a.kind == AggKind::CountStar {
                if let Value::Int(n) = vals[base + j] {
                    vals[base + j] = Value::Int(n + 1);
                }
                continue;
            }
            let v = t.cell(rows[k], a.col);
            if is_null(v) {
                continue;
            }
            let old = &vals[base + j];
            let new = match a.kind {
                AggKind::Count => match old {
                    Value::Int(n) => Some(Value::Int(n + 1)),
                    _ => None,
                },
                AggKind::Sum => match (old, v) {
                    (Value::Int(s), Value::Int(x)) => Some(Value::Int(s.wrapping_add(*x))),
                    (_, Value::Int(x)) => Some(Value::Int(*x)),
                    _ => None,
                },
                AggKind::Min => {
                    if is_null(old) || compare(v, old) < 0 {
                        Some(v.clone())
                    } else {
                        None
                    }
                }
                AggKind::Max => {
                    if is_null(old) || compare(v, old) > 0 {
                        Some(v.clone())
                    } else {
                        None
                    }
                }
                AggKind::CountStar => None,
            };
            if let Some(n) = new {
                vals[base + j] = n;
            }
        }
    }
    vals
}

fn push_value(out: &mut Vec<u8>, v: &Value) {
    match v {
        Value::Null => out.extend_from_slice(b"NULL"),
        Value::Int(n) => out.extend_from_slice(n.to_string().as_bytes()),
        Value::Str(s) => out.extend_from_slice(s),
    }
}

pub fn run(p: &Plan, t: &Table, out: &mut Vec<u8>) {
    let mut rows: Vec<usize> = Vec::new();
    for r in 0..t.nrows {
        let keep = match p.cond {
            Some(c) => holds(p, t, c, r),
            None => true,
        };
        if keep {
            rows.push(r);
        }
    }
    // Every output row's values, then its keys.
    let mut vals: Vec<Value> = Vec::new();
    let mut keys: Vec<Value> = Vec::new();
    let n;
    if !p.grouped {
        for &r in &rows {
            for e in &p.select {
                if let Expr::Col(c) = e {
                    vals.push(t.cell(r, *c).clone());
                }
            }
            for (e, _) in &p.order {
                if let Expr::Col(c) = e {
                    keys.push(t.cell(r, *c).clone());
                }
            }
        }
        n = rows.len();
    } else {
        let gs = make_groups(p, t, &rows);
        let aggs = aggregate(p, t, &rows, &gs);
        let naggs = p.aggs.len();
        n = gs.first.len();
        for k in 0..n {
            for e in &p.select {
                vals.push(match e {
                    Expr::Col(c) => t.cell(gs.first[k], *c).clone(),
                    Expr::Agg(a) => aggs[k * naggs + a].clone(),
                });
            }
            for (e, _) in &p.order {
                keys.push(match e {
                    Expr::Col(c) => t.cell(gs.first[k], *c).clone(),
                    Expr::Agg(a) => aggs[k * naggs + a].clone(),
                });
            }
        }
    }
    let mut desc = Vec::new();
    for (_, d) in &p.order {
        desc.push(*d);
    }
    let order = sorted_order(&keys, &desc, n);
    let mut count = n;
    if let Some(l) = p.limit {
        if (l as usize) < count {
            count = l as usize;
        }
    }

    for i in 0..p.headers.len() {
        if i > 0 {
            out.push(b'|');
        }
        out.extend_from_slice(&p.headers[i]);
    }
    out.push(b'\n');
    let nsel = p.select.len();
    for i in 0..count {
        let r = order[i];
        for j in 0..nsel {
            if j > 0 {
                out.push(b'|');
            }
            push_value(out, &vals[r * nsel + j]);
        }
        out.push(b'\n');
    }
    if count == 1 {
        out.extend_from_slice(b"(1 row)\n");
    } else {
        out.extend_from_slice(format!("({} rows)\n", count).as_bytes());
    }
}
