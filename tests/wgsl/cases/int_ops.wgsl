// Integer semantics where WGSL defines what C++ (and MSL) leaves
// undefined: division by zero, MIN / -1, shifts of 32 and more, wrapping
// overflow, abs(MIN), saturating float conversions.
// JOB: dispatch 1 1 1
// JOB: buffer 0 0 256 0 1 4294967295 2147483648 2147483647 7 4294967289 33 0x7fc00000 0x7f800000 0xff800000 0x4f800000 0xcf000001 3
// JOB: buffer 0 1 1024

@group(0) @binding(0) var<storage, read> inp: array<u32>;
@group(0) @binding(1) var<storage, read_write> out: array<u32>;

var<private> n: u32 = 0u;

fn put(v: u32) {
    out[n] = v;
    n += 1u;
}

fn puti(v: i32) {
    put(bitcast<u32>(v));
}

@compute @workgroup_size(1)
fn main() {
    let zero = inp[0];
    let one = inp[1];
    let m1 = bitcast<i32>(inp[2]);
    let imin = bitcast<i32>(inp[3]);
    let imax = bitcast<i32>(inp[4]);
    let seven = bitcast<i32>(inp[5]);
    let mseven = bitcast<i32>(inp[6]);
    let big = inp[7];
    puti(seven / i32(zero));
    puti(seven % i32(zero));
    puti(imin / m1);
    puti(imin % m1);
    puti(mseven / 2);
    puti(mseven % 2);
    puti(seven % -3);
    put(one / zero);
    put(one % zero);
    put(7u / 2u);
    puti(imax + 1);
    puti(imin - 1);
    puti(imax * 2);
    puti(-imin);
    puti(abs(imin));
    puti(abs(mseven));
    puti(seven << big);
    puti(mseven >> big);
    put(one << big);
    put(inp[2] >> big);
    puti(bitcast<i32>(one) << 31u);
    put(countOneBits(inp[2]));
    put(countLeadingZeros(inp[5]));
    put(countTrailingZeros(8u));
    put(countLeadingZeros(zero));
    put(countTrailingZeros(zero));
    puti(firstLeadingBit(m1));
    puti(firstLeadingBit(mseven));
    put(firstLeadingBit(zero));
    put(firstLeadingBit(inp[4]));
    put(firstTrailingBit(zero));
    put(firstTrailingBit(48u));
    put(reverseBits(one));
    put(extractBits(inp[2], 4u, 8u));
    puti(extractBits(m1, 30u, 8u));
    puti(extractBits(i32(0x80), 7u, 1u));
    put(extractBits(inp[2], 40u, 8u));
    put(insertBits(zero, inp[2], 28u, 8u));
    put(insertBits(inp[2], zero, 0u, 32u));
    // float to int: NaN, infinities, out of range
    puti(i32(bitcast<f32>(inp[8])));
    puti(i32(bitcast<f32>(inp[9])));
    puti(i32(bitcast<f32>(inp[10])));
    put(u32(bitcast<f32>(inp[9])));
    put(u32(bitcast<f32>(inp[10])));
    put(u32(bitcast<f32>(inp[11])));
    puti(i32(bitcast<f32>(inp[12])));
    puti(i32(-2.5));
    put(u32(-1.0 * bitcast<f32>(inp[11])));
    puti(sign(mseven));
    puti(sign(i32(zero)));
    puti(min(mseven, seven));
    put(max(one, inp[2]));
    puti(clamp(mseven, -3, 3));
    puti(dot(vec2<i32>(imax, 2), vec2<i32>(2, imax)));
    put(select(1u, 2u, seven > 0));
    puti(-mseven);
    puti(~seven);
    put(u32(m1));
    puti(i32(inp[2]));
    put(u32(true));
    puti(i32(false));
    let v = vec3<i32>(seven, mseven, imin) / vec3<i32>(0, 2, -1);
    puti(v.x);
    puti(v.y);
    puti(v.z);
    let w = vec2<u32>(one, inp[2]) << vec2<u32>(big, 31u);
    put(w.x);
    put(w.y);
    put(n);
}
