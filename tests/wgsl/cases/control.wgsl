// Control flow: loops with continuing and break-if, switch with several
// selectors per case, for and while, continue inside a switch, calls with
// pointer parameters, short-circuit operators with calls.
// JOB: dispatch 2 1 1
// JOB: buffer 0 0 1024

@group(0) @binding(0) var<storage, read_write> out: array<i32>;

var<private> calls: i32;

fn bump(p: ptr<function, i32>, by: i32) -> i32 {
    *p += by;
    calls += 1;
    return *p;
}

fn is_odd(x: i32) -> bool {
    calls += 1;
    return (x & 1) == 1;
}

fn classify(x: i32) -> i32 {
    switch x {
        case 0, 1: {
            return 10;
        }
        case 2 {
            return 20;
        }
        case 3, default: {
            return 30;
        }
    }
}

@compute @workgroup_size(4)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let base = i32(gid.x) * 32;
    var acc = 0;
    var i = 0;
    loop {
        if i >= 10 {
            break;
        }
        if i % 3 == 0 {
            i += 1;
            continue;
        }
        acc += i;
        continuing {
            i += 1;
        }
    }
    out[base] = acc;
    var j = 0;
    var k = 0;
    loop {
        k += j;
        continuing {
            j += 1;
            break if j > 5;
        }
    }
    out[base + 1] = k;
    var s = 0;
    for (var x = 0; x < 8; x++) {
        switch x {
            case 1, 3: {
                continue;
            }
            case 6: {
                break;
            }
            default: {
                s += x;
            }
        }
        s += 100;
    }
    out[base + 2] = s;
    var w = 0;
    while w < 5 {
        w += 2;
    }
    out[base + 3] = w;
    var cell = 5;
    let r = bump(&cell, 3);
    out[base + 4] = r * 10 + cell;
    out[base + 5] = classify(0) + classify(2) + classify(3) + classify(9) + classify(-1);
    calls = 0;
    var t = 0;
    if is_odd(i32(gid.x)) && is_odd(3) {
        t = 1;
    }
    if is_odd(2) || is_odd(i32(gid.x)) {
        t += 10;
    }
    out[base + 6] = t;
    out[base + 7] = calls;
    var nest = 0;
    for (var a = 0; a < 4; a++) {
        for (var b = 0; b < 4; b++) {
            if b > a {
                break;
            }
            nest += a * b;
        }
    }
    out[base + 8] = nest;
    let c = 7;
    const K = c2 * 3;
    out[base + 9] = K + c;
}

const c2 = 2;
