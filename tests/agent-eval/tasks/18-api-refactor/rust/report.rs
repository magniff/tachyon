// What the program prints about a level and its state.

use crate::grid::{cell_index, push_pos, tile_at};
use crate::level::{
    Level, ERR_EMPTY, ERR_MANY_ROBOTS, ERR_NO_ROBOT, ERR_NO_SEPARATOR, ERR_ODD_TELEPORTERS,
    ERR_RAGGED, ERR_UNKNOWN_TILE,
};
use crate::world::World;

// The line for a load_level error code.
pub fn push_load_error(out: &mut String, code: i64, level: &Level) {
    out.push_str("error: ");
    if code == ERR_EMPTY {
        out.push_str("the map is empty");
    } else if code == ERR_NO_SEPARATOR {
        out.push_str("no '---' line after the map");
    } else if code == ERR_RAGGED {
        out.push_str("row ");
        out.push_str(&level.error_at.0.to_string());
        out.push_str(" has length ");
        out.push_str(&level.error_num.to_string());
        out.push_str(", expected ");
        out.push_str(&level.width.to_string());
    } else if code == ERR_UNKNOWN_TILE {
        out.push_str("unknown tile '");
        out.push(level.error_tile as char);
        out.push_str("' at ");
        push_pos(out, level.error_at);
    } else if code == ERR_NO_ROBOT {
        out.push_str("no robot on the map");
    } else if code == ERR_MANY_ROBOTS {
        out.push_str("second robot at ");
        push_pos(out, level.error_at);
    } else if code == ERR_ODD_TELEPORTERS {
        out.push_str(&level.error_num.to_string());
        out.push_str(" teleporters, expected an even number");
    }
    out.push('\n');
}

// "level WxH, B boxes, G goals, T teleporters"
pub fn push_summary(out: &mut String, level: &Level) {
    out.push_str("level ");
    out.push_str(&level.width.to_string());
    out.push('x');
    out.push_str(&level.height.to_string());
    out.push_str(", ");
    out.push_str(&level.boxes.len().to_string());
    out.push_str(" boxes, ");
    out.push_str(&level.goals.len().to_string());
    out.push_str(" goals, ");
    out.push_str(&level.teleporters.len().to_string());
    out.push_str(" teleporters\n");
}

// "moves M, pushes P, boxes on goals B/N", and " (solved)" when every
// box is on a goal.
pub fn push_status(out: &mut String, level: &Level, world: &World) {
    let on = world.boxes_on_goals(level);
    let n = world.boxes.len() as i64;
    out.push_str("moves ");
    out.push_str(&world.moves.to_string());
    out.push_str(", pushes ");
    out.push_str(&world.pushes.to_string());
    out.push_str(", boxes on goals ");
    out.push_str(&on.to_string());
    out.push('/');
    out.push_str(&n.to_string());
    if n > 0 && on == n {
        out.push_str(" (solved)");
    }
    out.push('\n');
}

// The map as it is now: '@' the robot, '$' a box, '*' a box on a goal.
pub fn push_map(out: &mut String, level: &Level, world: &World) {
    let mut cells: Vec<u8> = level.tiles.clone();
    for i in 0..world.boxes.len() {
        let b = world.boxes[i];
        let k = cell_index(level, b);
        cells[k] = if tile_at(level, b) == b'G' { b'*' } else { b'$' };
    }
    cells[cell_index(level, world.robot)] = b'@';
    for r in 0..level.height {
        for c in 0..level.width {
            out.push(cells[cell_index(level, (r, c))] as char);
        }
        out.push('\n');
    }
}
