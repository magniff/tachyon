use crate::parser::ParserError;

use super::*;

pub fn parse_source(src: &str) -> Result<Program, ParserError> {
    crate::parser::parse(crate::lexer::Lexer::new(src).tokenize().unwrap())
        .map_err(|mut errors| errors.remove(0))
}

fn check_ok(src: &str) {
    let prog = parse_source(src).unwrap_or_else(|e| panic!("parse error: {}", e));
    if let Err(errs) = typecheck(&prog) {
        let msgs: Vec<_> = errs.iter().map(|e| e.to_string()).collect();
        panic!("type errors:\n{}\nsource: {}", msgs.join("\n"), src);
    }
}

fn check_err(src: &str) -> Vec<TypecheckerError> {
    let prog = parse_source(src).unwrap_or_else(|e| panic!("parse error: {}", e));
    match typecheck(&prog) {
        Ok(_) => panic!("expected type error for: {}", src),
        Err(errs) => errs,
    }
}

fn check_err_contains(src: &str, substr: &str) {
    let errs = check_err(src);
    let all_msgs: Vec<_> = errs.iter().map(|e| e.message.clone()).collect();
    assert!(
        all_msgs.iter().any(|m| m.contains(substr)),
        "expected error containing '{}', got: {:?}\nsource: {}",
        substr,
        all_msgs,
        src
    );
}

// Basic valid programs
#[test]
fn test_empty_program() {
    check_ok("");
}

#[test]
fn test_simple_function() {
    check_ok("fn main() {}");
}

#[test]
fn test_fn_return_type() {
    check_ok("fn main() -> i32 { 0 }");
}

#[test]
fn test_fn_return_unit_implicit() {
    check_ok("fn main() {}");
}

#[test]
fn test_fn_return_unit_explicit() {
    check_ok("fn main() -> () { () }");
}

// Let bindings and type inference
#[test]
fn test_let_infer_int() {
    check_ok("fn main() { let x = 42; }");
}

#[test]
fn test_let_annotated() {
    check_ok("fn main() { let x: i32 = 42; }");
}

#[test]
fn test_let_annotated_u8() {
    check_ok("fn main() { let x: u8 = 255; }");
}

#[test]
fn test_let_u8_overflow() {
    check_err_contains("fn main() { let x: u8 = 256; }", "does not fit");
}

#[test]
fn test_let_i8_overflow() {
    check_err_contains("fn main() { let x: i8 = 128; }", "does not fit");
}

#[test]
fn test_let_float_annotated() {
    check_ok("fn main() { let x: f32 = 3.14; }");
}

#[test]
fn test_let_int_in_float_context() {
    check_err("fn main() { let x: f64 = 42; }");
}

#[test]
fn test_let_bool() {
    check_ok("fn main() { let x = true; let y = false; }");
}

// String literals
#[test]
fn test_string_literal_type() {
    // String is (*u8, u64), so accessing .1 gives u64
    check_ok(
        r#"
            fn main() -> u64 {
                let s = "hello";
                s.1
            }
        "#,
    );
}

#[test]
fn test_string_as_tuple_param() {
    check_ok(
        r#"
            fn get_len(s: (*u8, u64)) -> u64 { s.1 }
            fn main() -> u64 { get_len("Alice") }
        "#,
    );
}

// Arithmetic and operators
#[test]
fn test_arithmetic() {
    check_ok("fn main() { let x: i32 = 1; let y: i32 = 2; let z = x + y; }");
}

#[test]
fn test_arithmetic_type_mismatch() {
    check_err_contains(
        "fn main() { let x: i32 = 1; let y: i64 = 2; let z = x + y; }",
        "expected 'i32', got 'i64'",
    );
}

#[test]
fn test_comparison() {
    check_ok("fn main() { let x: i32 = 1; let b = x < 2; }");
}

#[test]
fn test_logical() {
    check_ok("fn main() { let b = true && false || true; }");
}

#[test]
fn test_logical_non_bool() {
    check_err_contains(
        "fn main() { let x = 1 && 2; }",
        "logical operator requires bool",
    );
}

#[test]
fn test_bitwise() {
    check_ok("fn main() { let x: u32 = 0xFF; let y = x & 0x0F; }");
}

