
use super::*;
use crate::parser::{ParserError, Program};

pub fn parse_source(src: &str) -> Result<Program, ParserError> {
    crate::parser::parse(crate::lexer::Lexer::new(src).tokenize().unwrap())
        .map_err(|mut errors| errors.remove(0))
}

fn lower_ok(src: &str) -> IrProgram {
    let prog = parse_source(src).unwrap_or_else(|e| panic!("parse: {}", e));
    let checked =
        crate::typechecker::typecheck(&prog).unwrap_or_else(|e| panic!("typecheck: {:?}", e));
    lower(&prog, &checked)
}

fn ir_str(src: &str) -> String {
    print_ir(&lower_ok(src))
}

#[test]
fn test_empty_fn() {
    let s = ir_str("fn main() {}");
    assert!(s.contains("fn main()"));
    assert!(s.contains("ret"));
}
#[test]
fn test_return_int() {
    let s = ir_str("fn foo() -> i32 { 42 }");
    assert!(s.contains("const.i32 42"));
    assert!(s.contains("ret.i32"));
}
#[test]
fn test_let_return() {
    let s = ir_str("fn f() -> i32 { let x: i32 = 10; x }");
    assert!(s.contains("const.i32 10"));
}
#[test]
fn test_iadd() {
    let s = ir_str("fn f() -> i32 { let a: i32 = 3; let b: i32 = 4; a + b }");
    assert!(s.contains("iadd.i32"));
}
#[test]
fn test_fmul() {
    let s = ir_str("fn f() -> f64 { let a: f64 = 1.0; let b: f64 = 2.0; a * b }");
    assert!(s.contains("fmul.f64"));
}
#[test]
fn test_icmp() {
    let s = ir_str("fn f() -> bool { let a: i32 = 1; a < 2 }");
    assert!(s.contains("icmp.i32"));
}
#[test]
fn test_if_else() {
    let s = ir_str("fn f() -> i32 { if true { 1 } else { 2 } }");
    assert!(s.contains("br "));
}
#[test]
fn test_loop_break() {
    let s = ir_str("fn f() { let mut i: i32 = 0; loop { if i == 10 { break; }; i += 1; } }");
    assert!(s.contains("jmp bb"));
    assert!(s.contains("icmp"));
}
#[test]
fn test_struct() {
    let s = ir_str(
        "struct P { x: i32, y: i32 } fn f() -> i32 { let p = P { x: 10, y: 20 }; p.x + p.y }",
    );
    assert!(s.contains("memberptr"));
    assert!(s.contains("iadd.i32"));
}
#[test]
fn test_struct_return_uses_sret() {
    let prog = lower_ok(
        "struct P { x: i64, y: i64 } fn mk(a: i64) -> P { P { x: a, y: a } } \
             fn main() -> i64 { let p = mk(1); p.x }",
    );
    let mk = prog.functions.iter().find(|f| f.name == "mk").unwrap();
    // Hidden result pointer comes first, then the declared parameter
    assert_eq!(mk.params.len(), 2);
    assert_eq!(mk.params[0].1, IRType::Ptr);
    // The callee writes into the caller's slot instead of its own frame
    assert!(mk.slots.iter().all(|s| s.size != 16));
    let main = prog.functions.iter().find(|f| f.name == "main").unwrap();
    let call = main
        .blocks
        .iter()
        .flat_map(|b| &b.instructions)
        .find_map(|i| match i {
            Inst::Call { func, dst, args } if func == "mk" => Some((dst, args)),
            _ => None,
        })
        .unwrap();
    assert!(call.0.is_none());
    assert_eq!(call.1.len(), 2);
}
#[test]
fn test_variadic_promotes_f32_and_small_ints() {
    let prog = lower_ok(
        "extern fn printf(f: *u8, ...) -> i32; \
             fn main() { let x: f32 = 1.0; let y: u8 = 2; printf(\"\".0, x, y); }",
    );
    let main = prog.functions.iter().find(|f| f.name == "main").unwrap();
    let args = main
        .blocks
        .iter()
        .flat_map(|b| &b.instructions)
        .find_map(|i| match i {
            Inst::Call { func, args, .. } if func == "printf" => Some(args),
            _ => None,
        })
        .unwrap();
    let tys: Vec<IRType> = args.iter().map(|(_, t)| *t).collect();
    assert_eq!(tys, vec![IRType::Ptr, IRType::F64, IRType::I32]);
}
#[test]
fn test_array() {
    let s = ir_str("fn f() -> i64 { let a = [1, 2, 3]; a[1] }");
    assert!(s.contains("indexptr"));
}
#[test]
fn test_string() {
    let s = ir_str(r#"fn f() { let s = "hello"; }"#);
    assert!(s.contains("__str0"));
    assert!(s.contains("strptr"));
}
#[test]
fn test_call() {
    let s = ir_str("fn add(a: i32, b: i32) -> i32 { a + b } fn f() -> i32 { add(3, 4) }");
    assert!(s.contains("call.i32 add"));
}
#[test]
fn test_extern() {
    let s = ir_str("extern fn puts(s: *u8) -> i32; fn f() {}");
    assert!(s.contains("extern fn puts"));
}
#[test]
fn test_short_circuit_and() {
    let s = ir_str("fn f() -> bool { true && false }");
    assert!(s.contains("br ")); // must have conditional branch for short-circuit
}
#[test]
fn test_short_circuit_or() {
    let s = ir_str("fn f() -> bool { false || true }");
    assert!(s.contains("br "));
}
#[test]
fn test_shift() {
    let s = ir_str("fn f() -> i32 { let x: i32 = 1; x << 4 }");
    assert!(s.contains("ishl.i32"));
}
#[test]
fn test_cast() {
    let s = ir_str("fn f() -> f64 { let x: i32 = 42; x as f64 }");
    assert!(s.contains("itof"));
}
#[test]
fn test_unary_neg() {
    let s = ir_str("fn f() -> i32 { let x: i32 = 5; -x }");
    assert!(s.contains("ineg.i32"));
}
#[test]
fn test_bool_not() {
    let s = ir_str("fn f() -> bool { !true }");
    assert!(s.contains("bnot"));
}
#[test]
fn test_pointer_deref() {
    let s = ir_str("fn f() -> i32 { let x: i32 = 42; let p = &x; *p }");
    assert!(s.contains("slotaddr"));
    assert!(s.contains("load.i32"));
}
#[test]
fn test_tuple() {
    let s = ir_str("fn f() -> i32 { let t: (i32, i64) = (1, 2); t.0 }");
    assert!(s.contains("memberptr"));
    assert!(s.contains("load.i32"));
}
#[test]
fn test_compound_assign() {
    let s = ir_str("fn f() { let mut x: i32 = 1; x += 10; }");
    assert!(s.contains("iadd.i32"));
    assert!(s.contains("store.i32"));
}
#[test]
fn test_return_stmt() {
    let s = ir_str("fn f() -> i32 { return 42; }");
    assert!(s.contains("const.i32 42"));
    assert!(s.contains("ret.i32"));
}
#[test]
fn test_nested_blocks() {
    let s = ir_str("fn f() -> i32 { let x: i32 = { let y: i32 = 5; y + 1 }; x }");
    assert!(s.contains("iadd.i32"));
}
#[test]
fn test_float_mod_calls_fmod() {
    let s = ir_str("fn f() -> f64 { let x: f64 = 7.0; x % 3.0 }");
    assert!(s.contains("call") && s.contains("fmod"));
}
#[test]
fn test_continue() {
    let s = ir_str(
        "fn f() { let mut i: i32 = 0; loop { i += 1; if i == 5 { continue; }; if i == 10 { break; }; } }",
    );
    assert!(s.contains("jmp bb"));
}
#[test]
fn test_array_repeat() {
    let s = ir_str("fn f() -> i64 { let a = [0; 5]; a[3] }");
    assert!(s.contains("indexptr"));
}
