
use super::*;

pub fn parse_source(src: &str) -> Result<Program, Vec<ParserError>> {
    parse(crate::lexer::Lexer::new(src).tokenize().unwrap())
}

fn parse_ok(src: &str) -> Program {
    parse_source(src).unwrap_or_else(|e| panic!("parse failed: {:?}\nsource: {}", e, src))
}

fn parse_errs(src: &str) -> Vec<String> {
    match parse_source(src) {
        Ok(_) => panic!("expected parse error for: {}", src),
        Err(errors) => errors.into_iter().map(|e| e.message).collect(),
    }
}

fn parse_err(src: &str) {
    parse_errs(src);
}

fn parse_err_contains(src: &str, needle: &str) {
    let errors = parse_errs(src);
    assert!(
        errors.iter().any(|e| e.contains(needle)),
        "expected an error containing {:?}, got {:?}\nsource: {}",
        needle,
        errors,
        src
    );
}

// ---- S-expression printer, to check tree shapes compactly ----

fn binop(op: BinOp) -> &'static str {
    match op {
        BinOp::Add => "+",
        BinOp::Sub => "-",
        BinOp::Mul => "*",
        BinOp::Div => "/",
        BinOp::Mod => "%",
        BinOp::Eq => "==",
        BinOp::Neq => "!=",
        BinOp::Lt => "<",
        BinOp::Gt => ">",
        BinOp::LtEq => "<=",
        BinOp::GtEq => ">=",
        BinOp::And => "&&",
        BinOp::Or => "||",
        BinOp::BitAnd => "&",
        BinOp::BitOr => "|",
        BinOp::BitXor => "^",
        BinOp::Shl => "<<",
        BinOp::Shr => ">>",
    }
}

fn ty(t: &Type) -> String {
    match &t.kind {
        TypeKind::Named(n) => n.clone(),
        TypeKind::Unit => "()".into(),
        TypeKind::Never => "!".into(),
        TypeKind::Tuple(ts) => {
            format!("({})", ts.iter().map(ty).collect::<Vec<_>>().join(", "))
        }
        TypeKind::Array(e, n) => format!("[{}; {}]", ty(e), sx(n)),
        TypeKind::Pointer(p) => format!("*{}", ty(p)),
        TypeKind::Fn { params, result } => format!(
            "fn({}) -> {}",
            params.iter().map(ty).collect::<Vec<_>>().join(", "),
            ty(result)
        ),
    }
}

fn pat(p: &Pattern) -> String {
    match &p.kind {
        PatternKind::Wildcard => "_".into(),
        PatternKind::Binding { name, mutable } => {
            format!("{}{}", if *mutable { "mut " } else { "" }, name)
        }
        PatternKind::Tuple(ps) => {
            format!("({})", ps.iter().map(pat).collect::<Vec<_>>().join(", "))
        }
    }
}

fn label(l: &Option<Spanned<String>>) -> String {
    l.as_ref().map(|l| format!(" :{}", l.0)).unwrap_or_default()
}

fn block(b: &Block) -> String {
    let mut parts: Vec<String> = b
        .stmts
        .iter()
        .map(|s| match s {
            Stmt::Let(l) => format!(
                "(let {}{} {});",
                pat(&l.pattern),
                l.ty.as_ref()
                    .map(|t| format!(": {}", ty(t)))
                    .unwrap_or_default(),
                sx(&l.init)
            ),
            Stmt::Expr(e) => format!("{}{}", sx(&e.expr), if e.has_semi { ";" } else { "" }),
        })
        .collect();
    if let Some(t) = &b.expr {
        parts.push(sx(t));
    }
    format!("{{{}}}", parts.join(" "))
}

fn list(es: &[Expr]) -> String {
    es.iter().map(sx).collect::<Vec<_>>().join(" ")
}