#[test]
fn test_bitwise_on_float() {
    check_err_contains(
        "fn main() { let x: f64 = 1.0; let y = x & 1.0; }",
        "bitwise operator requires integer",
    );
}

#[test]
fn test_shift() {
    check_ok("fn main() { let x: u32 = 1; let y = x << 4; }");
    check_ok("fn main() { let x: u64 = 256; let y = x >> 2; }");
}

#[test]
fn test_shift_different_rhs_type() {
    // RHS type doesn't need to match LHS — u64 << u8 is fine
    check_ok("fn main() { let x: u64 = 1; let s: u8 = 4; let y = x << s; }");
}

#[test]
fn test_shift_on_float() {
    check_err_contains(
        "fn main() { let x: f64 = 1.0; let y = x << 1; }",
        "shift operator requires integer",
    );
}

#[test]
fn test_shift_assign() {
    check_ok("fn main() { let mut x: u32 = 1; x <<= 4; x >>= 2; }");
}

#[test]
fn test_shift_assign_on_float() {
    check_err_contains(
        "fn main() { let mut x: f64 = 1.0; x <<= 1; }",
        "shift assignment requires integer",
    );
}

#[test]
fn test_double_star_is_two_derefs() {
    // `**` is not an operator: `x ** 3` dereferences `3`.
    check_err_contains(
        "fn main() { let x: i32 = 2; let y = x ** 3; }",
        "cannot deref non-pointer type",
    );
    check_ok("fn f(pp: **i64) -> i64 { **pp }");
}

// Unary operators
#[test]
fn test_neg() {
    check_ok("fn main() { let x: i32 = 5; let y = -x; }");
}

#[test]
fn test_not() {
    check_ok("fn main() { let x = !true; }");
}

#[test]
fn test_bitnot() {
    check_ok("fn main() { let x: u32 = 0xFF; let y = ~x; }");
}

#[test]
fn test_bitnot_on_bool() {
    check_err_contains(
        "fn main() { let x = ~true; }",
        "bitwise NOT requires integer",
    );
}

#[test]
fn test_deref() {
    check_ok("fn main() { let x: i32 = 42; let p = &x; let y = *p; }");
}

#[test]
fn test_addr_of() {
    check_ok("fn main() { let x: i32 = 42; let p = &x; }");
}

#[test]
fn test_addr_of_non_lvalue() {
    check_err_contains(
        "fn main() { let p = &42; }",
        "cannot take address of non-lvalue",
    );
}

// Cast
#[test]
fn test_cast_int_to_float() {
    check_ok("fn main() { let x: i32 = 42; let y = x as f64; }");
}

#[test]
fn test_cast_float_to_int() {
    check_ok("fn main() { let x: f64 = 3.14; let y = x as i32; }");
}

#[test]
fn test_cast_int_widening() {
    check_ok("fn main() { let x: i32 = 42; let y = x as i64; }");
}

#[test]
fn test_cast_bool_to_int() {
    check_ok("fn main() { let b = true; let x = b as i32; }");
}

#[test]
fn test_cast_ptr_to_int() {
    check_ok("fn main() { let x: i32 = 0; let p = &x; let n = p as u64; }");
}

#[test]
fn test_cast_invalid() {
    check_err_contains(
        "fn main() { let b = true; let x = b as f64; }",
        "cannot cast",
    );
}

// Function calls
#[test]
fn test_call_basic() {
    check_ok("fn foo() -> i32 { 42 } fn main() { let x = foo(); }");
}

#[test]
fn test_call_with_args() {
    check_ok("fn add(a: i32, b: i32) -> i32 { a + b } fn main() { let x = add(1, 2); }");
}

#[test]
fn test_call_arg_type_push() {
    // Literal 1 should be checked against i32 parameter type
    check_ok("fn foo(x: i32) {} fn main() { foo(1); }");
}

#[test]
fn test_call_wrong_arg_count() {
    check_err_contains(
        "fn foo(a: i32) {} fn main() { foo(1, 2); }",
        "expects 1 arguments, got 2",
    );
}

#[test]
fn test_call_too_few_args() {
    check_err_contains(
        "fn foo(a: i32, b: i32) {} fn main() { foo(1); }",
        "expects 2 arguments, got 1",
    );
}

