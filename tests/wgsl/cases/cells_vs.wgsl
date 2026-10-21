// The terminal's shader (docs/design/terminal.md §3.5, the hand-written
// MSL of examples/term/render/shader.tach as WGSL): its vertex stage, run
// alone for random instances (out-of-range ones read zero from the
// runtime-sized arrays). cells_fs.wgsl is the same file's fragment stage.
// (Metal divides within 2.5 ULP:)
// ULP: 2
// JOB: call vs 64
// JOB: input 1024 random 9
// JOB: buffer 0 0 80 8 4 1 9 18 14 2 12 1 3 1 0x00ff8800 5 20 2 2 160.0 72.0 0 0
// JOB: buffer 0 1 256 random 4
// JOB: buffer 0 2 64 random 5

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