fn sx(e: &Expr) -> String {
    match &e.kind {
        ExprKind::Error => "<error>".into(),
        ExprKind::IntLiteral(v) => v.to_string(),
        ExprKind::FloatLiteral(f) => format!("{:?}", **f),
        ExprKind::CharLiteral(c) => format!("{:?}", *c as char),
        ExprKind::SuffixedLiteral(LitValue::Int(v), s) => format!("{}{}", v, s.name()),
        ExprKind::SuffixedLiteral(LitValue::Float(f), s) => format!("{:?}{}", **f, s.name()),
        ExprKind::StringLiteral(s) => format!("{:?}", String::from_utf8_lossy(s)),
        ExprKind::CStringLiteral(s) => format!("c{:?}", String::from_utf8_lossy(s)),
        ExprKind::BoolLiteral(b) => b.to_string(),
        ExprKind::UnitLiteral => "()".into(),
        ExprKind::Ident(n) => n.clone(),
        ExprKind::Tuple(es) => format!("(tuple {})", list(es)),
        ExprKind::Array(es) => format!("[{}]", list(es)),
        ExprKind::ArrayRepeat(v, n) => format!("[{}; {}]", sx(v), sx(n)),
        ExprKind::StructConstructor { name, fields } => format!(
            "({} {})",
            name.0,
            fields
                .iter()
                .map(|f| format!("{}: {}", f.name.0, sx(&f.value)))
                .collect::<Vec<_>>()
                .join(" ")
        ),
        ExprKind::BinOp { op, lhs, rhs } => format!("({} {} {})", binop(*op), sx(lhs), sx(rhs)),
        ExprKind::UnaryOp { op, expr } => {
            let o = match op {
                UnaryOp::Neg => "-",
                UnaryOp::Not => "!",
                UnaryOp::BitNot => "~",
                UnaryOp::Deref => "*",
                UnaryOp::AddrOf => "&",
            };
            format!("({} {})", o, sx(expr))
        }
        ExprKind::Cast { expr, ty: t } => format!("(as {} {})", sx(expr), ty(t)),
        ExprKind::Call { callee, args } => {
            format!(
                "(call {}{}{})",
                sx(callee),
                if args.is_empty() { "" } else { " " },
                list(args)
            )
        }
        ExprKind::Index { expr, index } => format!("(index {} {})", sx(expr), sx(index)),
        ExprKind::Field { expr, name } => format!("(. {} {})", sx(expr), name.0),
        ExprKind::TupleField { expr, index } => format!("(. {} {})", sx(expr), index.0),
        ExprKind::Range {
            start,
            end,
            inclusive,
        } => format!(
            "({} {} {})",
            if *inclusive { "..=" } else { ".." },
            sx(start),
            sx(end)
        ),
        ExprKind::Assign { op, target, value } => {
            let o = match op {
                AssignOp::Assign => "=".to_string(),
                other => format!("{}=", binop(other.binop().unwrap())),
            };
            format!("({} {} {})", o, sx(target), sx(value))
        }
        ExprKind::Block(b) => block(b),
        ExprKind::If {
            cond,
            then_block,
            else_block,
        } => match else_block {
            Some(eb) => format!("(if {} {} {})", sx(cond), block(then_block), block(eb)),
            None => format!("(if {} {})", sx(cond), block(then_block)),
        },
        ExprKind::Loop { label: l, body } => format!("(loop{} {})", label(l), block(body)),
        ExprKind::While {
            label: l,
            cond,
            body,
        } => format!("(while{} {} {})", label(l), sx(cond), block(body)),
        ExprKind::For {
            label: l,
            pattern,
            iter,
            body,
        } => format!(
            "(for{} {} {} {})",
            label(l),
            pat(pattern),
            sx(iter),
            block(body)
        ),
        ExprKind::Return(v) => match v {
            Some(v) => format!("(return {})", sx(v)),
            None => "(return)".into(),
        },
        ExprKind::Break { label: l, value } => match value {
            Some(v) => format!("(break{} {})", label(l), sx(v)),
            None => format!("(break{})", label(l)),
        },
        ExprKind::Continue { label: l } => format!("(continue{})", label(l)),
    }
}

// The body of `fn f() { <src> }`, printed.
fn body(src: &str) -> String {
    let program = parse_ok(&format!("fn f() {{ {} }}", src));
    let Item::Function(f) = &program.items[0] else {
        panic!()
    };
    block(&f.body)
}