#[test]
fn test_call_variadic_too_few_args() {
    check_err_contains(
        "extern fn printf(f: *u8, ...) -> i32; fn main() { printf(); }",
        "expects at least 1 arguments, got 0",
    );
}

#[test]
fn test_call_variadic_extra_args_checked() {
    check_err_contains(
        r#"extern fn printf(f: *u8, ...) -> i32; fn main() { printf("%d".0, nope); }"#,
        "undefined variable",
    );
}

#[test]
fn test_call_variadic_rejects_compound() {
    check_err_contains(
        r#"extern fn printf(f: *u8, ...) -> i32; fn main() { printf("%s".0, "hi"); }"#,
        "variadic argument",
    );
}

#[test]
fn test_call_variadic_scalars_ok() {
    check_ok(
        r#"extern fn printf(f: *u8, ...) -> i32;
            fn main() { let x: u8 = 1; let y: f32 = 2.0; printf("%d %f".0, x, y, &x); }"#,
    );
}

#[test]
fn test_call_wrong_arg_type() {
    check_err_contains(
        "fn foo(a: i32) {} fn main() { let b = true; foo(b); }",
        "expected 'i32', got 'bool'",
    );
}

#[test]
fn test_call_extern() {
    check_ok(
        r#"
            extern fn puts(s: *u8) -> i32;
            fn main() { let x: i32 = 42; let p = &x as *u8; puts(p); }
        "#,
    );
}

// Structs
#[test]
fn test_struct_basic() {
    check_ok(
        r#"
            struct Point { x: i32, y: i32 }
            fn main() {
                let p = Point { x: 10, y: 20 };
            }
        "#,
    );
}

#[test]
fn test_struct_field_access() {
    check_ok(
        r#"
            struct Point { x: i32, y: i32 }
            fn main() -> i32 {
                let p = Point { x: 10, y: 20 };
                p.x + p.y
            }
        "#,
    );
}

#[test]
fn test_struct_missing_field() {
    check_err_contains(
        "struct Point { x: i32, y: i32 } fn main() { let p = Point { x: 10 }; }",
        "missing field 'y'",
    );
}

#[test]
fn test_struct_extra_field() {
    check_err_contains(
        "struct Point { x: i32 } fn main() { let p = Point { x: 1, y: 2 }; }",
        "unknown field 'y'",
    );
}

#[test]
fn test_struct_field_type_check() {
    // Literal should be checked against field type
    check_ok(
        r#"
            struct Foo { val: u8 }
            fn main() { let f = Foo { val: 255 }; }
        "#,
    );
}

#[test]
fn test_struct_field_type_overflow() {
    check_err_contains(
        "struct Foo { val: u8 } fn main() { let f = Foo { val: 256 }; }",
        "does not fit",
    );
}

#[test]
fn test_struct_nonexistent_field_access() {
    check_err_contains(
        "struct Point { x: i32 } fn main() { let p = Point { x: 1 }; let q = p.y; }",
        "no field 'y'",
    );
}

#[test]
fn test_duplicate_struct() {
    check_err_contains("struct A {} struct A {}", "duplicate struct");
}

#[test]
fn test_recursive_struct_error() {
    check_err_contains("struct Node { next: Node }", "infinite size");
}

#[test]
fn test_recursive_struct_via_pointer_ok() {
    check_ok("struct Node { val: i32, next: *Node }");
}

// Arrays
#[test]
fn test_array_literal() {
    check_ok("fn main() { let arr = [1, 2, 3]; }");
}

#[test]
fn test_array_annotated() {
    check_ok("fn main() { let arr: [i32; 3] = [1, 2, 3]; }");
}

#[test]
fn test_array_size_mismatch() {
    check_err_contains(
        "fn main() { let arr: [i32; 3] = [1, 2]; }",
        "2 elements, expected 3",
    );
}

#[test]
fn test_array_repeat() {
    check_ok("fn main() { let arr = [0; 10]; }");
}

#[test]
fn test_array_index() {
    check_ok("fn main() { let arr = [1, 2, 3]; let x = arr[0]; }");
}

#[test]
fn test_array_index_non_integer() {
    check_err_contains(
        "fn main() { let arr = [1, 2, 3]; let x = arr[true]; }",
        "index must be integer",
    );
}

