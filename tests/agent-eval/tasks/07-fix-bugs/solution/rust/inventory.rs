// The stock: items kept sorted by SKU, found by binary search.

pub struct Item {
    pub sku: i64,
    pub name: String,
    pub price: i64, // cents
    pub stock: i64,
}

pub struct Inventory {
    pub items: Vec<Item>,
}

impl Inventory {
    pub fn new() -> Inventory {
        Inventory { items: Vec::new() }
    }

    pub fn add(&mut self, item: Item) {
        self.items.push(item);
    }

    // Puts the items in SKU order; `find` needs it.
    pub fn sort_by_sku(&mut self) {
        self.items.sort_by_key(|it| it.sku);
    }

    // The index of the item with this SKU, if there is one.
    pub fn find(&self, sku: i64) -> Option<usize> {
        let mut lo: i64 = 0;
        let mut hi: i64 = self.items.len() as i64 - 1;
        while lo <= hi {
            let mid = (lo + hi) / 2;
            let here = self.items[mid as usize].sku;
            if here == sku {
                return Some(mid as usize);
            }
            if here < sku {
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        None
    }

    // Takes `qty` units of item `index` out of stock; false (and nothing
    // taken) when there are not enough.
    pub fn take(&mut self, index: usize, qty: i64) -> bool {
        let item = &mut self.items[index];
        if item.stock < qty {
            return false;
        }
        item.stock -= qty;
        true
    }

    // One line per item, in SKU order: "  SKU NAME STOCK".
    pub fn report(&self, out: &mut String) {
        out.push_str("inventory\n");
        for item in &self.items {
            out.push_str("  ");
            out.push_str(&item.sku.to_string());
            out.push(' ');
            out.push_str(&item.name);
            out.push(' ');
            out.push_str(&item.stock.to_string());
            out.push('\n');
        }
    }
}