// An expression, printed.
fn expr(src: &str) -> String {
    let printed = body(src);
    printed[1..printed.len() - 1].to_string()
}

// ---- Items ----

#[test]
fn test_empty_program() {
    assert!(parse_ok("").items.is_empty());
}

#[test]
fn test_items() {
    let p = parse_ok(
        r#"
            struct Point { x: i32, y: i32, }
            struct Empty {}
            extern fn puts(s: *u8) -> i32;
            extern "C" fn printf(fmt: *u8, ...) -> i32;
            fn add(a: i32, mut b: i32,) -> i32 { a }
            fn ignore(_: i64) {}
            const N: i64 = 4 * 2;
            static mut COUNT: u64 = 0;
            static TABLE: [u8; N] = [0; N];
            type Grid = [[u8; 3]; 3];
            "#,
    );
    assert_eq!(p.items.len(), 10);
    let Item::Function(add) = &p.items[4] else {
        panic!()
    };
    assert!(!add.params[0].mutable && add.params[1].mutable);
    let Item::Extern(printf) = &p.items[3] else {
        panic!()
    };
    assert!(printf.is_variadic);
    let Item::Static(count) = &p.items[7] else {
        panic!()
    };
    assert!(count.mutable);
}

#[test]
fn test_types() {
    let p = parse_ok(
        "fn f(a: (i32, f64), b: (i32,), c: [i32; 2 * N], d: **i32, e: fn(i32) -> *u8, g: fn()) -> ! { loop {} }",
    );
    let Item::Function(f) = &p.items[0] else {
        panic!()
    };
    let printed: Vec<String> = f.params.iter().map(|p| ty(&p.ty)).collect();
    assert_eq!(
        printed,
        vec![
            "(i32, f64)",
            "(i32)",
            "[i32; (* 2 N)]",
            "**i32",
            "fn(i32) -> *u8",
            "fn() -> ()"
        ]
    );
    assert_eq!(ty(f.return_type.as_ref().unwrap()), "!");
}

#[test]
fn test_item_errors() {
    parse_err_contains("fn f() {} pub fn g() {}", "'pub' is a reserved keyword");
    parse_err_contains("extern \"Rust\" fn f();", "unsupported ABI");
    parse_err_contains(
        "fn f(x: i64, ...) {}",
        "only extern functions can be variadic",
    );
    parse_err_contains(
        "fn f(g: fn(i64, ...) -> i64) {}",
        "function pointer types cannot be variadic",
    );
    parse_err_contains("fn f(x: [u8]) {}", "slice types are not supported yet");
    parse_err_contains("fn f(x: a::B) {}", "paths are not supported yet");
    parse_err_contains("type V<T> = T;", "generic type aliases");
    parse_err_contains("fn match() {}", "'match' is a reserved keyword");
}

// ---- Statements ----

#[test]
fn test_let_and_patterns() {
    assert_eq!(body("let x: i32 = 42;"), "{(let x: i32 42);}");
    assert_eq!(
        body(
            "let mut x = 1; let _ = f(); let (a, mut b, _) = t; let ((p, q), r) = u; let (s) = 1;"
        ),
        "{(let mut x 1); (let _ (call f)); (let (a, mut b, _) t); (let ((p, q), r) u); (let s 1);}"
    );
    assert_eq!(body("let (one,) = t;"), "{(let (one) t);}");
    parse_err_contains("fn f() { let x: i64; }", "without an initializer");
    parse_err_contains("fn f() { let mut _ = 1; }", "expected a name, got '_'");
}

#[test]
fn test_statement_rule() {
    // Block-like statements need no `;`, and a following `;` is theirs.
    assert_eq!(
        body("if c { a(); } let x = 1; loop { break; }; while c {} b()"),
        "{(if c {(call a);}) (let x 1); (loop {(break);}); (while c {}) (call b)}"
    );
    // ... and are never continued by an operator: `- 1` is a new statement.
    assert_eq!(body("{ 1 } - 1"), "{{1} (- 1)}");
    // A trailing block-like expression is the block's value.
    assert_eq!(
        body("let y = 0; if c { 1 } else { 2 }"),
        "{(let y 0); (if c {1} {2})}"
    );
    // Empty statements are allowed anywhere.
    assert_eq!(body(";; let x = 1;;"), "{(let x 1);}");
    // Other expressions need a `;` unless they are the tail.
    parse_err_contains("fn f() { a() b() }", "expected ';' or '}' after expression");
    parse_err("fn main() { let x = 42 }");
}