// Tuples
#[test]
fn test_tuple_literal() {
    check_ok("fn main() { let t = (1, true); }");
}

#[test]
fn test_tuple_annotated() {
    check_ok("fn main() { let t: (i32, bool) = (42, true); }");
}

#[test]
fn test_tuple_field() {
    check_ok("fn main() { let t = (1, true); let x = t.0; let b = t.1; }");
}

#[test]
fn test_tuple_field_out_of_range() {
    check_err_contains("fn main() { let t = (1, 2); let x = t.5; }", "out of range");
}

#[test]
fn test_tuple_arity_mismatch() {
    check_err_contains(
        "fn main() { let t: (i32, i32) = (1, 2, 3); }",
        "3 elements, expected 2",
    );
}

// If expressions
#[test]
fn test_if_else_same_type() {
    check_ok("fn main() -> i32 { if true { 1 } else { 2 } }");
}

#[test]
fn test_if_else_different_types() {
    check_err_contains(
        "fn main() { let x = if true { 1 } else { true }; }",
        "different types",
    );
}

#[test]
fn test_if_no_else_unit() {
    check_ok("fn main() { if true { let x = 1; }; }");
}

#[test]
fn test_if_no_else_non_unit() {
    check_err_contains(
        "fn main() { let x = if true { 1 }; }",
        "if without else must have type '()'",
    );
}

#[test]
fn test_if_condition_non_bool() {
    check_err_contains(
        "fn main() { if 42 { let x = 1; }; }",
        "expected 'bool', got 'i64'",
    );
}

// Blocks
#[test]
fn test_block_expression() {
    check_ok("fn main() -> i32 { { let x: i32 = 1; x + 1 } }");
}

#[test]
fn test_block_no_tail_is_unit() {
    check_ok("fn main() { { let x = 1; }; }");
}

// Loops
#[test]
fn test_loop_basic() {
    check_ok("fn main() { loop { break; } }");
}

#[test]
fn test_break_outside_loop() {
    check_err_contains("fn main() { break; }", "break outside of loop");
}

#[test]
fn test_continue_outside_loop() {
    check_err_contains("fn main() { continue; }", "continue outside of loop");
}

#[test]
fn test_nested_loops() {
    check_ok("fn main() { loop { loop { break; } break; } }");
}

// Return
#[test]
fn test_return_value() {
    check_ok("fn main() -> i32 { return 0; }");
}

#[test]
fn test_return_void() {
    check_ok("fn main() { return; }");
}

#[test]
fn test_return_type_mismatch() {
    check_err_contains(
        "fn main() -> i32 { return true; }",
        "expected 'i32', got 'bool'",
    );
}

#[test]
fn test_empty_return_in_non_void() {
    check_err_contains("fn main() -> i32 { return; }", "empty return");
}

// Assignments
#[test]
fn test_simple_assign() {
    check_ok("fn main() { let mut x: i32 = 0; x = 42; }");
}

#[test]
fn test_compound_assign() {
    check_ok("fn main() { let mut x: i32 = 0; x += 1; x -= 2; }");
}

#[test]
fn test_compound_assign_non_numeric() {
    check_err_contains(
        "fn main() { let mut x = true; x += true; }",
        "compound assignment requires numeric",
    );
}

#[test]
fn test_assign_type_mismatch() {
    check_err_contains(
        "fn main() { let mut x: i32 = 0; x = true; }",
        "expected 'i32', got 'bool'",
    );
}

#[test]
fn test_assign_through_deref() {
    check_ok(
        r#"
            fn main() {
                let x: i32 = 0;
                let p = &x;
                *p = 42;
            }
        "#,
    );
}

#[test]
fn test_assign_struct_field() {
    check_ok(
        r#"
            struct Point { x: i32, y: i32 }
            fn main() {
                let mut p = Point { x: 0, y: 0 };
                p.x = 10;
            }
        "#,
    );
}

#[test]
fn test_assign_array_index() {
    check_ok(
        r#"
            fn main() {
                let mut arr = [0, 0, 0];
                arr[1] = 42;
            }
        "#,
    );
}

// Pointer types
#[test]
fn test_pointer_type() {
    check_ok("fn foo(p: *i32) -> i32 { *p }");
}

