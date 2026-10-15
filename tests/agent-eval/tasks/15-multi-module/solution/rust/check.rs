// Checks a parsed query against the table and resolves it into a Plan:
// column names become indices, aggregates are collected.

use crate::parser::{AggKind, CmpOp, Item, Node, Operand, Query};
use crate::table::{ColType, Table, Value};

#[derive(Clone, Copy)]
pub struct Agg {
    pub kind: AggKind,
    // Unused for COUNT(*).
    pub col: usize,
}

// A value of an output row: a column of the group's first row (or of the
// row), or the aggregate with this index in Plan.aggs.
#[derive(Clone, Copy)]
pub enum Expr {
    Col(usize),
    Agg(usize),
}

pub enum Arg {
    Col(usize),
    Lit(Value),
}

pub enum Cond {
    Or(usize, usize),
    And(usize, usize),
    Not(usize),
    IsNull(Arg, bool),
    Cmp(Arg, CmpOp, Arg),
}

pub struct Plan {
    pub headers: Vec<Vec<u8>>,
    pub select: Vec<Expr>,
    pub conds: Vec<Cond>,
    pub cond: Option<usize>,
    pub grouped: bool,
    pub group: Option<usize>,
    pub aggs: Vec<Agg>,
    pub order: Vec<(Expr, bool)>,
    pub limit: Option<i64>,
}

fn message(prefix: &[u8], name: &[u8], suffix: &[u8]) -> Vec<u8> {
    let mut m = prefix.to_vec();
    m.extend_from_slice(name);
    m.extend_from_slice(suffix);
    m
}

fn type_name(t: ColType) -> &'static [u8] {
    match t {
        ColType::Int => b"int",
        ColType::Str => b"str",
    }
}

fn agg_name(kind: AggKind) -> &'static [u8] {
    match kind {
        AggKind::CountStar | AggKind::Count => b"COUNT",
        AggKind::Sum => b"SUM",
        AggKind::Min => b"MIN",
        AggKind::Max => b"MAX",
    }
}

// The column names of an item, for the unknown-column check.
fn item_name(item: &Item) -> Option<&[u8]> {
    match item {
        Item::Star => None,
        Item::Col(n) => Some(n),
        Item::Agg(AggKind::CountStar, _) => None,
        Item::Agg(_, n) => Some(n),
    }
}

fn check_known(t: &Table, name: Option<&[u8]>) -> Result<(), Vec<u8>> {
    match name {
        Some(n) if t.find(n).is_none() => Err(message(b"unknown column ", n, b"")),
        _ => Ok(()),
    }
}

fn operand_name(op: &Operand) -> Option<&[u8]> {
    match op {
        Operand::Name(n) => Some(n),
        _ => None,
    }
}

fn operand_type(t: &Table, op: &Operand) -> ColType {
    match op {
        Operand::Name(n) => t.types[t.find(n).unwrap()],
        Operand::Int(_) => ColType::Int,
        Operand::Str(_) => ColType::Str,
    }
}

fn check_sum(t: &Table, item: &Item) -> Result<(), Vec<u8>> {
    if let Item::Agg(AggKind::Sum, n) = item {
        if t.types[t.find(n).unwrap()] == ColType::Str {
            return Err(message(b"cannot SUM str column ", n, b""));
        }
    }
    Ok(())
}

fn resolve_arg(t: &Table, op: &Operand) -> Arg {
    match op {
        Operand::Name(n) => Arg::Col(t.find(n).unwrap()),
        Operand::Int(v) => Arg::Lit(Value::Int(*v)),
        Operand::Str(s) => Arg::Lit(Value::Str(s.clone())),
    }
}

// The index in `aggs` of this aggregate, adding it when it is new.
fn agg_index(aggs: &mut Vec<Agg>, kind: AggKind, col: usize) -> usize {
    for i in 0..aggs.len() {
        if aggs[i].kind == kind && (kind == AggKind::CountStar || aggs[i].col == col) {
            return i;
        }
    }
    aggs.push(Agg { kind, col });
    aggs.len() - 1
}

fn resolve_item(t: &Table, aggs: &mut Vec<Agg>, item: &Item) -> Expr {
    match item {
        Item::Star => Expr::Col(0),
        Item::Col(n) => Expr::Col(t.find(n).unwrap()),
        Item::Agg(AggKind::CountStar, _) => Expr::Agg(agg_index(aggs, AggKind::CountStar, 0)),
        Item::Agg(kind, n) => Expr::Agg(agg_index(aggs, *kind, t.find(n).unwrap())),
    }
}