#[test]
fn test_assignment_is_an_expression() {
    assert_eq!(expr("x = 42"), "(= x 42)");
    assert_eq!(
        body("x += 1; x -= 2; x *= 3; x /= 4; x %= 5; x &= 6; x |= 7; x ^= 8; x <<= 9; x >>= 10;"),
        "{(+= x 1); (-= x 2); (*= x 3); (/= x 4); (%= x 5); (&= x 6); (|= x 7); (^= x 8); (<<= x 9); (>>= x 10);}"
    );
    // right-associative, lowest precedence
    assert_eq!(expr("a = b = c + 1"), "(= a (= b (+ c 1)))");
    assert_eq!(expr("*p.x = a[i] = 0"), "(= (* (. p x)) (= (index a i) 0))");
    // targets are checked by the type checker, not the parser
    assert_eq!(expr("f().x = 3"), "(= (. (call f) x) 3)");
}

// ---- Expressions: precedence and associativity ----

#[test]
fn test_arithmetic_precedence() {
    assert_eq!(expr("1 + 2 * 3"), "(+ 1 (* 2 3))");
    assert_eq!(expr("1 - 2 - 3"), "(- (- 1 2) 3)");
    assert_eq!(expr("a / b % c * d"), "(* (% (/ a b) c) d)");
    assert_eq!(expr("(1 + 2) * 3"), "(* (+ 1 2) 3)");
    assert_eq!(expr("a << 1 + 2"), "(<< a (+ 1 2))");
    assert_eq!(expr("a & b ^ c | d"), "(| (^ (& a b) c) d)");
    assert_eq!(expr("a | b == c"), "(== (| a b) c)");
    assert_eq!(expr("a < b && c || d"), "(|| (&& (< a b) c) d)");
}

#[test]
fn test_unary_and_cast_precedence() {
    assert_eq!(expr("-x as i64"), "(as (- x) i64)");
    assert_eq!(expr("a * b as f64"), "(* a (as b f64))");
    assert_eq!(expr("x as u8 as i32"), "(as (as x u8) i32)");
    assert_eq!(expr("*p.x"), "(* (. p x))");
    assert_eq!(expr("-a[0]"), "(- (index a 0))");
    assert_eq!(expr("!f()"), "(! (call f))");
    assert_eq!(expr("~0xFF"), "(~ 255)");
    assert_eq!(expr("&a.b"), "(& (. a b))");
    assert_eq!(expr("(p as u64 + i) as *u8"), "(as (+ (as p u64) i) *u8)");
    assert_eq!(expr("x as u64 < n"), "(< (as x u64) n)");
}

#[test]
fn test_double_star_and_double_amp() {
    // `**` is two derefs, `&&` in prefix position two address-ofs.
    assert_eq!(expr("**pp"), "(* (* pp))");
    assert_eq!(expr("a * *p"), "(* a (* p))");
    assert_eq!(expr("a**p"), "(* a (* p))");
    assert_eq!(expr("&&x"), "(& (& x))");
    assert_eq!(expr("a && &x == b"), "(&& a (== (& x) b))");
    parse_err_contains("fn f() { +x; }", "unary '+' is not supported");
}

#[test]
fn test_comparisons_do_not_chain() {
    parse_err_contains(
        "fn f() { a < b < c; }",
        "comparison operators cannot be chained",
    );
    parse_err_contains(
        "fn f() { a == b == c; }",
        "comparison operators cannot be chained",
    );
    parse_err_contains(
        "fn f() { a < b == true; }",
        "comparison operators cannot be chained",
    );
    assert_eq!(expr("(a < b) == c"), "(== (< a b) c)");
    assert_eq!(expr("a < b && b < c"), "(&& (< a b) (< b c))");
}