#[test]
fn test_double_pointer() {
    check_ok(
        r#"
            fn main() {
                let x: i32 = 42;
                let p = &x;
                let pp = &p;
                let val = **pp;
            }
        "#,
    );
}

// Function pointers
#[test]
fn test_fn_ptr_type() {
    check_ok(
        r#"
            fn add(a: i32, b: i32) -> i32 { a + b }
            fn apply(f: fn(i32, i32) -> i32, x: i32, y: i32) -> i32 {
                f(x, y)
            }
        "#,
    );
}

// Duplicate function
#[test]
fn test_duplicate_function() {
    check_err_contains("fn foo() {} fn foo() {}", "duplicate function");
}

// Unknown type
#[test]
fn test_unknown_type() {
    check_err_contains("fn foo(x: Nonexistent) {}", "unknown type");
}

// Body type mismatch
#[test]
fn test_body_type_mismatch() {
    check_err_contains("fn main() -> i32 { true }", "expected 'i32', got 'bool'");
}

// Comprehensive program
#[test]
fn test_comprehensive() {
    check_ok(
        r#"
            struct Vec2 { x: f64, y: f64 }

            extern fn sqrt(x: f64) -> f64;

            fn length(v: Vec2) -> f64 {
                let sq = v.x * v.x + v.y * v.y;
                sqrt(sq)
            }

            fn dot(a: Vec2, b: Vec2) -> f64 {
                a.x * b.x + a.y * b.y
            }

            fn abs(x: i32) -> i32 {
                if x < 0 { -x } else { x }
            }

            fn fib(n: i32) -> i32 {
                let mut a: i32 = 0;
                let mut b: i32 = 1;
                let mut i: i32 = 0;
                loop {
                    if i == n { break; };
                    let temp = b;
                    b = a + b;
                    a = temp;
                    i += 1;
                }
                a
            }

            fn main() -> i32 {
                let v = Vec2 { x: 3.0, y: 4.0 };
                let len = length(v);

                let arr: [i32; 5] = [1, 2, 3, 4, 5];
                let mut sum: i32 = 0;
                let mut i: i32 = 0;
                loop {
                    if i == 5 { break; };
                    sum += arr[i];
                    i += 1;
                }

                let pair: (i32, i32) = (10, 20);
                let first = pair.0;
                let answer = fib(10);
                let ptr = &sum;
                let val = *ptr;
                let mask = 0xFF & (0b1010 | 0x0F);
                let big = 2 * 3 * 2;
                let cast_val = 42 as f64;
                let flag = true && !false || 1 != 2;
                0
            }
        "#,
    );
}

#[test]
fn test_string_comprehensive() {
    check_ok(
        r#"
            fn get_len(s: (*u8, u64)) -> u64 {
                s.1
            }
            fn main() -> u64 {
                let name = "Alice";
                get_len(name)
            }
        "#,
    );
}

// usize alias
#[test]
fn test_usize_alias() {
    check_ok("fn main() { let x: usize = 42; }");
}

// Bidirectional literal checking through nested structures
#[test]
fn test_literal_push_through_array() {
    // Without annotation, elements default to i64.
    // With annotation, 1/2/3 are checked as u8.
    check_ok("fn main() { let arr: [u8; 3] = [1, 2, 3]; }");
}

#[test]
fn test_literal_push_through_tuple() {
    check_ok("fn main() { let t: (u8, f32) = (42, 3.14); }");
}

#[test]
fn test_literal_push_through_fn_args() {
    // Function param types push into literal arguments
    check_ok("fn foo(a: u16, b: f32) {} fn main() { foo(1000, 2.5); }");
}

// Edge cases
#[test]
fn test_empty_struct_constructor() {
    check_ok("struct Empty {} fn main() { let e = Empty {}; }");
}

#[test]
fn test_nested_struct() {
    check_ok(
        r#"
                struct Inner { val: i32 }
                struct Outer { inner: Inner }
                fn main() -> i32 {
                    let o = Outer { inner: Inner { val: 42 } };
                    o.inner.val
                }
            "#,
    );
}

#[test]
fn test_mutual_recursive_structs() {
    check_err_contains("struct A { b: B } struct B { a: A }", "infinite size");
}

#[test]
fn test_mutual_recursive_via_pointer_ok() {
    check_ok("struct A { b: *B } struct B { a: *A }");
}