fn header(item: &Item) -> Vec<u8> {
    match item {
        Item::Star => b"*".to_vec(),
        Item::Col(n) => n.clone(),
        Item::Agg(AggKind::CountStar, _) => b"COUNT(*)".to_vec(),
        Item::Agg(kind, n) => {
            let mut h = agg_name(*kind).to_vec();
            h.push(b'(');
            h.extend_from_slice(n);
            h.push(b')');
            h
        }
    }
}

fn is_group_col(t: &Table, group: Option<usize>, name: &[u8]) -> bool {
    match group {
        Some(g) => t.find(name).unwrap() == g,
        None => false,
    }
}

pub fn plan(q: &Query, t: &Table) -> Result<Plan, Vec<u8>> {
    // 1. the table
    if q.table != b"t" {
        return Err(message(b"unknown table ", &q.table, b""));
    }
    // 2. unknown columns, in the order they are written
    for item in &q.items {
        check_known(t, item_name(item))?;
    }
    for node in &q.nodes {
        match node {
            Node::IsNull(a, _) => check_known(t, operand_name(a))?,
            Node::Cmp(a, _, b) => {
                check_known(t, operand_name(a))?;
                check_known(t, operand_name(b))?;
            }
            _ => {}
        }
    }
    if let Some(g) = &q.group {
        check_known(t, Some(g))?;
    }
    for o in &q.order {
        check_known(t, item_name(&o.item))?;
    }
    // 3. types
    for item in &q.items {
        check_sum(t, item)?;
    }
    for node in &q.nodes {
        if let Node::Cmp(a, _, b) = node {
            let ta = operand_type(t, a);
            let tb = operand_type(t, b);
            if ta != tb {
                let mut m = b"cannot compare ".to_vec();
                m.extend_from_slice(type_name(ta));
                m.extend_from_slice(b" with ");
                m.extend_from_slice(type_name(tb));
                return Err(m);
            }
        }
    }
    for o in &q.order {
        check_sum(t, &o.item)?;
    }
    // 4. grouping
    let mut grouped = q.group.is_some();
    for item in &q.items {
        if let Item::Agg(_, _) = item {
            grouped = true;
        }
    }
    let group = match &q.group {
        Some(g) => t.find(g),
        None => None,
    };
    if grouped {
        for item in &q.items {
            match item {
                Item::Star => return Err(b"column * must be grouped or aggregated".to_vec()),
                Item::Col(n) if !is_group_col(t, group, n) => {
                    return Err(message(b"column ", n, b" must be grouped or aggregated"))
                }
                _ => {}
            }
        }
    }
    for o in &q.order {
        match &o.item {
            Item::Col(n) if grouped && !is_group_col(t, group, n) => {
                return Err(message(b"column ", n, b" must be grouped or aggregated"))
            }
            Item::Agg(_, _) if !grouped => {
                return Err(b"aggregate in ORDER BY of an ungrouped query".to_vec())
            }
            _ => {}
        }
    }

    let mut aggs = Vec::new();
    let mut headers = Vec::new();
    let mut select = Vec::new();
    for item in &q.items {
        if let Item::Star = item {
            for c in 0..t.ncols() {
                headers.push(t.names[c].clone());
                select.push(Expr::Col(c));
            }
        } else {
            headers.push(header(item));
            select.push(resolve_item(t, &mut aggs, item));
        }
    }
    let mut order = Vec::new();
    for o in &q.order {
        order.push((resolve_item(t, &mut aggs, &o.item), o.desc));
    }
    let mut conds = Vec::new();
    for node in &q.nodes {
        conds.push(match node {
            Node::Or(a, b) => Cond::Or(*a, *b),
            Node::And(a, b) => Cond::And(*a, *b),
            Node::Not(a) => Cond::Not(*a),
            Node::IsNull(a, neg) => Cond::IsNull(resolve_arg(t, a), *neg),
            Node::Cmp(a, op, b) => Cond::Cmp(resolve_arg(t, a), *op, resolve_arg(t, b)),
        });
    }
    Ok(Plan {
        headers,
        select,
        conds,
        cond: q.cond,
        grouped,
        group,
        aggs,
        order,
        limit: q.limit,
    })
}
