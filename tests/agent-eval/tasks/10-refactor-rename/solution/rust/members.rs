// The library's members and what they owe.

pub struct Member {
    pub id: i64,
    pub name: String,
    // Books held now.
    pub on_loan: i64,
    // Late fees not yet paid, in cents.
    pub owes: i64,
    // Late fees paid so far, in cents.
    pub paid: i64,
}

pub struct Members {
    // In the order they joined.
    pub list: Vec<Member>,
}

impl Members {
    pub fn new() -> Members {
        Members { list: Vec::new() }
    }

    // The index of the member `id`.
    pub fn find(&self, id: i64) -> Option<usize> {
        for i in 0..self.list.len() {
            if self.list[i].id == id {
                return Some(i);
            }
        }
        None
    }

    // Adds a member; false if `id` is taken.
    pub fn add(&mut self, id: i64, name: &str) -> bool {
        if self.find(id).is_some() {
            return false;
        }
        self.list.push(Member { id: id, name: name.to_string(), on_loan: 0, owes: 0, paid: 0 });
        true
    }

    // Takes up to `cents` off what member `i` owes; returns the amount taken.
    pub fn pay(&mut self, i: usize, cents: i64) -> i64 {
        let m = &mut self.list[i];
        let amount = if cents < m.owes { cents } else { m.owes };
        m.owes -= amount;
        m.paid += amount;
        amount
    }

    // Fees owed, over every member.
    pub fn total_owed(&self) -> i64 {
        let mut n = 0;
        for m in &self.list {
            n += m.owes;
        }
        n
    }
}