#[test]
fn test_deref_non_pointer() {
    check_err_contains(
        "fn main() { let x: i32 = 42; let y = *x; }",
        "cannot deref non-pointer",
    );
}

#[test]
fn test_call_non_function() {
    check_err_contains(
        "fn main() { let x: i32 = 42; x(1); }",
        "cannot call non-function",
    );
}

#[test]
fn test_index_non_array() {
    check_err_contains(
        "fn main() { let x: i32 = 42; let y = x[0]; }",
        "cannot index type",
    );
}

#[test]
fn test_field_on_non_struct() {
    check_err_contains(
        "fn main() { let x: i32 = 42; let y = x.foo; }",
        "cannot access field",
    );
}

#[test]
fn test_undefined_variable() {
    check_err_contains("fn main() { let x = y; }", "undefined variable 'y'");
}

#[test]
fn test_scope_isolation() {
    check_err_contains(
        "fn main() { { let x: i32 = 1; }; let y = x; }",
        "undefined variable 'x'",
    );
}

#[test]
fn test_shadowing() {
    check_ok(
        r#"
            fn main() -> bool {
                let x: i32 = 42;
                let x = true;
                x
            }
        "#,
    );
}

#[test]
fn test_literal_takes_context_type() {
    check_ok("fn main() { let x: u8 = 1 + 2; let y: i8 = -128; let z: i32 = 0 - 7; }");
    check_ok("fn main() { let x: u8 = 3; let y = 1 + x; let b = 0 == x; let c: u8 = y; }");
    check_ok("fn main() { let x: u32 = (1 << 31) | 5; let f: f32 = -1.5; }");
    check_err_contains("fn main() { let x: i8 = -129; }", "-129 does not fit");
    check_err_contains(
        "fn main() { let a: u32 = 1; let x: u64 = a + 1; }",
        "expected 'u64', got 'u32'",
    );
}

#[test]
fn test_diverging_bodies() {
    check_ok("fn f(c: bool) -> i64 { if c { return 1; } else { return 2; }; }");
    check_ok("fn f() -> i64 { loop { return 1; } }");
    check_ok("fn f(c: bool) -> i64 { let x: i64 = if c { return 0; } else { 5 }; x }");
    check_err_contains(
        "fn f(c: bool) -> i64 { loop { if c { break; }; return 1; } }",
        "expected 'i64', got '()' (break without a value)",
    );
    check_err_contains(
        "fn f(c: bool) -> i64 { if c { return 1; }; }",
        "body has type '()'",
    );
    // a break inside a nested loop does not leave the outer one
    check_ok("fn f() -> i64 { loop { loop { break; } return 1; } }");
}

#[test]
fn test_block_without_tail_has_unit_type() {
    check_err_contains("fn main() { let x: i64 = {}; }", "expected 'i64', got '()'");
    check_err_contains(
        "fn main() { let x: i64 = if true { 1 } else { }; }",
        "expected 'i64', got '()'",
    );
}

#[test]
fn test_function_as_value() {
    check_ok(
        "fn g(x: i64) -> i64 { x } fn main() { let f: fn(i64) -> i64 = g; let y = f(1); let e = f == g; }",
    );
    check_err_contains(
        "extern fn printf(f: *u8, ...) -> i32; fn main() { let p = printf; }",
        "variadic function 'printf' cannot be used as a value",
    );
}

// ---- never type, loops, labels ----

#[test]
fn test_never_coerces_everywhere() {
    check_ok("fn f(c: bool) -> i64 { let x: i64 = if c { 1 } else { return 2 }; x }");
    check_ok("fn f() -> i64 { loop {} }");
    check_ok("fn f(c: bool) -> i64 { if c { return 1 } else { return 2 } }");
    check_ok("extern fn exit(c: i32) -> !; fn f() -> (i64, bool) { exit(1) }");
    check_ok("fn f() -> i64 { let x = return 3; }");
    check_ok("fn f() { let v: [i64; 2] = [1, loop { break 2; }]; }");
}

