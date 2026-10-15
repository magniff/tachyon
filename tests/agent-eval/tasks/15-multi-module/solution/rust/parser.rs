// Parses a query's tokens into a Query; conditions are nodes in an arena.

use crate::lexer::{Kw, Tok, Token};

#[derive(Clone, Copy, PartialEq)]
pub enum AggKind {
    CountStar,
    Count,
    Sum,
    Min,
    Max,
}

#[derive(Clone)]
pub enum Item {
    Star,
    Col(Vec<u8>),
    // The column; empty for COUNT(*).
    Agg(AggKind, Vec<u8>),
}

#[derive(Clone)]
pub enum Operand {
    Name(Vec<u8>),
    Int(i64),
    Str(Vec<u8>),
}

#[derive(Clone, Copy, PartialEq)]
pub enum CmpOp {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}

// A condition node; children are indices in Query.nodes, always smaller
// than the node's own index (a leaf comes before the leaves to its right).
pub enum Node {
    Or(usize, usize),
    And(usize, usize),
    Not(usize),
    // true for IS NOT NULL
    IsNull(Operand, bool),
    Cmp(Operand, CmpOp, Operand),
}

pub struct OrderItem {
    pub item: Item,
    pub desc: bool,
}

pub struct Query {
    pub items: Vec<Item>,
    pub table: Vec<u8>,
    pub nodes: Vec<Node>,
    pub cond: Option<usize>,
    pub group: Option<Vec<u8>>,
    pub order: Vec<OrderItem>,
    pub limit: Option<i64>,
}

struct Parser<'a> {
    toks: &'a [Token],
    pos: usize,
    nodes: Vec<Node>,
}

fn error_at(t: &Token) -> Vec<u8> {
    if t.tok == Tok::End {
        return b"syntax error: unexpected end of query".to_vec();
    }
    let mut m = b"syntax error: unexpected ".to_vec();
    m.extend_from_slice(&t.text);
    m
}

impl<'a> Parser<'a> {
    fn peek(&self) -> &Tok {
        &self.toks[self.pos].tok
    }

    fn fail(&self) -> Vec<u8> {
        error_at(&self.toks[self.pos])
    }

    fn is_kw(&self, k: Kw) -> bool {
        *self.peek() == Tok::Kw(k)
    }

    fn expect(&mut self, t: Tok) -> Result<(), Vec<u8>> {
        if *self.peek() == t {
            self.pos += 1;
            Ok(())
        } else {
            Err(self.fail())
        }
    }

    fn name(&mut self) -> Result<Vec<u8>, Vec<u8>> {
        if *self.peek() == Tok::Name {
            let text = self.toks[self.pos].text.clone();
            self.pos += 1;
            Ok(text)
        } else {
            Err(self.fail())
        }
    }

    // NAME or an aggregate.
    fn item(&mut self) -> Result<Item, Vec<u8>> {
        let kind = match self.peek() {
            Tok::Name => return Ok(Item::Col(self.name()?)),
            Tok::Kw(Kw::Count) => AggKind::Count,
            Tok::Kw(Kw::Sum) => AggKind::Sum,
            Tok::Kw(Kw::Min) => AggKind::Min,
            Tok::Kw(Kw::Max) => AggKind::Max,
            _ => return Err(self.fail()),
        };
        self.pos += 1;
        self.expect(Tok::LParen)?;
        if kind == AggKind::Count && *self.peek() == Tok::Star {
            self.pos += 1;
            self.expect(Tok::RParen)?;
            return Ok(Item::Agg(AggKind::CountStar, Vec::new()));
        }
        let col = self.name()?;
        self.expect(Tok::RParen)?;
        Ok(Item::Agg(kind, col))
    }

    fn operand(&mut self) -> Result<Operand, Vec<u8>> {
        let op = match self.peek() {
            Tok::Name => Operand::Name(self.toks[self.pos].text.clone()),
            Tok::Int(v) => Operand::Int(*v),
            Tok::Str => Operand::Str(self.toks[self.pos].value.clone()),
            _ => return Err(self.fail()),
        };
        self.pos += 1;
        Ok(op)
    }

    fn push(&mut self, n: Node) -> usize {
        self.nodes.push(n);
        self.nodes.len() - 1
    }

