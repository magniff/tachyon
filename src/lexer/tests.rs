use super::token::NumSuffix;
use super::*;

#[test]
fn test_lex_integers() {
    let mut l = Lexer::new("42 0xFF 0b1010 1_000_000");
    let t = l.tokenize().unwrap();
    assert!(matches!(t[0].kind, TokenKind::IntLiteral(42)));
    assert!(matches!(t[1].kind, TokenKind::IntLiteral(255)));
    assert!(matches!(t[2].kind, TokenKind::IntLiteral(10)));
    assert!(matches!(t[3].kind, TokenKind::IntLiteral(1000000)));
}

#[test]
fn test_lex_floats() {
    let mut l = Lexer::new("3.25 1.0 2.0e10 1.5e-3");
    let t = l.tokenize().unwrap();
    assert!(matches!(t[0].kind, TokenKind::FloatLiteral(v) if (*v - 3.25).abs() < 1e-10));
    assert!(matches!(t[1].kind, TokenKind::FloatLiteral(v) if (*v - 1.0).abs() < 1e-10));
    assert!(matches!(t[2].kind, TokenKind::FloatLiteral(v) if (*v - 2.0e10).abs() < 1.0));
    assert!(matches!(t[3].kind, TokenKind::FloatLiteral(v) if (*v - 1.5e-3).abs() < 1e-10));
}

