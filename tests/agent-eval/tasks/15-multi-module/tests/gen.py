#!/usr/bin/env python3
# Writes the hidden test inputs of 15-multi-module (fixed seeds); the
# expected outputs come from the reference solution:
#   python3 gen.py && for f in *.in; do ../solution-binary < $f > ${f%.in}.out; done
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))


def write(name, text, crlf=False, final_newline=True):
    if crlf:
        text = text.replace("\n", "\r\n")
    if not final_newline:
        text = text.rstrip("\r\n")
    with open(os.path.join(HERE, name), "w", newline="") as f:
        f.write(text)


EXAMPLE = '''id:int,name:str,city:str,age:int
1,Ann,Oslo,34
2,Bob,"Rome, IT",
3,"Cy ""the kid""",Oslo,19
4,Dee,Rome,34
%%
SELECT name, age FROM t WHERE age >= 20 ORDER BY age DESC
SELECT city, COUNT(*), max(age) FROM t GROUP BY city ORDER BY COUNT(*) DESC
-- a comment
select * from t where age is null or name = 'Cy "the kid"'
SELECT COUNT(*), SUM(age), MIN(name) FROM t WHERE id > 10
SELECT name FROM t WHERE height > 3
SELECT name FROM t WHERE age > 'x'
SELECT name, COUNT(*) FROM t
SELECT name FROM t LIMIT
'''

# Quoting, odd fields, \r\n, a last line without a newline.
QUOTING = '''k:int,s:str,n:int
1,plain,10
2,"with, comma",20

3,"say ""hi""",
4,"",-5
5, spaced out ,7
6,mid"quote,8
7,"""",9
8,"a|b",0
9,,-0
10,"x"",""y",100
11,"",
%%
SELECT * FROM t
SELECT k, s FROM t WHERE s = ''
SELECT k FROM t WHERE s = ' spaced out '
SELECT k FROM t WHERE s = 'spaced out'
SELECT k, s FROM t WHERE s = 'mid"quote'
SELECT k, s FROM t WHERE s = '"'
SELECT s FROM t WHERE s = 'say "hi"'
SELECT s FROM t WHERE s = 'x","y'
SELECT k FROM t WHERE n IS NULL
SELECT k FROM t WHERE n IS NOT NULL AND n <= 0
SELECT COUNT(*), COUNT(n), COUNT(s), SUM(n), MIN(s), MAX(s), MIN(n), MAX(n) FROM t
SELECT s, n FROM t ORDER BY s
SELECT s, n FROM t ORDER BY s DESC, k DESC
SELECT n, COUNT(*) FROM t GROUP BY n ORDER BY n
SELECT s, COUNT(*) FROM t GROUP BY s ORDER BY COUNT(*) DESC, s LIMIT 3
'''

LOGIC = '''id:int,name:str,team:str,pts:int,bonus:int
1,ann,red,10,
2,bob,blue,-3,5
3,cid,red,,2
4,dee,green,7,7
5,eve,blue,10,-1
6,fay,red,0,
7,gus,green,-10,0
8,hal,,4,4
9,Ivy,red,10,10
10,jon,blue,,
%%
SELECT name FROM t WHERE pts = 10
SELECT name FROM t WHERE pts != 10
SELECT name FROM t WHERE pts < 0
SELECT name FROM t WHERE pts <= 0
SELECT name FROM t WHERE pts > -4 AND pts < 5
SELECT name FROM t WHERE pts >= -3
SELECT name FROM t WHERE NOT pts > 0
SELECT name FROM t WHERE NOT (pts > 0)
SELECT name FROM t WHERE pts = bonus
SELECT name FROM t WHERE pts != bonus
SELECT name FROM t WHERE team = 'red' OR team = 'blue' AND pts > 0
SELECT name FROM t WHERE (team = 'red' OR team = 'blue') AND pts > 0
SELECT name FROM t WHERE NOT team = 'red' AND NOT team = 'blue'
SELECT name FROM t WHERE NOT NOT team = 'red'
SELECT name FROM t WHERE team = ''
SELECT name FROM t WHERE team < 'green'
SELECT name FROM t WHERE name < 'b'
SELECT name FROM t WHERE name >= 'ann' AND name < 'cid'
SELECT name FROM t WHERE 'b' < name AND name < 'e'
SELECT name FROM t WHERE 1 = 1 AND pts IS NULL
SELECT name FROM t WHERE 1 = 2 OR bonus IS NULL
SELECT name FROM t WHERE 'x' IS NULL
SELECT name FROM t WHERE 5 IS NOT NULL AND id>8
select name from t where pts is not null and not (bonus is null) order by id desc
SeLeCt name FrOm t WhErE ((pts>0)) Or ((bonus>5)) LiMiT 4
SELECT name, pts FROM t WHERE pts>=-10AND pts<=-3
SELECT name FROM t WHERE name = 'ivy'
SELECT name FROM t WHERE name = 'Ivy'
SELECT name FROM t WHERE team = 'red' AND (pts = 10 OR pts IS NULL) AND NOT bonus = 10
'''

