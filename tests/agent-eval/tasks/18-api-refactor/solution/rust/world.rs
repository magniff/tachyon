// The state that commands change: where the robot and the boxes are, the
// marks, the steps that can be undone, and the counters.

use crate::grid::{cell_index, partner, step, tile_at, Pos};
use crate::level::Level;

// One step of the robot, enough to take it back.
pub struct Step {
    // Where the robot was before the step.
    pub robot: Pos,
    // The box it pushed (an index into World::boxes), or -1.
    pub moved_box: i64,
    // Where that box was before the push.
    pub box_from: Pos,
}

pub struct World {
    pub robot: Pos,
    pub boxes: Vec<Pos>,
    pub marks: Vec<Pos>,
    // Oldest first.
    pub history: Vec<Step>,
    pub moves: i64,
    pub pushes: i64,
}

impl World {
    pub fn new(level: &Level) -> World {
        let mut w = World {
            robot: level.start,
            boxes: Vec::new(),
            marks: Vec::new(),
            history: Vec::new(),
            moves: 0,
            pushes: 0,
        };
        w.reset(level);
        w
    }

    // Back to the level's start: robot, boxes, no marks, no history.
    pub fn reset(&mut self, level: &Level) {
        self.robot = level.start;
        self.boxes.clear();
        for i in 0..level.boxes.len() {
            self.boxes.push(level.boxes[i]);
        }
        self.marks.clear();
        self.history.clear();
        self.moves = 0;
        self.pushes = 0;
    }

    // The index of the box at `p`, or -1.
    pub fn box_at(&self, p: Pos) -> i64 {
        for i in 0..self.boxes.len() {
            if self.boxes[i] == p {
                return i as i64;
            }
        }
        -1
    }

    pub fn boxes_on_goals(&self, level: &Level) -> i64 {
        let mut n = 0;
        for i in 0..self.boxes.len() {
            if tile_at(level, self.boxes[i]) == b'G' {
                n += 1;
            }
        }
        n
    }

    // The fewest steps the robot needs from `from` to `to` without pushing
    // a box, teleporters included; -1 if it cannot get there.
    pub fn distance(&self, level: &Level, from: Pos, to: Pos) -> i64 {
        if from == to {
            return 0;
        }
        let cells = (level.height * level.width) as usize;
        let mut blocked: Vec<bool> = vec![false; cells];
        for i in 0..self.boxes.len() {
            blocked[cell_index(level, self.boxes[i])] = true;
        }
        let mut dist: Vec<i64> = vec![-1; cells];
        let mut queue: Vec<Pos> = Vec::new();
        dist[cell_index(level, from)] = 0;
        queue.push(from);
        let dirs = b"NSEW";
        let mut head = 0;
        while head < queue.len() {
            let p = queue[head];
            head += 1;
            let d = dist[cell_index(level, p)];
            for k in 0..4 {
                let mut q = step(p, dirs[k]);
                if tile_at(level, q) == b'#' || blocked[cell_index(level, q)] {
                    continue;
                }
                if tile_at(level, q) == b'T' {
                    let t = partner(level, q);
                    if !blocked[cell_index(level, t)] {
                        q = t;
                    }
                }
                let qi = cell_index(level, q);
                if dist[qi] < 0 {
                    dist[qi] = d + 1;
                    if q == to {
                        return d + 1;
                    }
                    queue.push(q);
                }
            }
        }
        -1
    }
}