#[test]
fn test_lex_strings() {
    let mut l = Lexer::new(r#""hello" "world\n" "\x41""#);
    let t = l.tokenize().unwrap();
    assert!(matches!(&t[0].kind, TokenKind::StringLiteral(s) if s == b"hello"));
    assert!(matches!(&t[1].kind, TokenKind::StringLiteral(s) if s == b"world\n"));
    assert!(matches!(&t[2].kind, TokenKind::StringLiteral(s) if s == b"A"));
}

#[test]
fn test_lex_trailing_underscore_err() {
    let mut l = Lexer::new("100_");
    assert!(l.tokenize().is_err());
}

fn kinds(src: &str) -> Vec<TokenKind> {
    Lexer::new(src)
        .tokenize()
        .unwrap_or_else(|e| panic!("{}: {}", src, e))
        .into_iter()
        .map(|t| t.kind)
        .collect()
}

fn lex_err(src: &str) -> String {
    Lexer::new(src).tokenize().unwrap_err().message
}

#[test]
fn test_lex_new_keywords_and_reserved() {
    assert_eq!(
        kinds("while for in mut const static type match Self moved"),
        vec![
            TokenKind::While,
            TokenKind::For,
            TokenKind::In,
            TokenKind::Mut,
            TokenKind::Const,
            TokenKind::Static,
            TokenKind::Type,
            TokenKind::Reserved("match"),
            TokenKind::Reserved("Self"),
            TokenKind::Ident("moved".into()),
            TokenKind::EOF,
        ]
    );
}

#[test]
fn test_lex_star_star_is_two_tokens() {
    assert_eq!(
        kinds("**p"),
        vec![
            TokenKind::Star,
            TokenKind::Star,
            TokenKind::Ident("p".into()),
            TokenKind::EOF
        ]
    );
}

#[test]
fn test_lex_joint_flag() {
    let t = Lexer::new("&&x && y // c\n").tokenize().unwrap();
    assert!(t[0].joint);
    assert!(!t[2].joint);
    assert!(!t[3].joint);
}

#[test]
fn test_lex_block_comments_nest() {
    assert_eq!(
        kinds("1 /* a /* b */ c */ 2 /**/ 3"),
        vec![
            TokenKind::IntLiteral(1),
            TokenKind::IntLiteral(2),
            TokenKind::IntLiteral(3),
            TokenKind::EOF
        ]
    );
    assert!(lex_err("1 /* a /* b */").contains("unterminated block comment"));
}

#[test]
fn test_lex_char_literals() {
    assert_eq!(
        kinds(r"'a' '\n' '\'' '\\' '\x41' '\u{7a}' '0'"),
        vec![
            TokenKind::CharLiteral(b'a'),
            TokenKind::CharLiteral(b'\n'),
            TokenKind::CharLiteral(b'\''),
            TokenKind::CharLiteral(b'\\'),
            TokenKind::CharLiteral(0x41),
            TokenKind::CharLiteral(b'z'),
            TokenKind::CharLiteral(b'0'),
            TokenKind::EOF,
        ]
    );
    assert!(lex_err("''").contains("empty character literal"));
    assert!(lex_err("'ab'").contains("unterminated character literal"));
    assert!(lex_err("'é'").contains("not ASCII"));
    assert!(lex_err(r"'\u{e9}'").contains("not ASCII"));
}

#[test]
fn test_lex_unicode_escape_in_string() {
    assert_eq!(
        kinds(r#""\u{e9}\u{1F600}\'""#),
        vec![
            TokenKind::StringLiteral(vec![0xc3, 0xa9, 0xf0, 0x9f, 0x98, 0x80, b'\'']),
            TokenKind::EOF
        ]
    );
    assert!(lex_err(r#""\u{110000}""#).contains("invalid unicode escape"));
}

#[test]
fn test_lex_c_strings() {
    assert_eq!(
        kinds(r#"c"hi\n" cx"#),
        vec![
            TokenKind::CStringLiteral(b"hi\n".to_vec()),
            TokenKind::Ident("cx".into()),
            TokenKind::EOF
        ]
    );
    assert!(lex_err(r#"c"a\0b""#).contains("NUL"));
}

#[test]
fn test_lex_suffixes() {
    assert_eq!(
        kinds("1u8 255_u8 0xffu32 0b1i8 7usize 2f32 1.5f64 1e3f32 7i64"),
        vec![
            TokenKind::SuffixedInt(1, NumSuffix::U8),
            TokenKind::SuffixedInt(255, NumSuffix::U8),
            TokenKind::SuffixedInt(0xff, NumSuffix::U32),
            TokenKind::SuffixedInt(1, NumSuffix::I8),
            TokenKind::SuffixedInt(7, NumSuffix::Usize),
            TokenKind::SuffixedFloat(2.0.into(), NumSuffix::F32),
            TokenKind::SuffixedFloat(1.5.into(), NumSuffix::F64),
            TokenKind::SuffixedFloat(1e3.into(), NumSuffix::F32),
            TokenKind::SuffixedInt(7, NumSuffix::I64),
            TokenKind::EOF,
        ]
    );
    assert!(lex_err("1foo").contains("invalid suffix 'foo'"));
    assert!(lex_err("1.5u8").contains("invalid suffix 'u8' on float literal"));
    assert!(lex_err("0b1f32").contains("invalid suffix 'f32'"));
}

#[test]
fn test_lex_ranges() {
    assert_eq!(
        kinds("0..10 a..=b"),
        vec![
            TokenKind::IntLiteral(0),
            TokenKind::DotDot,
            TokenKind::IntLiteral(10),
            TokenKind::Ident("a".into()),
            TokenKind::DotDotEq,
            TokenKind::Ident("b".into()),
            TokenKind::EOF,
        ]
    );
}

#[test]
fn test_lex_non_ascii_message() {
    assert!(lex_err("é").contains("unexpected character 'é'"));
}

#[test]
fn test_lex_keywords_and_idents() {
    let mut l =
        Lexer::new("fn let struct if else loop break continue true false as return extern foo");
    let t = l.tokenize().unwrap();
    assert!(matches!(t[0].kind, TokenKind::Fn));
    assert!(matches!(t[1].kind, TokenKind::Let));
    assert!(matches!(t[2].kind, TokenKind::Struct));
    assert!(matches!(t[3].kind, TokenKind::If));
    assert!(matches!(t[4].kind, TokenKind::Else));
    assert!(matches!(t[5].kind, TokenKind::Loop));
    assert!(matches!(t[6].kind, TokenKind::Break));
    assert!(matches!(t[7].kind, TokenKind::Continue));
    assert!(matches!(t[8].kind, TokenKind::True));
    assert!(matches!(t[9].kind, TokenKind::False));
    assert!(matches!(t[10].kind, TokenKind::As));
    assert!(matches!(t[11].kind, TokenKind::Return));
    assert!(matches!(t[12].kind, TokenKind::Extern));
    assert!(matches!(&t[13].kind, TokenKind::Ident(s) if s == "foo"));
}

#[test]
fn test_lex_operators() {
    let mut l = Lexer::new(
        "+= -= != == >= <= && || -> << >> <<= >>= ... *= /= %= &= |= ^= .. ..= :: => # ? @",
    );
    let t = l.tokenize().unwrap();
    let kinds: Vec<TokenKind> = t.into_iter().map(|t| t.kind).collect();
    assert_eq!(
        kinds,
        vec![
            TokenKind::PlusEq,
            TokenKind::MinusEq,
            TokenKind::BangEq,
            TokenKind::EqEq,
            TokenKind::GtEq,
            TokenKind::LtEq,
            TokenKind::AmpAmp,
            TokenKind::PipePipe,
            TokenKind::Arrow,
            TokenKind::Shl,
            TokenKind::Shr,
            TokenKind::ShlEq,
            TokenKind::ShrEq,
            TokenKind::Ellipsis,
            TokenKind::StarEq,
            TokenKind::SlashEq,
            TokenKind::PercentEq,
            TokenKind::AmpEq,
            TokenKind::PipeEq,
            TokenKind::CaretEq,
            TokenKind::DotDot,
            TokenKind::DotDotEq,
            TokenKind::ColonColon,
            TokenKind::FatArrow,
            TokenKind::Hash,
            TokenKind::Question,
            TokenKind::At,
            TokenKind::EOF,
        ]
    );
}

#[test]
fn test_lex_comments() {
    let mut l = Lexer::new("42 // comment\n43");
    let t = l.tokenize().unwrap();
    assert!(matches!(t[0].kind, TokenKind::IntLiteral(42)));
    assert!(matches!(t[1].kind, TokenKind::IntLiteral(43)));
}

#[test]
fn test_lex_exponent_without_fraction() {
    let mut l = Lexer::new("1e3 2E-2 7e+1");
    let t = l.tokenize().unwrap();
    assert!(matches!(&t[0].kind, TokenKind::FloatLiteral(f) if **f == 1e3));
    assert!(matches!(&t[1].kind, TokenKind::FloatLiteral(f) if **f == 2e-2));
    assert!(matches!(&t[2].kind, TokenKind::FloatLiteral(f) if **f == 7e1));
    // `3e` has no exponent digits: `e` is an (invalid) suffix
    let err = Lexer::new("3e").tokenize().unwrap_err();
    assert!(
        err.message.contains("invalid suffix 'e'"),
        "{}",
        err.message
    );
}

#[test]
fn test_lex_nested_tuple_index() {
    let mut l = Lexer::new("t.0.1 x = 0.1");
    let t = l.tokenize().unwrap();
    assert!(matches!(t[2].kind, TokenKind::IntLiteral(0)));
    assert!(matches!(t[3].kind, TokenKind::Dot));
    assert!(matches!(t[4].kind, TokenKind::IntLiteral(1)));
    assert!(matches!(&t[7].kind, TokenKind::FloatLiteral(f) if **f == 0.1));
}

#[test]
fn test_lex_hex_escape_is_one_byte() {
    let mut l = Lexer::new(r#""\xff\x00é""#);
    let t = l.tokenize().unwrap();
    assert!(matches!(&t[0].kind, TokenKind::StringLiteral(s) if s == &[0xff, 0x00, 0xc3, 0xa9]));
}
