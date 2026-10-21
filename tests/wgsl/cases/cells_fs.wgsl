// The terminal's fragment stage (see cells_vs.wgsl): coverage or colour
// texels by textureLoad at the pixel's offset in the cell, the
// decorations, the thin cursors, foreground over background. Run alone on
// hand-made inputs (glyphs, colour glyphs, each decoration, cursors).
// ULP: 2
// JOB: call fs 6
// JOB: input 576 0x41100000 0x40a00000 0 0x3f800000 0x3f800000 0x3f000000 0 0 0 0x3e800000 0x3f800000 0 2 1 3 4 0 1 1 1 1 0 0 0 0 0 0 0 0x41b00000 0x41a00000 0 0x3f800000 0x3f800000 0x3f800000 0x3f800000 0 0 0 0 0 0 0 4 4 1 0 2 9 0 0 0 0 0 0 0 0 0x41f80000 0x40400000 0 0x3f800000 0x3f000000 0x3f000000 0x3f000000 0 0x3e000000 0x3e000000 0x3e000000 0 0 0 1 1 0 0 1 1 26 0 16 8 0 0 0 0 0x40400000 0x41300000 0 0x3f800000 0x3f800000 0 0 0 0 0 0x3f800000 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 3 0 0 0 0 0 0x40000000 0x40000000 0 0x3f800000 0x3f800000 0x3f800000 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 2 0 0 0 0 0x41000000 0x41800000 0 0x3f800000 0 0x3f800000 0 0 0x3f800000 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 0
// JOB: buffer 0 0 80 8 4 1 9 18 14 2 12 1 3 1 0x00ff8800 5 20 2 2 160.0 72.0 0 0
// JOB: texture 0 3 r8unorm 8 8 random 13
// JOB: texture 0 4 rgba8unorm 8 8 random 17

struct U {
    cols: u32, lines: u32, top: u32, cw: u32,
    ch: u32, ul_pos: u32, ul_thick: u32, strike_pos: u32,
    cur_line: u32, cur_col: u32, cur_shape: u32, cur_color: u32,
    sel_lo: u32, sel_hi: u32, pad_x: u32, pad_y: u32,
    vw: f32, vh: f32, r0: u32, r1: u32,
}

@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(3) var cov: texture_2d<f32>;
@group(0) @binding(4) var colp: texture_2d<f32>;

struct V {
    @builtin(position) pos: vec4<f32>,
    @location(0) @interpolate(flat) fg: vec3<f32>,
    @location(1) @interpolate(flat) bg: vec3<f32>,
    @location(2) @interpolate(flat) org: vec2<u32>,
    @location(3) @interpolate(flat) size: vec2<i32>,
    @location(4) @interpolate(flat) off: vec2<i32>,
    @location(5) @interpolate(flat) kind: u32,
    @location(6) @interpolate(flat) flags: u32,
    @location(7) @interpolate(flat) cell: vec2<u32>,
    @location(8) @interpolate(flat) xoff: i32,
    @location(9) @interpolate(flat) cur: u32,
}

fn rgbf(c: u32) -> vec3<f32> {
    return vec3<f32>(f32((c >> 16u) & 255u), f32((c >> 8u) & 255u), f32(c & 255u)) / 255.0;
}

// The decoration covering pixel (x, y) of a cell: 1 or 0.
fn deco(fl: u32, x: i32, y: i32) -> f32 {
    if fl == 0u || fl == 16u {
        return 0.0;
    }
    let t = i32(u.ul_thick);
    let ul = i32(u.ul_pos);
    let ch = i32(u.ch);
    let cw = i32(u.cw);
    let s = fl & 7u;
    var on = false;
    if s == 1u {
        on = y >= ul && y < ul + t;
    } else if s == 2u {
        let a = min(ul, ch - 3 * t);
        on = (y >= a && y < a + t) || (y >= a + 2 * t && y < a + 3 * t);
    } else if s == 3u {
        let h = max(cw / 2, 1);
        let ph = x % cw;
        let tri = select(cw - ph, ph, ph < h);
        let top = min(ul - t + tri * 2 * t / h, ch - t);
        on = y >= top && y < top + t;
    } else if s == 4u {
        on = y >= ul && y < ul + t && (x / t) % 2 == 0;
    } else if s == 5u {
        on = y >= ul && y < ul + t && x % (6 * t) < 4 * t;
    }
    if (fl & 8u) != 0u {
        let sp = i32(u.strike_pos);
        on = on || (y >= sp && y < sp + t);
    }
    return select(0.0, 1.0, on);
}

@fragment
fn fs(v: V) -> @location(0) vec4<f32> {
    let y = i32(v.pos.y) - i32(v.cell.y);
    let x = i32(v.pos.x) - i32(v.cell.x) + v.xoff;
    var c = 0.0;
    var k = vec4<f32>(0.0);
    let t = vec2<i32>(x, y) - v.off;
    if v.kind != 0u && t.x >= 0 && t.y >= 0 && t.x < v.size.x && t.y < v.size.y {
        let at = v.org + vec2<u32>(t);
        if v.kind == 1u {
            c = textureLoad(cov, at, 0).r;
        } else {
            k = textureLoad(colp, at, 0);
        }
    }
    var o = k.rgb + v.bg * (1.0 - k.a);
    o = o + (v.fg - o) * c;
    o = o + (v.fg - o) * deco(v.flags, x, y);
    if v.cur != 0u {
        let th = i32(u.ul_thick);
        let cw = i32(u.cw);
        let ch = i32(u.ch);
        var m = false;
        if v.cur == 2u {
            m = x < th;
        } else if v.cur == 3u {
            m = y >= ch - th;
        } else {
            m = x < th || x >= cw - th || y < th || y >= ch - th;
        }
        if m {
            o = rgbf(u.cur_color);
        }
    }
    return vec4<f32>(o, 1.0);
}
