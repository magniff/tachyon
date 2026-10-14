// The books the library owns: each title once, with its number of copies.

pub struct Book {
    pub id: i64,
    pub title: String,
    // Copies the library owns.
    pub copies: i64,
    // Copies out on loan.
    pub lent: i64,
}

impl Book {
    // Copies on the shelf.
    pub fn available(&self) -> i64 {
        self.copies - self.lent
    }
}

pub struct Catalog {
    // In the order they were added.
    pub items: Vec<Book>,
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

    // Adds `copies` copies of the book `id`, a new title or more of one the
    // library has; returns its copies now.
    pub fn add(&mut self, id: i64, title: &str, copies: i64) -> i64 {
        match self.find(id) {
            Some(i) => {
                self.items[i].copies += copies;
                self.items[i].copies
            }
            None => {
                self.items.push(Book { id: id, title: title.to_string(), copies: copies, lent: 0 });
                copies
            }
        }
    }

    // Copies owned, over every title.
    pub fn total_qty(&self) -> i64 {
        let mut n = 0;
        for it in &self.items {
            n += it.copies;
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
