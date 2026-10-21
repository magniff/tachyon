// The terminal's one shader (docs/design/terminal.md §3.5): one instanced
// draw of a 4-vertex strip per cell, translated by std::gpu::wgsl.
//
// The vertex stage does the per-cell work once per vertex rather than
// once per pixel: it places instance i at its line and column (the line
// from the ring's top row, a uniform), unpacks the colours, swaps them for
// the selection and the block cursor, and fetches the glyph's atlas
// entry. The fragment stage reads the glyph's coverage (or colour) texel
// at the pixel's offset in the cell, draws the decorations and the thin
// cursors, and mixes foreground over background: no blending, no
// overdraw. Every rule has its twin in tests/voltty-render/cpu.tach, the
// reference renderer the tests compare GPU images with;
// tests/wgsl/cases/cells_vs.wgsl and cells_fs.wgsl run the two stages on
// the interpreter.
//
// cells.tach holds this text as a constant (render/embed.sh writes it:
// tachyon has no include_str yet).

struct U {
    cols: u32, lines: u32, top: u32, cw: u32,
    ch: u32, ul_pos: u32, ul_thick: u32, strike_pos: u32,
    cur_line: u32, cur_col: u32, cur_shape: u32, cur_color: u32,
    sel_lo: u32, sel_hi: u32, pad_x: u32, pad_y: u32,
    vw: f32, vh: f32, r0: u32, r1: u32,
}

struct Inst { glyph: u32, fg: u32, bg: u32, flags: u32 }

// an atlas entry: x | y << 16, w | h << 16, ox | oy << 16, kind
struct Entry { xy: u32, wh: u32, oxy: u32, kind: u32 }

@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var<storage, read> inst: array<Inst>;
@group(0) @binding(2) var<storage, read> ent: array<Entry>;
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

@vertex
fn vs(@builtin(vertex_index) vid: u32, @builtin(instance_index) iid: u32) -> V {
    let slot = iid / u.cols;
    let col = iid - slot * u.cols;
    let line = (slot + u.lines - u.top) % u.lines;
    let cx = u.pad_x + col * u.cw;
    let cy = u.pad_y + line * u.ch;
    let c = vec2<f32>(f32(vid & 1u), f32(vid >> 1u));
    let p = vec2<f32>(f32(cx), f32(cy)) + c * vec2<f32>(f32(u.cw), f32(u.ch));
    var o: V;
    o.pos = vec4<f32>(p.x / u.vw * 2.0 - 1.0, 1.0 - p.y / u.vh * 2.0, 0.0, 1.0);
    let i = inst[iid];
    var fg = i.fg;
    var bg = i.bg;
    let idx = line * u.cols + col;
    if idx >= u.sel_lo && idx < u.sel_hi {
        let t = fg;
        fg = bg;
        bg = t;
    }
    let at = line == u.cur_line && col == u.cur_col;
    if at && u.cur_shape == 1u {
        fg = bg;
        bg = u.cur_color;
    }
    o.fg = rgbf(fg);
    o.bg = rgbf(bg);
    o.kind = 0u;
    o.org = vec2<u32>(0u);
    o.size = vec2<i32>(0);
    o.off = vec2<i32>(0);
    if i.glyph != 0u {
        let e = ent[i.glyph];
        o.kind = e.kind + 1u;
        o.org = vec2<u32>(e.xy & 0xffffu, e.xy >> 16u);
        o.size = vec2<i32>(i32(e.wh & 0xffffu), i32(e.wh >> 16u));
        o.off = vec2<i32>(i32(e.oxy & 0xffffu), i32(e.oxy >> 16u));
    }
    o.flags = i.flags;
    o.cell = vec2<u32>(cx, cy);
    o.xoff = select(0, i32(u.cw), (i.flags & 16u) != 0u);
    o.cur = select(0u, u.cur_shape, at && u.cur_shape >= 2u);
    return o;
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
