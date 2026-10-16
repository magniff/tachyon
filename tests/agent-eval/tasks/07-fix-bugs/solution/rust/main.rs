// Order processing: reads an inventory and a list of orders from stdin,
// fills the orders against the stock and prints a report.

mod inventory;
mod money;
mod orders;

use std::io::Read;

use inventory::{Inventory, Item};
use money::push_cents;
use orders::{parse_tier, process_orders, Order, OrderLine};

// Reads whitespace-separated words from the input.
struct Scanner {
    text: Vec<u8>,
    pos: usize,
}

impl Scanner {
    fn new(text: Vec<u8>) -> Scanner {
        Scanner { text: text, pos: 0 }
    }

    fn is_space(c: u8) -> bool {
        c == b' ' || c == b'\n' || c == b'\t' || c == b'\r'
    }

    // The next word, or "" at the end of the input.
    fn next_word(&mut self) -> String {
        while self.pos < self.text.len() && Scanner::is_space(self.text[self.pos]) {
            self.pos += 1;
        }
        let start = self.pos;
        while self.pos < self.text.len() && !Scanner::is_space(self.text[self.pos]) {
            self.pos += 1;
        }
        String::from_utf8_lossy(&self.text[start..self.pos]).to_string()
    }

    // The next word as a non-negative decimal integer.
    fn next_int(&mut self) -> i64 {
        let word = self.next_word();
        let mut n: i64 = 0;
        for c in word.bytes() {
            n = n * 10 + (c - b'0') as i64;
        }
        n
    }
}

fn read_inventory(sc: &mut Scanner) -> Inventory {
    let mut inv = Inventory::new();
    let _ = sc.next_word(); // "items"
    let count = sc.next_int();
    for _ in 0..count {
        let sku = sc.next_int();
        let price = sc.next_int();
        let stock = sc.next_int();
        let name = sc.next_word();
        inv.add(Item {
            sku: sku,
            name: name,
            price: price,
            stock: stock,
        });
    }
    inv.sort_by_sku();
    inv
}

fn read_orders(sc: &mut Scanner) -> Vec<Order> {
    let mut list = Vec::new();
    let _ = sc.next_word(); // "orders"
    let count = sc.next_int();
    for _ in 0..count {
        let customer = sc.next_word();
        let tier = parse_tier(&sc.next_word());
        let nlines = sc.next_int();
        let mut lines = Vec::new();
        for _ in 0..nlines {
            let sku = sc.next_int();
            let qty = sc.next_int();
            lines.push(OrderLine { sku: sku, qty: qty });
        }
        list.push(Order {
            customer: customer,
            tier: tier,
            lines: lines,
        });
    }
    list
}

fn main() {
    let mut input = Vec::new();
    std::io::stdin().read_to_end(&mut input).unwrap();
    let mut sc = Scanner::new(input);
    let mut inv = read_inventory(&mut sc);
    let list = read_orders(&mut sc);
    let mut out = String::new();
    let revenue = process_orders(&mut inv, &list, &mut out);
    inv.report(&mut out);
    out.push_str("revenue ");
    push_cents(&mut out, revenue);
    out.push('\n');
    print!("{}", out);
}