#[test]
fn test_loop_values() {
    check_ok("fn f() -> u8 { loop { break 200; } }");
    check_ok("fn f() -> i64 { outer: loop { loop { break :outer 1; } } }");
    check_err_contains(
        "fn f() -> i64 { loop { break true; } }",
        "expected 'i64', got 'bool'",
    );
    check_err_contains(
        "fn f(c: bool) { let x = loop { if c { break 1; } break; }; }",
        "break without a value",
    );
    check_err_contains(
        "fn f() { while true { break 1; } }",
        "only allowed in 'loop'",
    );
    check_err_contains(
        "fn f() { for i in 0..3 { continue :x; } }",
        "unknown loop label ':x'",
    );
    check_err_contains("fn f() { break; }", "break outside of loop");
}

#[test]
fn test_block_like_statement_must_be_unit() {
    check_err_contains(
        "fn f(c: bool) -> i64 { if c { 1 } else { 2 } 3 }",
        "expected '()', got 'i64'",
    );
    check_ok("fn f(c: bool) -> i64 { if c { 1 } else { 2 }; 3 }");
}

#[test]
fn test_for_ranges() {
    check_ok("fn f() { for i in 0u8..=255 { let x: u8 = i; } }");
    check_ok("fn f(n: u32) { for i in 0..n { let x: u32 = i; } }");
    check_err_contains(
        "fn f() { for i in 0.0..1.0 { } }",
        "range bounds must be integers",
    );
    check_err_contains("fn f() { let r = 1..2; }", "ranges can only be used");
}

// ---- constants, statics, aliases ----

fn const_value(src: &str, name: &str) -> ConstValue {
    let prog = parse_source(src).unwrap();
    let checked = typecheck(&prog).unwrap_or_else(|e| panic!("{:?}", e));
    checked.consts[name].value.clone()
}

#[test]
fn test_const_evaluation() {
    assert_eq!(
        const_value("const A: i64 = (1 << 10) - 24 / 3;", "A"),
        ConstValue::Int(1016)
    );
    assert_eq!(
        const_value("const A: u8 = 250 + 10;", "A"),
        ConstValue::Int(4)
    );
    assert_eq!(
        const_value("const A: i8 = 127 + 1;", "A"),
        ConstValue::Int(-128)
    );
    assert_eq!(
        const_value("const A: u32 = ~0u32 >> 4;", "A"),
        ConstValue::Int(0x0FFF_FFFF)
    );
    assert_eq!(
        const_value("const A: i64 = -7 % 3;", "A"),
        ConstValue::Int(-1)
    );
    assert_eq!(
        const_value("const A: f32 = 0.1;", "A"),
        ConstValue::Float(0.1f32 as f64)
    );
    assert_eq!(
        const_value("const A: i32 = 2.9 as i32;", "A"),
        ConstValue::Int(2)
    );
    assert_eq!(
        const_value(
            "const A: bool = B > 2 && B < 5; const B: u8 = 'a' - 94;",
            "A"
        ),
        ConstValue::Bool(true)
    );
    check_err_contains("const A: i64 = 1 / 0;", "division by zero");
    check_err_contains(
        "const A: i64 = B; const B: i64 = A;",
        "defined in terms of itself",
    );
    check_err_contains(
        "fn g() -> i64 { 1 } const A: i64 = g();",
        "not a compile-time constant",
    );
    check_err_contains(
        "const A: (i64, i64) = (1, 2);",
        "constants must be integers, floats or bool",
    );
}

#[test]
fn test_const_array_sizes() {
    check_ok(
        "const N: i64 = 4; fn f() { let a: [u8; N * 2] = [0; 8]; let b = [1; N]; let c: [i64; 4] = b; }",
    );
    check_err_contains(
        "fn f() { let a: [u8; 2 - 3] = []; }",
        "must not be negative",
    );
    check_err_contains(
        "fn f() { let a: [u8; 1.5] = []; }",
        "array length must be an integer",
    );
    check_err_contains(
        "fn f() { let a: [u8; 3] = [0; 4]; }",
        "array repeat count is 4, expected 3",
    );
}

#[test]
fn test_statics() {
    check_ok("static mut C: i64 = 0; fn f() { C += 1; let p = &C; }");
    check_ok(
        "struct P { a: i32, b: (u8, bool) } static S: P = P { b: (1, true), a: -1 }; fn f() -> i32 { S.a }",
    );
    check_err_contains(
        "static S: i64 = 0; fn f() { S = 1; }",
        "cannot assign to immutable static 'S'",
    );
    check_err_contains(
        "fn g() -> i64 { 1 } static S: i64 = g();",
        "not a compile-time constant",
    );
}

