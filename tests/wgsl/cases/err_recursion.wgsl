// ERROR: error wgsl.recursion: 'f' calls itself, directly or through other functions
fn f(x: i32) -> i32 {
    if x <= 0 {
        return 0;
    }
    return g(x - 1);
}
fn g(x: i32) -> i32 {
    return f(x);
}
@compute @workgroup_size(1)
fn main() {
    _ = f(3);
}
