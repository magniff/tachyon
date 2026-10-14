// The reports: stock, members, overdue loans and totals.

use crate::catalog::Book;
use crate::loans::{days_late, late_fee};
use crate::text::{push_int, push_money};
use crate::Library;

// Every title: its id, title, copies on the shelf and copies owned.
pub fn report_stock(lib: &Library, out: &mut String) {
    out.push_str("stock:\n");
    if lib.catalog.items.is_empty() {
        out.push_str("  none\n");
    }
    for it in &lib.catalog.items {
        let it: &Book = it;
        out.push_str("  ");
        push_int(out, it.id);
        out.push(' ');
        out.push_str(&it.title);
        out.push_str(": ");
        push_int(out, it.available());
        out.push('/');
        push_int(out, it.copies);
        out.push('\n');
    }
}

// Every member: books held, fees owed and paid.
pub fn report_members(lib: &Library, out: &mut String) {
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
pub fn report_overdue(lib: &Library, day: i64, out: &mut String) {
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
        push_money(out, late_fee(day - l.day));
        out.push('\n');
    }
    if count == 0 {
        out.push_str("  none\n");
    }
}

// Totals over the whole library.
pub fn report_summary(lib: &Library, out: &mut String) {
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