    fn or(&mut self) -> Result<usize, Vec<u8>> {
        let mut left = self.and()?;
        while self.is_kw(Kw::Or) {
            self.pos += 1;
            let right = self.and()?;
            left = self.push(Node::Or(left, right));
        }
        Ok(left)
    }

    fn and(&mut self) -> Result<usize, Vec<u8>> {
        let mut left = self.not()?;
        while self.is_kw(Kw::And) {
            self.pos += 1;
            let right = self.not()?;
            left = self.push(Node::And(left, right));
        }
        Ok(left)
    }

    fn not(&mut self) -> Result<usize, Vec<u8>> {
        if self.is_kw(Kw::Not) {
            self.pos += 1;
            let inner = self.not()?;
            return Ok(self.push(Node::Not(inner)));
        }
        self.atom()
    }

    fn atom(&mut self) -> Result<usize, Vec<u8>> {
        if *self.peek() == Tok::LParen {
            self.pos += 1;
            let inner = self.or()?;
            self.expect(Tok::RParen)?;
            return Ok(inner);
        }
        let left = self.operand()?;
        if self.is_kw(Kw::Is) {
            self.pos += 1;
            let mut negated = false;
            if self.is_kw(Kw::Not) {
                self.pos += 1;
                negated = true;
            }
            self.expect(Tok::Kw(Kw::Null))?;
            return Ok(self.push(Node::IsNull(left, negated)));
        }
        let op = match self.peek() {
            Tok::Eq => CmpOp::Eq,
            Tok::Ne => CmpOp::Ne,
            Tok::Lt => CmpOp::Lt,
            Tok::Le => CmpOp::Le,
            Tok::Gt => CmpOp::Gt,
            Tok::Ge => CmpOp::Ge,
            _ => return Err(self.fail()),
        };
        self.pos += 1;
        let right = self.operand()?;
        Ok(self.push(Node::Cmp(left, op, right)))
    }

    fn query(&mut self) -> Result<Query, Vec<u8>> {
        self.expect(Tok::Kw(Kw::Select))?;
        let mut items = Vec::new();
        if *self.peek() == Tok::Star {
            self.pos += 1;
            items.push(Item::Star);
        } else {
            items.push(self.item()?);
            while *self.peek() == Tok::Comma {
                self.pos += 1;
                items.push(self.item()?);
            }
        }
        self.expect(Tok::Kw(Kw::From))?;
        let table = self.name()?;
        let mut cond = None;
        if self.is_kw(Kw::Where) {
            self.pos += 1;
            cond = Some(self.or()?);
        }
        let mut group = None;
        if self.is_kw(Kw::Group) {
            self.pos += 1;
            self.expect(Tok::Kw(Kw::By))?;
            group = Some(self.name()?);
        }
        let mut order = Vec::new();
        if self.is_kw(Kw::Order) {
            self.pos += 1;
            self.expect(Tok::Kw(Kw::By))?;
            loop {
                let item = self.item()?;
                let mut desc = false;
                if self.is_kw(Kw::Asc) {
                    self.pos += 1;
                } else if self.is_kw(Kw::Desc) {
                    self.pos += 1;
                    desc = true;
                }
                order.push(OrderItem { item, desc });
                if *self.peek() != Tok::Comma {
                    break;
                }
                self.pos += 1;
            }
        }
        let mut limit = None;
        if self.is_kw(Kw::Limit) {
            self.pos += 1;
            match self.peek() {
                Tok::Int(v) if *v >= 0 && self.toks[self.pos].text[0] != b'-' => {
                    limit = Some(*v);
                    self.pos += 1;
                }
                _ => return Err(self.fail()),
            }
        }
        if *self.peek() != Tok::End {
            return Err(self.fail());
        }
        let nodes = std::mem::take(&mut self.nodes);
        Ok(Query {
            items,
            table,
            nodes,
            cond,
            group,
            order,
            limit,
        })
    }
}

pub fn parse(toks: &[Token]) -> Result<Query, Vec<u8>> {
    let mut p = Parser {
        toks,
        pos: 0,
        nodes: Vec::new(),
    };
    p.query()
}
