#!/usr/bin/env python3
# Writes the hidden test inputs of 07-fix-bugs (fixed seeds); the expected
# outputs come from the reference solution.
import random

def write(name, items, orders):
    lines = [f"items {len(items)}"]
    for sku, price, stock, nm in items:
        lines.append(f"{sku} {price} {stock} {nm}")
    lines.append(f"orders {len(orders)}")
    for cust, tier, ol in orders:
        lines.append(f"{cust} {tier} {len(ol)}")
        for sku, qty in ol:
            lines.append(f"{sku} {qty}")
    open(name, "w").write("\n".join(lines) + "\n")

WORDS = ["bolt", "nut", "gear", "lamp", "cable", "valve", "pump", "fan", "hinge", "spring", "plug", "drill"]
TIERS = ["basic", "silver", "gold"]

def random_case(seed, nitems, norders, maxlines, stock_hi, price_hi):
    rng = random.Random(seed)
    skus = rng.sample(range(1, 10 * nitems + 10), nitems)
    items = [(s, rng.randint(1, price_hi), rng.randint(0, stock_hi), rng.choice(WORDS) + str(i)) for i, s in enumerate(skus)]
    lo, hi = min(skus), max(skus)
    orders = []
    for k in range(norders):
        ol = []
        for _ in range(rng.randint(0, maxlines)):
            r = rng.random()
            if r < 0.08:
                sku = rng.choice([lo - 1, hi + 1, rng.randint(lo, hi)])  # often unknown
            elif r < 0.15:
                sku = rng.choice([lo, hi])
            else:
                sku = rng.choice(skus)
            ol.append((sku, rng.randint(1, 12)))
        orders.append((f"c{k % 997}", rng.choice(TIERS), ol))
    return items, orders

# 09: large: binary search must be fast, accumulators reset across many orders
write("09.in", *random_case(7, 20000, 6000, 6, 60, 9000))
# 10: medium, tight stock: many "short" lines
write("10.in", *random_case(11, 300, 2000, 5, 8, 4000))
# 11: small inventory, every lookup near the ends of the search range
write("11.in", *random_case(23, 3, 200, 4, 30, 6000))