#[test]
fn test_type_aliases() {
    check_ok("type B = u8; type P = *B; type Arr = [P; 2]; fn f(a: Arr) -> B { *a[0] }");
    check_err_contains("type A = (A, i64);", "defined in terms of itself");
    check_err_contains("type A = Nope;", "unknown type 'Nope'");
    check_err_contains("type A = i64; struct A { x: i64 }", "duplicate");
}

// ---- literals, pointers, patterns ----

#[test]
fn test_char_and_suffixed_literals() {
    check_ok(
        "fn f() { let c = 'a'; let d: u8 = c; let e: i32 = 'b'; let s: i16 = -128i8 as i16; }",
    );
    check_ok("fn f() { let x = 1u8 + 2; let y: u8 = x; let z = 2f32 * 1.5; let w: f32 = z; }");
    check_err_contains("fn f() { let x = 300u8; }", "does not fit in type 'u8'");
    check_err_contains(
        "fn f() { let x = -129i8; }",
        "-129 does not fit in type 'i8'",
    );
    check_err_contains("fn f() { let x: f64 = 'a'; }", "expected 'f64', got 'u8'");
    check_ok("fn f() -> *u8 { c\"hi\" }");
}

#[test]
fn test_pointer_indexing() {
    check_ok("fn f(p: *i64, i: u8) -> i64 { p[i] = 1; let q: *i64 = &p[2]; p[0] + q[0] }");
    check_err_contains("fn f(p: *i64) -> i64 { p[1.0] }", "index must be integer");
}

#[test]
fn test_let_patterns() {
    check_ok("fn f() { let (a, (b, mut c), _) = (1, (true, 2.5), 3); c += 1.0; let x: bool = b; }");
    check_err_contains(
        "fn f() { let (a, b) = 1; }",
        "tuple pattern with 2 elements",
    );
    check_err_contains(
        "fn f() { let (a, b) = (1, 2, 3); }",
        "tuple pattern with 2 elements",
    );
    check_err_contains(
        "fn f() { let (a, b) = (1, 2); a = 3; }",
        "immutable variable 'a'",
    );
}

// ---- mutability ----

#[test]
fn test_mutability() {
    check_ok("fn f(mut n: i64) -> i64 { n -= 1; n }");
    check_ok("fn f() { let x = 1; let p = &x; *p = 2; }");
    check_ok("fn f() { let a = [1, 2]; let p = &a[0]; p[1] = 3; }");
    let errs = check_err("fn f() { let x = 1; x = 2; }");
    assert_eq!(
        errs[0].help.as_deref(),
        Some("make it mutable: `let mut x`")
    );
    let errs = check_err("fn f(n: i64) { n += 1; }");
    assert_eq!(
        errs[0].help.as_deref(),
        Some("make the parameter mutable: `mut n: i64`")
    );
    check_err_contains(
        "struct P { x: i64 } fn f() { let p = P { x: 1 }; p.x = 2; }",
        "immutable variable 'p'",
    );
    check_err_contains(
        "fn f() { let a = [[0; 2]; 2]; a[1][1] = 2; }",
        "immutable variable 'a'",
    );
    check_err_contains(
        "fn f() { for i in 0..3 { i += 1; } }",
        "immutable variable 'i'",
    );
    check_ok("fn f() { for mut i in 0..3 { i += 1; } }");
}

#[test]
fn test_assignment_targets() {
    check_err_contains(
        "struct P { x: i64 } fn mk() -> P { P { x: 1 } } fn f() { mk().x = 2; }",
        "invalid assignment target",
    );
    check_err_contains(
        "const N: i64 = 1; fn f() { N = 2; }",
        "cannot assign to constant 'N'",
    );
    check_err_contains(
        "fn g() {} fn f() { g = g; }",
        "cannot assign to function 'g'",
    );
    check_ok("fn f() { let mut x = 0; let u: () = (x = 1); }");
}

#[test]
fn test_local_shadows_function_in_calls() {
    check_ok(
        "fn g(x: i64) -> i64 { x } fn h(x: i64) -> i64 { x } fn f() -> i64 { let g = h; g(1) }",
    );
}
