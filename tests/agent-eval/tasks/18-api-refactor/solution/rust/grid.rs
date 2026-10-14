// Positions on the map: stepping, bounds, tiles, teleporter pairs, text.
// A position is a row and a column, both from 0; row 0 is the top.

use crate::level::Level;

#[derive(Clone, Copy, PartialEq)]
pub struct Pos {
    pub row: i64,
    pub col: i64,
}

impl Pos {
    pub fn new(row: i64, col: i64) -> Pos {
        Pos { row: row, col: col }
    }
}

// The position one step from `p` in direction `dir`: 'N' up, 'S' down,
// 'E' right, 'W' left.
pub fn step(p: Pos, dir: u8) -> Pos {
    if dir == b'N' {
        Pos::new(p.row - 1, p.col)
    } else if dir == b'S' {
        Pos::new(p.row + 1, p.col)
    } else if dir == b'E' {
        Pos::new(p.row, p.col + 1)
    } else {
        Pos::new(p.row, p.col - 1)
    }
}

pub fn in_bounds(level: &Level, p: Pos) -> bool {
    p.row >= 0 && p.row < level.height && p.col >= 0 && p.col < level.width
}

// The index of `p` in a row-by-row array of the map's cells.
pub fn cell_index(level: &Level, p: Pos) -> usize {
    (p.row * level.width + p.col) as usize
}

// The tile at `p`; outside the map everything is wall.
pub fn tile_at(level: &Level, p: Pos) -> u8 {
    if !in_bounds(level, p) {
        return b'#';
    }
    level.tiles[cell_index(level, p)]
}

// The teleporter paired with the one at `p`: the first with the second in
// reading order, the third with the fourth, and so on.
pub fn partner(level: &Level, p: Pos) -> Pos {
    let mut i = 0;
    while level.teleporters[i] != p {
        i += 1;
    }
    level.teleporters[i ^ 1]
}

// Appends "row,col".
pub fn push_pos(out: &mut String, p: Pos) {
    out.push_str(&p.row.to_string());
    out.push(',');
    out.push_str(&p.col.to_string());
}