AGGS = '''g:str,h:int,v:int,w:str
a,1,5,pear
b,2,,fig
a,1,-2,apple
c,,7,kiwi
b,2,,date
a,3,10,fig
c,,1,
d,4,,lime
a,1,0,Zed
%%
SELECT COUNT(*) FROM t
SELECT COUNT(*), COUNT(v), SUM(v), MIN(v), MAX(v) FROM t
SELECT COUNT(v), SUM(v), MIN(v), MAX(v), MIN(w), MAX(w) FROM t WHERE g = 'b'
SELECT COUNT(*), SUM(v), MIN(w) FROM t WHERE g = 'zzz'
SELECT g, COUNT(*), SUM(v) FROM t GROUP BY g
SELECT h, COUNT(*), COUNT(h), SUM(v), MAX(w) FROM t GROUP BY h
SELECT g FROM t GROUP BY g
SELECT COUNT(*) FROM t GROUP BY g
SELECT g, MIN(w), MAX(w), MIN(v) FROM t WHERE v IS NOT NULL GROUP BY g
SELECT g, COUNT(*) FROM t WHERE h > 100 GROUP BY g
SELECT SUM(h), sum(v), Count(*), count(w), min(h), max(h) FROM t
SELECT MAX(v), MAX(v), COUNT(*) FROM t
SELECT g, h FROM t GROUP BY g
SELECT h FROM t GROUP BY h ORDER BY h DESC
SELECT g, SUM(v) FROM t GROUP BY g ORDER BY SUM(v) DESC
SELECT g, SUM(v) FROM t GROUP BY g ORDER BY SUM(v)
SELECT g, COUNT(*) FROM t GROUP BY g ORDER BY MAX(w) DESC
SELECT g, COUNT(*) FROM t GROUP BY g ORDER BY MIN(v) ASC, g DESC
'''

ORDERS = '''id:int,a:int,b:str,c:int
1,3,x,
2,1,y,5
3,3,x,2
4,,z,2
5,1,x,5
6,2,y,
7,3,y,1
8,,x,9
9,2,x,2
10,1,z,5
%%
SELECT id FROM t ORDER BY a
SELECT id FROM t ORDER BY a ASC
SELECT id FROM t ORDER BY a DESC
SELECT id, a, b FROM t ORDER BY b, a DESC
SELECT id, a, b FROM t ORDER BY b DESC, a
SELECT id FROM t ORDER BY c DESC, id DESC
SELECT id FROM t ORDER BY c, b DESC LIMIT 5
SELECT id FROM t ORDER BY b LIMIT 0
SELECT id FROM t ORDER BY b LIMIT 100
SELECT id FROM t LIMIT 3
SELECT b FROM t ORDER BY a, c
SELECT * FROM t WHERE a = 3 ORDER BY c
SELECT b, COUNT(*) FROM t GROUP BY b ORDER BY COUNT(*)
SELECT b, COUNT(*) FROM t GROUP BY b ORDER BY COUNT(*) DESC
SELECT a, COUNT(*), SUM(c) FROM t GROUP BY a ORDER BY a DESC
SELECT a, COUNT(*), SUM(c) FROM t GROUP BY a ORDER BY SUM(c), a
SELECT c FROM t GROUP BY c ORDER BY COUNT(*) DESC, c DESC LIMIT 2
SELECT COUNT(*) FROM t ORDER BY COUNT(*)
SELECT id FROM t WHERE id > 100 ORDER BY a
SELECT id FROM t ORDER BY a ASC, b ASC, c ASC, id DESC
'''

