// Error recovery: after a syntax error the parser skips ahead to a point
// where parsing can resume, so later errors are still found.

use super::Parser;
use crate::lexer::token::TokenKind;

pub(super) fn is_item_start(kind: &TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::Fn
            | TokenKind::Extern
            | TokenKind::Struct
            | TokenKind::Const
            | TokenKind::Static
            | TokenKind::Type
    )
}

impl Parser {
    // Skips the rest of a broken statement: up to and including the next
    // `;`, or up to the `}` that closes the enclosing block, or a keyword
    // that starts the next statement or item. Braces are skipped as units.
    // `start` is where the statement began; at least one token is skipped.
    pub(super) fn recover_stmt(&mut self, start: usize) {
        let mut depth = 0usize;
        loop {
            match self.current() {
                TokenKind::EOF => break,
                TokenKind::LBrace => depth += 1,
                TokenKind::RBrace if depth == 0 => break,
                TokenKind::RBrace => depth -= 1,
                TokenKind::Semi if depth == 0 => {
                    self.advance();
                    break;
                }
                kind if depth == 0
                    && self.pos != start
                    && (*kind == TokenKind::Let || is_item_start(kind)) =>
                {
                    break;
                }
                _ => {}
            }
            self.advance();
        }
        if self.pos == start && !matches!(self.current(), TokenKind::RBrace | TokenKind::EOF) {
            self.advance();
        }
    }

    // Skips to the next item keyword at the top level.
    pub(super) fn recover_item(&mut self, start: usize) {
        let mut depth = 0usize;
        loop {
            match self.current() {
                TokenKind::EOF => break,
                TokenKind::LBrace => depth += 1,
                TokenKind::RBrace => depth = depth.saturating_sub(1),
                kind if depth == 0 && self.pos != start && is_item_start(kind) => break,
                _ => {}
            }
            self.advance();
        }
    }
}