#[test]
fn test_postfix() {
    assert_eq!(
        expr("foo().bar[0].baz"),
        "(. (index (. (call foo) bar) 0) baz)"
    );
    assert_eq!(expr("foo(1, 2,)"), "(call foo 1 2)");
    assert_eq!(expr("t.0.1"), "(. (. t 0) 1)");
    assert_eq!(expr("(s.f)(x)"), "(call (. s f) x)");
    parse_err_contains("fn f() { s.f(x); }", "methods are not supported yet");
    parse_err_contains("fn f() { x?; }", "'?' is reserved for future use");
}

#[test]
fn test_literals() {
    assert_eq!(
        expr("(1, 2.5, 'a', 1u8, 2f32, 3.5f64, true, (), \"hi\", c\"cs\")"),
        "(tuple 1 2.5 'a' 1u8 2.0f32 3.5f64 true () \"hi\" c\"cs\")"
    );
    assert_eq!(expr("(1,)"), "(tuple 1)");
    assert_eq!(expr("[1, 2, 3,]"), "[1 2 3]");
    assert_eq!(expr("[]"), "[]");
    assert_eq!(expr("[0; N + 1]"), "[0; (+ N 1)]");
    assert_eq!(expr("P { x: 1, y: Q { z: 2 } }"), "(P x: 1 y: (Q z: 2))");
    parse_err_contains("fn f() { _; }", "'_' can only be used in patterns");
}

// ---- Control flow ----

#[test]
fn test_if_else_if() {
    assert_eq!(
        expr("if a { 1 } else if b { 2 } else { 3 }"),
        "(if a {1} {(if b {2} {3})})"
    );
    assert_eq!(
        expr("if a { 1 } else if b { 2 }"),
        "(if a {1} {(if b {2})})"
    );
}

#[test]
fn test_struct_literal_restriction() {
    // In a condition `Name {` starts the body ...
    assert_eq!(expr("if a { 1; }"), "(if a {1;})");
    assert_eq!(expr("while x { }"), "(while x {})");
    // ... but not inside parentheses, brackets, braces or arguments.
    assert_eq!(expr("if f(P { x: 1 }) { }"), "(if (call f (P x: 1)) {})");
    assert_eq!(
        expr("if (P { x: 1 }).x == 1 { }"),
        "(if (== (. (P x: 1) x) 1) {})"
    );
    assert_eq!(
        expr("if a[P { x: 1 }.x] { }"),
        "(if (index a (. (P x: 1) x)) {})"
    );
    assert_eq!(
        expr("if { P { x: 1 } }.x == 1 { }"),
        "(if (== (. {(P x: 1)} x) 1) {})"
    );
}

#[test]
fn test_loops() {
    assert_eq!(expr("loop { break; }"), "(loop {(break);})");
    assert_eq!(
        expr("while i < 10 { i += 1; }"),
        "(while (< i 10) {(+= i 1);})"
    );
    assert_eq!(expr("for i in 0..n { }"), "(for i (.. 0 n) {})");
    assert_eq!(
        expr("for mut i in a..=b + 1 { }"),
        "(for mut i (..= a (+ b 1)) {})"
    );
    assert_eq!(expr("for _ in 0..3 { }"), "(for _ (.. 0 3) {})");
    assert_eq!(
        expr("outer: loop { inner: while c { continue :outer; break :inner; } }"),
        "(loop :outer {(while :inner c {(continue :outer); (break :inner);})})"
    );
    assert_eq!(
        expr("let x = loop { break 5; };"),
        "(let x (loop {(break 5);}));"
    );
    assert_eq!(expr("break :outer x + 1"), "(break :outer (+ x 1))");
    parse_err_contains("fn f() { a..b..c; }", "range operators cannot be chained");
}

#[test]
fn test_return_break_continue_are_expressions() {
    assert_eq!(expr("return"), "(return)");
    assert_eq!(expr("return 1 + 2"), "(return (+ 1 2))");
    assert_eq!(
        body("let v = if c { 1 } else { return 0; }; v"),
        "{(let v (if c {1} {(return 0);})); v}"
    );
    assert_eq!(
        expr("if c { return } else { continue }"),
        "(if c {(return)} {(continue)})"
    );
    assert_eq!(expr("x || return"), "(|| x (return))");
}