ERRORS = '''id:int,name:str,qty:int
1,ann,3
2,bob,
%%
SELECT
SELECT FROM t
SELECT name qty FROM t
SELECT name, FROM t
SELECT * , name FROM t
SELECT name FROM
SELECT name FROM t WHERE
SELECT name FROM t WHERE qty
SELECT name FROM t WHERE qty =
SELECT name FROM t WHERE (qty = 1
SELECT name FROM t WHERE qty = 1)
SELECT name FROM t WHERE qty IS 5
SELECT name FROM t WHERE qty IS NOT 5
SELECT name FROM t WHERE qty = NULL
SELECT name FROM t WHERE NOT
SELECT name FROM t WHERE qty = 1 AND
SELECT name FROM t WHERE qty == 1
SELECT name FROM t WHERE qty ! 1
SELECT name FROM t WHERE qty = 1;
SELECT FROM t WHERE qty = 1;
SELECT FROM t WHERE name = 'x
SELECT name FROM t WHERE qty IS NULL AND nope = 'x
SELECT name FROM t WHERE name = 'ann
SELECT name FROM t WHERE name = 'it''s
SELECT name FROM t WHERE name = 'it''s' AND qty = - 1
SELECT name FROM t WHERE name = "ann"
SELECT name FROM t WHERE (qty = 1) = 2
SELECT name FROM t.x
SELECT name FROM t GROUP name
SELECT name FROM t GROUP BY
SELECT name FROM t ORDER BY
SELECT name FROM t ORDER BY name ASC DESC
SELECT name FROM t ORDER name
SELECT name FROM t LIMIT -1
SELECT name FROM t LIMIT x
SELECT name FROM t LIMIT 5 WHERE qty = 1
SELECT name FROM t LIMIT 5 5
SELECT name FROM t ORDER BY name GROUP BY name
SELECT SUM(*) FROM t
SELECT COUNT() FROM t
SELECT COUNT(name FROM t
SELECT MAX name FROM t
SELECT name FROM t WHERE 'it''s' = name AND x
UPDATE t SET qty = 1
SELECT select FROM t
SELECT name FROM t extra
SELECT name FROM u
SELECT name FROM T
SELECT nope FROM u
SELECT nope FROM t
SELECT Name FROM t
SELECT name, nope FROM t WHERE qty > 'x'
SELECT name FROM t WHERE qty > 'x' AND zip = 1
SELECT name FROM t WHERE qty > 1 GROUP BY zip
SELECT name FROM t ORDER BY zap
SELECT SUM(zz) FROM t
SELECT name FROM t WHERE qty > 'x'
SELECT name FROM t WHERE 'x' < qty
SELECT name FROM t WHERE name = 1
SELECT name FROM t WHERE 1 = 'a' OR name = 2
SELECT SUM(name) FROM t
SELECT SUM(qty), SUM(name) FROM t WHERE qty = 'x'
SELECT name FROM t WHERE qty = 'x' ORDER BY SUM(name)
SELECT name FROM t ORDER BY SUM(name)
SELECT name, COUNT(*) FROM t
SELECT * FROM t GROUP BY name
SELECT COUNT(*), qty FROM t GROUP BY name
SELECT name FROM t GROUP BY qty
SELECT name, SUM(qty) FROM t WHERE qty > 'x' GROUP BY qty
SELECT name FROM t ORDER BY COUNT(*)
SELECT name FROM t GROUP BY name ORDER BY qty
SELECT name FROM t GROUP BY name ORDER BY name, qty
SELECT COUNT(*) FROM t ORDER BY name
SELECT name, qty FROM t ORDER BY qty LIMIT 1
'''

EMPTY = '''a:int,b:str
%%
SELECT * FROM t
SELECT a FROM t WHERE a > 0
SELECT COUNT(*), COUNT(a), SUM(a), MIN(b), MAX(a) FROM t
SELECT b, COUNT(*) FROM t GROUP BY b
SELECT COUNT(*) FROM t GROUP BY a
SELECT a FROM t ORDER BY b DESC LIMIT 0
SELECT nope FROM t
'''

COMMENTS = '''x:int,y:str
1,one
2,two
3,three
%%

-- comment at the start
   \t
SELECT x FROM t
--SELECT nothing
\tSELECT\tx ,y\tFROM t   WHERE x>1   ORDER BY y DESC
   -- an indented comment is not a comment
SELECT x,y FROM t WHERE y='two'OR x=1
SELECT COUNT(*)FROM t
SELECT(x)FROM t
SELECT x FROM t WHERE(x=1)OR(x=3)
SELECT x FROM t WHERE x>=2AND y<'tz'
SELECT x FROM t WHERE x>-1
SELECT x FROM t WHERE x>- 1
SELECT x FROM t WHERE x<-1
select X from t
SELECT x FROM t WHERE y = 'one' -- trailing
'''


WORDS = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo "
         "lima mike november oscar papa quebec romeo sierra tango uniform victor "
         "whiskey xray yankee zulu").split()


def rand_name(rng):
    n = rng.randint(1, 3)
    w = [rng.choice(WORDS) for _ in range(n)]
    s = " ".join(w)
    r = rng.random()
    if r < 0.05:
        s = s.capitalize()
    elif r < 0.08:
        s = s + ", jr"
    elif r < 0.10:
        s = 'the "' + s + '"'
    return s


