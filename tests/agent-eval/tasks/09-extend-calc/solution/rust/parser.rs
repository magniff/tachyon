// Parses tokens into a tree, by recursive descent:
//
//   line       := 'let' NAME '=' expr | expr
//   expr       := relational (('==' | '!=') relational)*
//   relational := additive (('<' | '<=' | '>' | '>=') additive)*
//   additive   := term (('+' | '-') term)*
//   term       := unary (('*' | '/' | '%') unary)*
//   unary      := '-' unary | primary
//   primary    := NUMBER | NAME | '(' expr ')'
//
// The nodes live in one vector and refer to each other by index.

use crate::lexer::{Token, TokenKind};

#[derive(Clone, Copy, PartialEq)]
pub enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Lt,
    Le,
    Gt,
    Ge,
    Eq,
    Ne,
}

#[derive(Clone)]
pub enum Node {
    Num(i64),
    Var(String),
    Neg(usize),
    // An operator and the indices of its left and right operands.
    Binary(Op, usize, usize),
}

pub struct Tree {
    pub nodes: Vec<Node>,
    pub root: usize,
    // The variable a `let` line sets.
    pub let_name: Option<String>,
}

struct Parser {
    tokens: Vec<Token>,
    pos: usize,
    nodes: Vec<Node>,
}

impl Parser {
    fn peek(&self) -> TokenKind {
        self.tokens[self.pos].kind
    }

    fn advance(&mut self) -> Token {
        let t = self.tokens[self.pos].clone();
        if t.kind != TokenKind::End {
            self.pos += 1;
        }
        t
    }

    fn add(&mut self, node: Node) -> usize {
        self.nodes.push(node);
        self.nodes.len() - 1
    }

    fn binary(&mut self, op: Op, left: usize, right: usize) -> usize {
        self.add(Node::Binary(op, left, right))
    }

    fn expr(&mut self) -> Option<usize> {
        let mut left = self.relational()?;
        loop {
            let op = match self.peek() {
                TokenKind::EqEq => Op::Eq,
                TokenKind::Ne => Op::Ne,
                _ => return Some(left),
            };
            self.advance();
            let right = self.relational()?;
            left = self.binary(op, left, right);
        }
    }

    fn relational(&mut self) -> Option<usize> {
        let mut left = self.additive()?;
        loop {
            let op = match self.peek() {
                TokenKind::Lt => Op::Lt,
                TokenKind::Le => Op::Le,
                TokenKind::Gt => Op::Gt,
                TokenKind::Ge => Op::Ge,
                _ => return Some(left),
            };
            self.advance();
            let right = self.additive()?;
            left = self.binary(op, left, right);
        }
    }

    fn additive(&mut self) -> Option<usize> {
        let mut left = self.term()?;
        loop {
            let op = match self.peek() {
                TokenKind::Plus => Op::Add,
                TokenKind::Minus => Op::Sub,
                _ => return Some(left),
            };
            self.advance();
            let right = self.term()?;
            left = self.binary(op, left, right);
        }
    }

    fn term(&mut self) -> Option<usize> {
        let mut left = self.unary()?;
        loop {
            let op = match self.peek() {
                TokenKind::Star => Op::Mul,
                TokenKind::Slash => Op::Div,
                TokenKind::Percent => Op::Rem,
                _ => return Some(left),
            };
            self.advance();
            let right = self.unary()?;
            left = self.binary(op, left, right);
        }
    }

    fn unary(&mut self) -> Option<usize> {
        if self.peek() == TokenKind::Minus {
            self.advance();
            let inner = self.unary()?;
            return Some(self.add(Node::Neg(inner)));
        }
        self.primary()
    }

    fn primary(&mut self) -> Option<usize> {
        let t = self.advance();
        match t.kind {
            TokenKind::Num => Some(self.add(Node::Num(t.value))),
            TokenKind::Name => Some(self.add(Node::Var(t.name))),
            TokenKind::LParen => {
                let inner = self.expr()?;
                if self.advance().kind != TokenKind::RParen {
                    return None;
                }
                Some(inner)
            }
            _ => None,
        }
    }
}

// The tree of a whole line, or None when the tokens are not a line of
// the grammar.
pub fn parse(tokens: Vec<Token>) -> Option<Tree> {
    let mut p = Parser {
        tokens: tokens,
        pos: 0,
        nodes: Vec::new(),
    };
    let mut let_name = None;
    if p.peek() == TokenKind::Let {
        p.advance();
        let name = p.advance();
        if name.kind != TokenKind::Name || p.advance().kind != TokenKind::Assign {
            return None;
        }
        let_name = Some(name.name);
    }
    let root = p.expr()?;
    if p.peek() != TokenKind::End {
        return None;
    }
    Some(Tree {
        nodes: p.nodes,
        root: root,
        let_name: let_name,
    })
}
