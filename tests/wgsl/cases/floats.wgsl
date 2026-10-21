// Float arithmetic and the math builtins whose results are exact or
// correctly rounded on both sides; the rest are compared within a few ULP.
// ULP: 4
// JOB: dispatch 1 1 1
// JOB: buffer 0 0 64 0x3fc00000 0xc0200000 0x40490fdb 0x3e800000 0x00000000 0x80000000 0x42c80000 0x3f000000
// JOB: buffer 0 1 512

@group(0) @binding(0) var<storage, read> inp: array<f32>;
@group(0) @binding(1) var<storage, read_write> out: array<f32>;

@compute @workgroup_size(1)
fn main() {
    let a = inp[0];
    let b = inp[1];
    let pi = inp[2];
    let q = inp[3];
    var k = 0u;
    let vals = array<f32, 40>(
        a + b, a - b, a * b, a / b, a % b, b % a, -a,
        floor(b), ceil(b), round(2.5), round(b), fract(a), trunc(b),
        sqrt(a), abs(b), min(a, b), max(a, b), clamp(b, -1.0, 1.0),
        sign(b), step(a, b), mix(a, b, q), fma(a, b, q),
        sin(pi * q), cos(pi * q), exp2(a), log2(inp[6]), pow(a, 2.0),
        inverseSqrt(q), length(vec2(a, b)), distance(vec3(a), vec3(b)),
        dot(vec3(a, b, q), vec3(1.0, 2.0, 3.0)), smoothstep(0.0, 1.0, q),
        degrees(pi), radians(180.0), saturate(b), atan2(a, b), tanh(q),
        f32(i32(b)), f32(u32(inp[6])), ldexp(a, 3)
    );
    for (var i = 0u; i < 40u; i++) {
        out[i] = vals[i];
    }
    let c = cross(vec3(a, b, q), vec3(q, a, b));
    out[40] = c.x;
    out[41] = c.y;
    out[42] = c.z;
    let n = normalize(vec2(3.0, 4.0));
    out[43] = n.x;
    out[44] = n.y;
    let m = mat2x2<f32>(a, b, q, pi);
    let mv = m * vec2(1.0, 2.0);
    out[45] = mv.x;
    out[46] = mv.y;
    let vm = vec2(1.0, 2.0) * m;
    out[47] = vm.x;
    out[48] = vm.y;
    let mm = m * transpose(m);
    out[49] = mm[0].x;
    out[50] = mm[1].y;
    out[51] = determinant(m);
    let r = reflect(vec2(1.0, -1.0), vec2(0.0, 1.0));
    out[52] = r.y;
    out[53] = bitcast<f32>(pack4x8unorm(vec4(0.0, 0.5, 1.0, 2.0)));
    let u = unpack4x8unorm(0x80ff4000u);
    out[54] = u.x;
    out[55] = u.w;
    out[56] = bitcast<f32>(pack2x16float(vec2(1.5, -2.0)));
    let h = unpack2x16float(0x3c00c000u);
    out[57] = h.x + h.y;
    out[58] = select(a, b, a > b);
    out[59] = f32(inp[4] == inp[5]);
}