def make_table(rng, nrows, schema, crlf=False):
    """schema: list of (name, type, generator)"""
    lines = [",".join("%s:%s" % (n, t) for n, t, _ in schema)]
    rows = []
    for i in range(nrows):
        row = []
        for n, t, g in schema:
            v = g(rng, i)
            if t == "int":
                row.append("" if v is None else str(v))
            else:
                if v.startswith('"') or "," in v or (rng.random() < 0.1 and '"' not in v):
                    row.append('"' + v.replace('"', '""') + '"')
                else:
                    row.append(v)
        lines.append(",".join(row))
    return lines


def lit(rng, ty, gen):
    if ty == "int":
        return str(rng.randint(-50, 1200))
    s = gen(rng, 0)
    if not isinstance(s, str):
        s = rng.choice(WORDS)
    if rng.random() < 0.3:
        s = s[: rng.randint(0, len(s))]
    return "'" + s.replace("'", "''") + "'"


def rand_cond(rng, schema, depth, err):
    r = rng.random()
    if depth > 0 and r < 0.25:
        op = rng.choice(["AND", "OR", "and", "Or"])
        return "%s %s %s" % (rand_cond(rng, schema, depth - 1, err), op,
                             rand_cond(rng, schema, depth - 1, err))
    if depth > 0 and r < 0.35:
        return "NOT " + rand_cond(rng, schema, depth - 1, err)
    if depth > 0 and r < 0.45:
        return "(" + rand_cond(rng, schema, depth - 1, err) + ")"
    n, t, g = rng.choice(schema)
    if rng.random() < 0.15:
        return "%s IS %sNULL" % (n, rng.choice(["", "NOT "]))
    op = rng.choice(["=", "!=", "<", "<=", ">", ">="])
    if rng.random() < 0.15:
        others = [s for s in schema if s[1] == t]
        m = rng.choice(others)[0]
        return "%s %s %s" % (n, op, m)
    ty = t
    if err and rng.random() < 0.05:
        ty = "str" if t == "int" else "int"
    v = lit(rng, ty, g)
    if rng.random() < 0.2:
        return "%s %s %s" % (v, op, n)
    return "%s %s %s" % (n, op, v)


def rand_query(rng, schema, err=True, small_out=True):
    names = [s[0] for s in schema]
    ints = [s[0] for s in schema if s[1] == "int"]
    parts = []
    grouped = rng.random() < 0.4
    group = None
    aggs_pool = []
    for n in names:
        aggs_pool += ["COUNT(%s)" % n, "MIN(%s)" % n, "MAX(%s)" % n]
    for n in ints:
        aggs_pool.append("SUM(%s)" % n)
    aggs_pool.append("COUNT(*)")
    if grouped:
        if rng.random() < 0.75:
            group = rng.choice(names)
        items = []
        if group and rng.random() < 0.8:
            items.append(group)
        for _ in range(rng.randint(0 if group else 1, 3)):
            items.append(rng.choice(aggs_pool))
        if not items:
            items.append(group)
        rng.shuffle(items)
    else:
        if rng.random() < 0.15:
            items = ["*"]
        else:
            items = rng.sample(names, rng.randint(1, min(4, len(names))))
    if err and rng.random() < 0.05:
        items.append("bogus")
    if err and rng.random() < 0.05 and grouped:
        items.append(rng.choice(names))
    q = "SELECT " + ", ".join(items) + " FROM t"
    if rng.random() < 0.7:
        q += " WHERE " + rand_cond(rng, schema, rng.randint(0, 3), err)
    if group:
        q += " GROUP BY " + group
    if rng.random() < 0.7:
        keys = []
        for _ in range(rng.randint(1, 3)):
            if grouped:
                k = group if (group and rng.random() < 0.4) else rng.choice(aggs_pool)
            else:
                k = rng.choice(names)
            keys.append(k + rng.choice(["", "", " ASC", " DESC"]))
        q += " ORDER BY " + ", ".join(keys)
    if small_out or rng.random() < 0.6:
        q += " LIMIT %d" % rng.choice([0, 1, 3, 5, 10, 20])
    if err and rng.random() < 0.04:
        # chop the query somewhere
        q = q[: rng.randint(6, len(q))]
    if rng.random() < 0.2:
        q = q.replace("SELECT", "select").replace("FROM", "from").replace("WHERE", "where")
    return q


