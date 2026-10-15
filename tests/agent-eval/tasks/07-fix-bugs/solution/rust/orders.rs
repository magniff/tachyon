// Orders: each line is filled from the inventory or rejected, then the
// order's discount and total are computed.

use crate::inventory::Inventory;
use crate::money::{percent_of, push_cents};

#[derive(Clone, Copy, PartialEq)]
pub enum Tier {
    Basic,
    Silver,
    Gold,
}

pub fn parse_tier(word: &str) -> Tier {
    if word == "gold" {
        Tier::Gold
    } else if word == "silver" {
        Tier::Silver
    } else {
        Tier::Basic
    }
}

pub fn tier_name(tier: Tier) -> &'static str {
    match tier {
        Tier::Basic => "basic",
        Tier::Silver => "silver",
        Tier::Gold => "gold",
    }
}

pub struct OrderLine {
    pub sku: i64,
    pub qty: i64,
}

pub struct Order {
    pub customer: String,
    pub tier: Tier,
    pub lines: Vec<OrderLine>,
}

// Orders of at least this much (in cents, before discount) get BULK_PERCENT more off.
const BULK_MIN: i64 = 10000;
const BULK_PERCENT: i64 = 5;

// The discount, in percent, for an order of `subtotal` cents.
pub fn discount_percent(tier: Tier, subtotal: i64) -> i64 {
    let mut percent = match tier {
        Tier::Basic => 0,
        Tier::Silver => 5,
        Tier::Gold => 10,
    };
    if subtotal >= BULK_MIN {
        percent += BULK_PERCENT;
    }
    percent
}

// What one order has added up to so far.
struct Tally {
    subtotal: i64,
    filled: i64,
    rejected: i64,
}

impl Tally {
    fn new() -> Tally {
        Tally {
            subtotal: 0,
            filled: 0,
            rejected: 0,
        }
    }

    // Starts the next order.
    fn reset(&mut self) {
        self.subtotal = 0;
        self.filled = 0;
        self.rejected = 0;
    }
}

// Fills one order line, or rejects it; writes its report line.
fn fill_line(inv: &mut Inventory, line: &OrderLine, tally: &mut Tally, out: &mut String) {
    out.push_str("  ");
    out.push_str(&line.sku.to_string());
    let index = match inv.find(line.sku) {
        Some(i) => i,
        None => {
            out.push_str(" x");
            out.push_str(&line.qty.to_string());
            out.push_str(": unknown\n");
            tally.rejected += 1;
            return;
        }
    };
    let price = inv.items[index].price;
    let stock = inv.items[index].stock;
    out.push(' ');
    out.push_str(&inv.items[index].name);
    out.push_str(" x");
    out.push_str(&line.qty.to_string());
    if !inv.take(index, line.qty) {
        out.push_str(": short (");
        out.push_str(&stock.to_string());
        out.push_str(" in stock)\n");
        tally.rejected += 1;
        return;
    }
    let cost = price * line.qty;
    out.push_str(" @ ");
    push_cents(out, price);
    out.push_str(" = ");
    push_cents(out, cost);
    out.push('\n');
    tally.subtotal += cost;
    tally.filled += 1;
}

// Processes the orders in turn and writes their reports; returns the
// revenue (the sum of the totals).
pub fn process_orders(inv: &mut Inventory, list: &Vec<Order>, out: &mut String) -> i64 {
    let mut revenue = 0;
    let mut tally = Tally::new();
    for (i, order) in list.iter().enumerate() {
        tally.reset();
        out.push_str("order ");
        out.push_str(&(i + 1).to_string());
        out.push(' ');
        out.push_str(&order.customer);
        out.push_str(" (");
        out.push_str(tier_name(order.tier));
        out.push_str(")\n");
        for line in &order.lines {
            fill_line(inv, line, &mut tally, out);
        }
        let percent = discount_percent(order.tier, tally.subtotal);
        let discount = percent_of(tally.subtotal, percent);
        let total = tally.subtotal - discount;
        out.push_str("  subtotal ");
        push_cents(out, tally.subtotal);
        out.push_str(", discount ");
        out.push_str(&percent.to_string());
        out.push_str("% ");
        push_cents(out, discount);
        out.push_str(", total ");
        push_cents(out, total);
        out.push_str(" (");
        out.push_str(&tally.filled.to_string());
        out.push_str(" filled, ");
        out.push_str(&tally.rejected.to_string());
        out.push_str(" rejected)\n");
        revenue += total;
    }
    revenue
}
