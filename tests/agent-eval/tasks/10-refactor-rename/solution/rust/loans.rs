// Books out on loan, and the fee for returning one late.

// A loan lasts this many days; each day after it is late.
pub const LOAN_DAYS: i64 = 14;
// The first late days cost FEE_LOW cents each, later ones FEE_HIGH.
const LOW_DAYS: i64 = 7;
const FEE_LOW: i64 = 25;
const FEE_HIGH: i64 = 50;
// No fee is more than this.
const FEE_CAP: i64 = 1500;

pub struct Loan {
    pub member: i64,
    pub book: i64,
    // The day it was lent.
    pub day: i64,
}

pub struct Loans {
    // Oldest first.
    pub list: Vec<Loan>,
}

impl Loans {
    pub fn new() -> Loans {
        Loans { list: Vec::new() }
    }

    pub fn lend(&mut self, member: i64, book: i64, day: i64) {
        self.list.push(Loan {
            member: member,
            book: book,
            day: day,
        });
    }

    // The index of the oldest loan of `book` to `member`.
    pub fn find(&self, member: i64, book: i64) -> Option<usize> {
        for i in 0..self.list.len() {
            let l = &self.list[i];
            if l.member == member && l.book == book {
                return Some(i);
            }
        }
        None
    }

    // Removes loan `i`, keeping the others in order; returns it.
    pub fn remove(&mut self, i: usize) -> Loan {
        self.list.remove(i)
    }
}

// Days past the loan period for a book held `days` days (0 if on time).
pub fn days_late(days: i64) -> i64 {
    if days > LOAN_DAYS {
        days - LOAN_DAYS
    } else {
        0
    }
}

// The late fee, in cents, for a book held `days` days.
pub fn late_fee(days: i64) -> i64 {
    let late = days_late(days);
    let low = if late < LOW_DAYS { late } else { LOW_DAYS };
    let fee = low * FEE_LOW + (late - low) * FEE_HIGH;
    if fee > FEE_CAP {
        FEE_CAP
    } else {
        fee
    }
}
