// A library's front desk: books, members, loans and reports, driven by
// commands on stdin, one per line. Everything printed goes through `out`.

mod catalog;
mod loans;
mod members;
mod text;

use catalog::{Catalog, Item};
use loans::{calc, days_late, Loans, LOAN_DAYS};
use members::Members;
use std::io::Read;
use text::{parse_int, push_int, push_money, rest_after, words};

// A member may hold this many books at once.
const MAX_LOANS: i64 = 3;
// A member who owes more than this, in cents, may not borrow.
const MAX_OWED: i64 = 1000;

pub struct Library {
    pub catalog: Catalog,
    pub members: Members,
    pub loans: Loans,
    // Fees paid, in cents.
    pub collected: i64,
}

fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).unwrap();
    let mut lib = Library {
        catalog: Catalog::new(),
        members: Members::new(),
        loans: Loans::new(),
        collected: 0,
    };
    let mut out = String::new();
    for raw in input.split('\n') {
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        let w = words(line);
        if w.is_empty() || w[0].starts_with('#') {
            continue;
        }
        run_command(&mut lib, line, &w, &mut out);
    }
    print!("{}", out);
}

fn run_command(lib: &mut Library, line: &str, w: &[&str], out: &mut String) {
    let cmd = w[0];
    if cmd == "ADD" {
        cmd_add(lib, line, w, out);
    } else if cmd == "JOIN" {
        cmd_join(lib, line, w, out);
    } else if cmd == "LEND" {
        cmd_lend(lib, w, out);
    } else if cmd == "RETURN" {
        cmd_return(lib, w, out);
    } else if cmd == "PAY" {
        cmd_pay(lib, w, out);
    } else if cmd == "REPORT" {
        cmd_report(lib, w, out);
    } else {
        out.push_str("error: unknown command ");
        out.push_str(cmd);
        out.push('\n');
    }
}

// Writes the usage line of a command given too few words.
fn usage(text: &str, out: &mut String) {
    out.push_str("error: usage: ");
    out.push_str(text);
    out.push('\n');
}

// The number in `word`, or None after writing an error.
fn number(word: &str, out: &mut String) -> Option<i64> {
    let n = parse_int(word);
    if n.is_none() {
        out.push_str("error: bad number ");
        out.push_str(word);
        out.push('\n');
    }
    n
}

// ADD <id> <copies> <title>
fn cmd_add(lib: &mut Library, line: &str, w: &[&str], out: &mut String) {
    if w.len() < 4 {
        return usage("ADD <id> <copies> <title>", out);
    }
    let id = match number(w[1], out) {
        Some(n) => n,
        None => return,
    };
    let qty = match number(w[2], out) {
        Some(n) => n,
        None => return,
    };
    if qty == 0 {
        out.push_str("error: no copies\n");
        return;
    }
    let known = lib.catalog.find(id).is_some();
    let now = lib.catalog.add(id, rest_after(line, 3), qty);
    if known {
        out.push_str("restocked ");
        push_int(out, id);
        out.push_str(": ");
        push_int(out, now);
        out.push_str(" copies\n");
    } else {
        out.push_str("added ");
        push_int(out, id);
        out.push_str(": ");
        out.push_str(rest_after(line, 3));
        out.push('\n');
    }
}

// JOIN <id> <name>
fn cmd_join(lib: &mut Library, line: &str, w: &[&str], out: &mut String) {
    if w.len() < 3 {
        return usage("JOIN <id> <name>", out);
    }
    let id = match number(w[1], out) {
        Some(n) => n,
        None => return,
    };
    if lib.members.add(id, rest_after(line, 2)) {
        out.push_str("joined ");
    } else {
        out.push_str("error: member exists ");
    }
    push_int(out, id);
    out.push('\n');
}

// LEND <member> <book> <day>
fn cmd_lend(lib: &mut Library, w: &[&str], out: &mut String) {
    if w.len() < 4 {
        return usage("LEND <member> <book> <day>", out);
    }
    let member = match number(w[1], out) {
        Some(n) => n,
        None => return,
    };
    let book = match number(w[2], out) {
        Some(n) => n,
        None => return,
    };
    let day = match number(w[3], out) {
        Some(n) => n,
        None => return,
    };
    let mi = match lib.members.find(member) {
        Some(i) => i,
        None => {
            out.push_str("error: no member ");
            push_int(out, member);
            out.push('\n');
            return;
        }
    };
    let bi = match lib.catalog.find(book) {
        Some(i) => i,
        None => {
            out.push_str("error: no book ");
            push_int(out, book);
            out.push('\n');
            return;
        }
    };
    let m = &mut lib.members.list[mi];
    let it: &mut Item = &mut lib.catalog.items[bi];
    if m.on_loan >= MAX_LOANS {
        out.push_str("error: member ");
        push_int(out, member);
        out.push_str(" holds ");
        push_int(out, MAX_LOANS);
        out.push_str(" books\n");
        return;
    }
    if m.owes > MAX_OWED {
        out.push_str("error: member ");
        push_int(out, member);
        out.push_str(" owes ");
        push_money(out, m.owes);
        out.push('\n');
        return;
    }
    if it.available() == 0 {
        out.push_str("error: book ");
        push_int(out, book);
        out.push_str(" is out\n");
        return;
    }
    it.lent += 1;
    m.on_loan += 1;
    lib.loans.lend(member, book, day);
    out.push_str("lent ");
    push_int(out, book);
    out.push_str(" to ");
    push_int(out, member);
    out.push_str(", due day ");
    push_int(out, day + LOAN_DAYS);
    out.push('\n');
}

