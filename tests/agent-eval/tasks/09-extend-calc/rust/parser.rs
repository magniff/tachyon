// Parses tokens into a tree, by recursive descent:
//
//   expr    := term (('+' | '-') term)*
//   term    := primary (('*' | '/') primary)*
//   primary := NUMBER | '(' expr ')'
//
// The nodes live in one vector and refer to each other by index.

use crate::lexer::{Token, TokenKind};

#[derive(Clone, Copy, PartialEq)]
pub enum Op {
    Add,
    Sub,
    Mul,
    Div,
}

#[derive(Clone, Copy)]
pub enum Node {
    Num(i64),
    // An operator and the indices of its left and right operands.
    Binary(Op, usize, usize),
}

pub struct Tree {
    pub nodes: Vec<Node>,
    pub root: usize,
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
        let t = self.tokens[self.pos];
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
        let mut left = self.primary()?;
        loop {
            let op = match self.peek() {
                TokenKind::Star => Op::Mul,
                TokenKind::Slash => Op::Div,
                _ => return Some(left),
            };
            self.advance();
            let right = self.primary()?;
            left = self.binary(op, left, right);
        }
    }

    fn primary(&mut self) -> Option<usize> {
        let t = self.advance();
        match t.kind {
            TokenKind::Num => Some(self.add(Node::Num(t.value))),
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

// The tree of a whole line, or None when the tokens are not an expression.
pub fn parse(tokens: Vec<Token>) -> Option<Tree> {
    let mut p = Parser { tokens: tokens, pos: 0, nodes: Vec::new() };
    let root = p.expr()?;
    if p.peek() != TokenKind::End {
        return None;
    }
    Some(Tree { nodes: p.nodes, root: root })
}