#[test]
fn test_reserved_keywords() {
    for kw in [
        "enum", "match", "impl", "trait", "pub", "mod", "use", "self", "Self", "super", "where",
        "unsafe", "defer", "union", "dyn", "move",
    ] {
        parse_err_contains(
            &format!("fn f() {{ let {} = 1; }}", kw),
            "is a reserved keyword",
        );
    }
    parse_err_contains("fn f() { a => b; }", "'=>' is reserved for future use");
    parse_err_contains("fn f() { #x; }", "'#' is reserved for future use");
    parse_err_contains("fn f() { a::b; }", "'::' is reserved for future use");
    parse_err_contains("fn f() { @x; }", "'@' is reserved for future use");
}

// ---- Error recovery ----

#[test]
fn test_reports_independent_errors() {
    let src = r#"
            fn a() { let x = ; }
            fn b() { foo(1, 2; let ok = 1; }
            struct S { x i64 }
            fn c() -> { 1 }
            fn d() {
                let y = 1 +;
                let z = (2;
                if y < 1 { } else { let w = ) ; }
            }
            fn e() -> i64 { 1 }
        "#;
    let errors = parse_errs(src);
    assert_eq!(errors.len(), 7, "{:#?}", errors);
    assert!(errors[0].contains("expected expression, got ';'"));
    assert!(errors[1].contains("expected ')', got ';'"));
    assert!(errors[2].contains("expected ':', got 'i64'"));
    assert!(errors[3].contains("expected type, got '{'"));
    assert!(errors[4].contains("expected expression, got ';'"));
    assert!(errors[5].contains("expected ')', got ';'"));
    assert!(errors[6].contains("expected expression, got ')'"));
}

#[test]
fn test_recovery_keeps_parsing_after_missing_brace() {
    let errors = parse_errs("fn a() { let x = 1;\nfn b() { let y = ; }");
    assert_eq!(errors.len(), 2, "{:#?}", errors);
    assert!(errors[0].contains("expected '}' before 'fn'"));
    assert!(errors[1].contains("expected expression, got ';'"));
}

#[test]
fn test_error_statements_are_kept() {
    let mut parser = Parser::new(
        crate::lexer::Lexer::new("fn f() { let = 1; g(); }")
            .tokenize()
            .unwrap(),
    );
    let program = parser.parse_program();
    assert_eq!(parser.errors.len(), 1);
    let Item::Function(f) = &program.items[0] else {
        panic!()
    };
    assert_eq!(block(&f.body), "{<error>; (call g);}");
}

#[test]
fn test_expression_ids_are_dense() {
    let p = parse_ok("fn f() -> i64 { let x = 1 + 2; x * (3 - 4) }");
    assert_eq!(p.expr_count, 8);
}

#[test]
fn test_comprehensive_program_parses() {
    parse_ok(
        r#"
            struct Vec2 { x: f64, y: f64 }
            extern fn sqrt(x: f64) -> f64;
            extern fn printf(fmt: *u8, ...) -> i32;
            const SCALE: f64 = 2.0;

            fn length(v: Vec2) -> f64 {
                let sq = v.x * v.x + v.y * v.y;
                sqrt(sq)
            }

            fn abs(x: i32) -> i32 {
                if x < 0 { -x } else { x }
            }

            fn fib(n: i32) -> i32 {
                if n <= 1 { return n; }
                fib(n - 1) + fib(n - 2)
            }

            fn main() -> i32 {
                let mut sum = 0;
                for i in 0..10 {
                    if i % 2 == 0 { continue; }
                    sum += i;
                }
                let mut i = 10;
                while i > 0 { i -= 1; }
                let found = outer: loop {
                    loop { break :outer 42; }
                };
                let p = Vec2 { x: 3.0, y: 4.0 };
                let (a, mut b) = (1, 2);
                b = a;
                let arr: [i32; 3] = [1, 2, 3];
                let c = 'a' as i32 + arr[0] + b;
                printf(c"%f %d %d\n", length(p) * SCALE, fib(10), c + found + sum);
                0
            }
            "#,
    );
}