// RETURN <member> <book> <day>
fn cmd_return(lib: &mut Library, w: &[&str], out: &mut String) {
    if w.len() < 4 {
        return usage("RETURN <member> <book> <day>", out);
    }
    let member = match number(w[1], out) {
        Some(n) => n,
        None => return,
    };
    let book = match number(w[2], out) {
        Some(n) => n,
        None => return,
    };
    let day = match number(w[3], out) {
        Some(n) => n,
        None => return,
    };
    let li = match lib.loans.find(member, book) {
        Some(i) => i,
        None => {
            out.push_str("error: no loan of ");
            push_int(out, book);
            out.push_str(" to ");
            push_int(out, member);
            out.push('\n');
            return;
        }
    };
    let loan = lib.loans.remove(li);
    let days = day - loan.day;
    let fee = calc(days);
    if let Some(mi) = lib.members.find(member) {
        let m = &mut lib.members.list[mi];
        m.on_loan -= 1;
        m.owes += fee;
    }
    if let Some(bi) = lib.catalog.find(book) {
        lib.catalog.items[bi].lent -= 1;
    }
    out.push_str("returned ");
    push_int(out, book);
    out.push_str(" by ");
    push_int(out, member);
    out.push_str(", ");
    push_int(out, days_late(days));
    out.push_str(" days late, fee ");
    push_money(out, fee);
    out.push('\n');
}

// PAY <member> <cents>
fn cmd_pay(lib: &mut Library, w: &[&str], out: &mut String) {
    if w.len() < 3 {
        return usage("PAY <member> <cents>", out);
    }
    let member = match number(w[1], out) {
        Some(n) => n,
        None => return,
    };
    let cents = match number(w[2], out) {
        Some(n) => n,
        None => return,
    };
    let mi = match lib.members.find(member) {
        Some(i) => i,
        None => {
            out.push_str("error: no member ");
            push_int(out, member);
            out.push('\n');
            return;
        }
    };
    let amount = lib.members.pay(mi, cents);
    lib.collected += amount;
    out.push_str("paid ");
    push_money(out, amount);
    out.push_str(", owes ");
    push_money(out, lib.members.list[mi].owes);
    out.push('\n');
}

// REPORT STOCK | MEMBERS | OVERDUE <day> | SUMMARY
fn cmd_report(lib: &Library, w: &[&str], out: &mut String) {
    if w.len() < 2 {
        return usage("REPORT <kind>", out);
    }
    let kind = w[1];
    if kind == "STOCK" {
        report_stock(lib, out);
    } else if kind == "MEMBERS" {
        report_members(lib, out);
    } else if kind == "OVERDUE" {
        if w.len() < 3 {
            return usage("REPORT OVERDUE <day>", out);
        }
        let day = match number(w[2], out) {
            Some(n) => n,
            None => return,
        };
        report_overdue(lib, day, out);
    } else if kind == "SUMMARY" {
        report_summary(lib, out);
    } else {
        out.push_str("error: unknown report ");
        out.push_str(kind);
        out.push('\n');
    }
}

// Every title: its id, title, copies on the shelf and copies owned.
fn report_stock(lib: &Library, out: &mut String) {
    out.push_str("stock:\n");
    if lib.catalog.items.is_empty() {
        out.push_str("  none\n");
    }
    for it in &lib.catalog.items {
        let it: &Item = it;
        out.push_str("  ");
        push_int(out, it.id);
        out.push(' ');
        out.push_str(&it.title);
        out.push_str(": ");
        push_int(out, it.available());
        out.push('/');
        push_int(out, it.qty);
        out.push('\n');
    }
}

// Every member: books held, fees owed and paid.
fn report_members(lib: &Library, out: &mut String) {
    out.push_str("members:\n");
    if lib.members.list.is_empty() {
        out.push_str("  none\n");
    }
    for m in &lib.members.list {
        out.push_str("  ");
        push_int(out, m.id);
        out.push(' ');
        out.push_str(&m.name);
        out.push_str(": ");
        push_int(out, m.on_loan);
        out.push_str(" on loan, owes ");
        push_money(out, m.owes);
        out.push_str(", paid ");
        push_money(out, m.paid);
        out.push('\n');
    }
}

// Every loan late on `day`, oldest first, with the fee if returned then.
fn report_overdue(lib: &Library, day: i64, out: &mut String) {
    out.push_str("overdue on day ");
    push_int(out, day);
    out.push_str(":\n");
    let mut count = 0;
    for l in &lib.loans.list {
        let late = days_late(day - l.day);
        if late == 0 {
            continue;
        }
        count += 1;
        out.push_str("  ");
        match lib.members.find(l.member) {
            Some(mi) => out.push_str(&lib.members.list[mi].name),
            None => out.push('?'),
        }
        out.push_str(" has ");
        match lib.catalog.find(l.book) {
            Some(bi) => out.push_str(&lib.catalog.items[bi].title),
            None => out.push('?'),
        }
        out.push_str(", ");
        push_int(out, late);
        out.push_str(" days late, fee ");
        push_money(out, calc(day - l.day));
        out.push('\n');
    }
    if count == 0 {
        out.push_str("  none\n");
    }
}

// Totals over the whole library.
fn report_summary(lib: &Library, out: &mut String) {
    out.push_str("summary: ");
    push_int(out, lib.catalog.items.len() as i64);
    out.push_str(" titles, ");
    push_int(out, lib.catalog.total_qty());
    out.push_str(" copies, ");
    push_int(out, lib.catalog.total_lent());
    out.push_str(" lent, ");
    push_int(out, lib.members.list.len() as i64);
    out.push_str(" members, owed ");
    push_money(out, lib.members.total_owed());
    out.push_str(", collected ");
    push_money(out, lib.collected);
    out.push('\n');
}