def schema_a(rng_nulls):
    return [
        ("id", "int", lambda r, i: i * 7 % 1009 + 1),
        ("name", "str", lambda r, i: rand_name(r)),
        ("dept", "str", lambda r, i: r.choice(["eng", "ops", "sales", "hr", "legal", "Eng", ""])),
        ("age", "int", lambda r, i: None if r.random() < rng_nulls else r.randint(18, 70)),
        ("salary", "int", lambda r, i: None if r.random() < rng_nulls else r.randint(-50, 1200) * 10),
        ("city", "str", lambda r, i: r.choice(["Oslo", "Rome", "Lima", "Kyiv", "Pune", "Rome, IT", "oslo"])),
    ]


def schema_b():
    return [
        ("code", "str", lambda r, i: "%c%c%d" % (r.choice("ABCDE"), r.choice("xyz"), r.randint(0, 99))),
        ("n", "int", lambda r, i: r.randint(-5, 5)),
        ("m", "int", lambda r, i: None if r.random() < 0.3 else r.randint(0, 1000)),
        ("tag", "str", lambda r, i: r.choice(["a", "b", "ab", "B", "", "a b", "a,b"])),
    ]


def random_test(name, seed, nrows, nq, schema_fn, crlf=False):
    rng = random.Random(seed)
    schema = schema_fn(rng)
    lines = make_table(rng, nrows, schema)
    lines.append("%%")
    for _ in range(nq):
        lines.append(rand_query(rng, schema))
    write(name, "\n".join(lines) + "\n", crlf=crlf)


def big_test(name, seed, nrows):
    rng = random.Random(seed)
    schema = [
        ("id", "int", lambda r, i: (i * 7919) % nrows),
        ("name", "str", lambda r, i: rand_name(r)),
        ("dept", "str", lambda r, i: r.choice(["eng", "ops", "sales", "hr", "legal", "it", "pr", "rd"])),
        ("age", "int", lambda r, i: None if r.random() < 0.05 else r.randint(18, 70)),
        ("score", "int", lambda r, i: None if r.random() < 0.05 else r.randint(-1000, 1000)),
        ("code", "str", lambda r, i: "c%05d" % ((i * 4271) % (nrows - 7))),
    ]
    lines = make_table(rng, nrows, schema)
    lines.append("%%")
    heavy = [
        "SELECT id, COUNT(*) FROM t GROUP BY id ORDER BY id DESC LIMIT 5",
        "SELECT code, COUNT(*) FROM t GROUP BY code ORDER BY COUNT(*) DESC, code LIMIT 10",
        "SELECT code FROM t GROUP BY code ORDER BY code LIMIT 5",
        "SELECT name, COUNT(*), SUM(score), MIN(age), MAX(code) FROM t GROUP BY name ORDER BY COUNT(*) DESC, name LIMIT 10",
        "SELECT id, name FROM t ORDER BY name, id DESC LIMIT 10",
        "SELECT id, score FROM t ORDER BY score DESC LIMIT 10",
        "SELECT id FROM t ORDER BY dept, age DESC LIMIT 10",
        "SELECT id, age FROM t ORDER BY age LIMIT 15",
        "SELECT name FROM t ORDER BY code DESC LIMIT 5",
        "SELECT score, COUNT(*) FROM t GROUP BY score ORDER BY COUNT(*) DESC, score LIMIT 10",
        "SELECT age, COUNT(*), SUM(score) FROM t GROUP BY age ORDER BY age",
        "SELECT dept, COUNT(*), COUNT(age), SUM(score), MIN(name), MAX(name) FROM t GROUP BY dept ORDER BY dept",
        "SELECT COUNT(*), SUM(score), MIN(score), MAX(score), MIN(code), MAX(code) FROM t",
        "SELECT id, dept FROM t WHERE dept = 'hr' ORDER BY id",
    ]
    qs = []
    for q in heavy:
        qs.append(q)
    for _ in range(100 - len(heavy)):
        qs.append(rand_query(rng, schema, err=True, small_out=True))
    rng.shuffle(qs)
    lines += qs
    write(name, "\n".join(lines) + "\n")


def main():
    write("01.in", EXAMPLE)
    write("02.in", QUOTING, crlf=True, final_newline=False)
    write("03.in", LOGIC)
    write("04.in", AGGS)
    write("05.in", ORDERS)
    write("06.in", ERRORS)
    write("07.in", EMPTY)
    write("08.in", COMMENTS)
    random_test("09.in", 9, 300, 150, lambda r: schema_a(0.15))
    random_test("10.in", 10, 500, 150, lambda r: schema_b(), crlf=True)
    big_test("11.in", 11, 18000)
    big_test("12.in", 12, 17000)


if __name__ == "__main__":
    main()
