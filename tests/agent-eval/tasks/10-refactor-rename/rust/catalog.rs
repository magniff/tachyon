// The books the library owns: each title once, with its number of copies.

pub struct Item {
    pub id: i64,
    pub title: String,
    // Copies the library owns.
    pub qty: i64,
    // Copies out on loan.
    pub lent: i64,
}

impl Item {
    // Copies on the shelf.
    pub fn available(&self) -> i64 {
        self.qty - self.lent
    }
}

pub struct Catalog {
    // In the order they were added.
    pub items: Vec<Item>,
}

impl Catalog {
    pub fn new() -> Catalog {
        Catalog { items: Vec::new() }
    }

    // The index of the book `id`.
    pub fn find(&self, id: i64) -> Option<usize> {
        for i in 0..self.items.len() {
            if self.items[i].id == id {
                return Some(i);
            }
        }
        None
    }

    // Adds `qty` copies of the book `id`, a new title or more of one the
    // library has; returns its copies now.
    pub fn add(&mut self, id: i64, title: &str, qty: i64) -> i64 {
        match self.find(id) {
            Some(i) => {
                self.items[i].qty += qty;
                self.items[i].qty
            }
            None => {
                self.items.push(Item { id: id, title: title.to_string(), qty: qty, lent: 0 });
                qty
            }
        }
    }

    // Copies owned, over every title.
    pub fn total_qty(&self) -> i64 {
        let mut n = 0;
        for it in &self.items {
            n += it.qty;
        }
        n
    }

    // Copies out on loan, over every title.
    pub fn total_lent(&self) -> i64 {
        let mut n = 0;
        for it in &self.items {
            n += it.lent;
        }
        n
    }
}
