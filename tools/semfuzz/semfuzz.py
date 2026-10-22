#!/usr/bin/env python3
"""The semantics fuzzer (0.25): random well-typed vole programs over owned
values, each with the outcome its value semantics give, computed here.

A program is generated as a tree (the classes below) that is both printed
as vole and run by a small interpreter of the value semantics: moves,
copies, clones, inout accesses, sink parameters, drops at scope end in
reverse declaration order, temporaries at the end of their statement,
drop flags of conditionally moved locals, early returns and `?`. The
interpreter gives the expected output: every observation the program
prints (`o<N> ...`) and every drop of a Tracked value (`d<id>`), in order
where the order is specified (an enum's payload: a set), and at the end
`live 0`. The program is then compiled at several levels and job counts
with --check-alloc, run, and compared with the expectation and with each
other. Failing programs are shrunk (statements deleted while the failure
stays the same) and kept.

usage: tools/semfuzz/semfuzz.py [-c VOLEC] [-n COUNT] [-f FIRST] [-k DIR]
                                [-j JOBS] [--known] [--no-shrink]
                                [--print SEED] [--levels L,..]

  -c VOLEC     the compiler (default: target/volec)
  -n COUNT     programs (default 100); -f FIRST: the first seed (default 1)
  -k DIR       where failing programs are kept (default tests/fuzz/failures/sem)
  -j JOBS      programs at once (default: $VOLE_JOBSERVER's slots, or the CPUs)
  --known      also generate the constructs of known bugs (see KNOWN)
  --print SEED print the program of SEED and its expected output, and stop
  --size N     statements in run's body, about (default 24)

Exit status: 0 when every program behaved as expected.
"""

import argparse
import concurrent.futures
import os
import random
import shutil
import subprocess
import sys
import tempfile
import threading

MASK = (1 << 64) - 1


def wrap(x):
    x &= MASK
    return x - (1 << 64) if x >> 63 else x


def cmod(a, b):
    """vole's %: C's (truncated), and x % 0 == x."""
    if b == 0:
        return a
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return wrap(a - b * q)


# Known bugs: constructs the generator leaves out unless --known, each a
# tests/run/sem_fuzz_*.vl case with its XFAIL.
KNOWN = {
    # `?` on a borrowed Option (Vec::last) drops the element
    'last_question': 'sem_fuzz_last_question_double_drop',
    # a by-value match that binds only part of the payload leaks the rest
    'match_wild': 'sem_fuzz_match_wildcard_leak',
    # an owned temporary passed to a let parameter lives to the end of the
    # block, not of its statement (and two such in a statement are rejected)
    'temp_let_arg': 'sem_fuzz_temp_let_arg',
    # `w[i] = x` and `w.set(i, x)` do not drop the old element
    'index_assign': 'sem_fuzz_index_assign_leak',
}


class Invalid(Exception):
    """The model's own check: the program uses a moved value (a shrunk
    candidate that is not a program)."""


class _Moved:
    def __repr__(self):
        return 'MOVED'


MOVED = _Moved()


# ---------------------------------------------------------------- values

class TV:
    __slots__ = ('id', 'v')

    def __init__(self, id, v):
        self.id = id
        self.v = v


class SV:
    __slots__ = ('t', 'w', 'n')

    def __init__(self, t, w, n):
        self.t = t
        self.w = w
        self.n = n


class EV:
    __slots__ = ('tag', 'items')

    def __init__(self, tag, items):
        self.tag = tag
        self.items = items


class OV:
    __slots__ = ('val',)

    def __init__(self, val):
        self.val = val


class RV:
    __slots__ = ('ok', 'val')

    def __init__(self, ok, val):
        self.ok = ok
        self.val = val


class PV:
    __slots__ = ('x', 'y')

    def __init__(self, x, y):
        self.x = x
        self.y = y


class StrV:
    __slots__ = ('s',)

    def __init__(self, s):
        self.s = s


class CloV:
    """A sink closure: its capture is its own."""
    __slots__ = ('cap', 'k')

    def __init__(self, cap, k):
        self.cap = cap
        self.k = k


def copy_plain(v):
    if type(v) is PV:
        return PV(v.x, v.y)
    return v


def is_plain(v):
    return type(v) in (int, bool, PV)


# ---------------------------------------------------------------- places

class Cell:
    __slots__ = ('val', 'owned')

    def __init__(self, val, owned=True):
        self.val = val
        self.owned = owned

    def get(self):
        return self.val

    def set(self, v):
        self.val = v


class AliasCell:
    """A let or inout parameter: the caller's place, never dropped here."""
    __slots__ = ('place', 'owned')

    def __init__(self, place):
        self.place = place
        self.owned = False

    def get(self):
        return self.place.get()

    def set(self, v):
        self.place.set(v)


class AttrPlace:
    __slots__ = ('obj', 'attr')

    def __init__(self, obj, attr):
        self.obj = obj
        self.attr = attr

    def get(self):
        return getattr(self.obj, self.attr)

    def set(self, v):
        setattr(self.obj, self.attr, v)


class IdxPlace:
    __slots__ = ('lst', 'i')

    def __init__(self, lst, i):
        self.lst = lst
        self.i = i

    def get(self):
        return self.lst[self.i]

    def set(self, v):
        self.lst[self.i] = v


class ReturnEx(Exception):
    def __init__(self, val):
        self.val = val


class BreakEx(Exception):
    pass


class ContinueEx(Exception):
    pass


class Frame:
    def __init__(self):
        self.scopes = []

    def lookup(self, name):
        for sc in reversed(self.scopes):
            for n, c in reversed(sc):
                if n == name:
                    return c
        raise Invalid('no variable ' + name)


class Interp:
    def __init__(self, prog):
        self.prog = prog
        self.ev = []
        self.next_id = 0
        self.live = 0
        self.steps = 0
        self.temps = [[]]

    def tick(self):
        self.steps += 1
        if self.steps > 200000:
            raise Invalid('runs too long')

    def line(self, s):
        self.ev.append(('l', s))

    def mk(self, v):
        self.next_id += 1
        self.live += 1
        return TV(self.next_id, v)

    def clone(self, v):
        t = type(v)
        if v is MOVED:
            raise Invalid('clone of a moved value')
        if t is TV:
            return self.mk(v.v)
        if t is list:
            return [self.clone(e) for e in v]
        if t is SV:
            return SV(self.clone(v.t), self.clone(v.w), v.n)
        if t is EV:
            return EV(v.tag, [self.clone(e) for e in v.items])
        if t is OV:
            return OV(None if v.val is None else self.clone(v.val))
        if t is StrV:
            return StrV(v.s)
        if t is PV:
            return PV(v.x, v.y)
        return v

    def drop(self, v):
        if v is MOVED or v is None:
            return
        t = type(v)
        if t is TV:
            self.live -= 1
            self.line('d%d' % v.id)
        elif t is list:
            for e in v:
                self.drop(e)
        elif t is SV:
            self.drop(v.t)
            self.drop(v.w)
        elif t is EV:
            items = [e for e in v.items if e is not MOVED]
            if len(items) >= 2:
                # (the order of an enum's payload is not specified)
                saved = self.ev
                self.ev = []
                for e in items:
                    self.drop(e)
                group = [s for _, s in self.ev]
                self.ev = saved
                self.ev.append(('s', group))
            else:
                for e in items:
                    self.drop(e)
        elif t is OV:
            self.drop(v.val)
        elif t is RV:
            self.drop(v.val)
        elif t is CloV:
            self.drop(v.cap)

    def drop_scope(self, sc):
        for _, c in reversed(sc):
            if c.owned:
                v = c.val
                c.val = MOVED
                self.drop(v)

    def run(self):
        fr = Frame()
        fr.scopes.append([('gpa', Cell(0, owned=False))])
        self.prog.run_fn.body.run(self, fr)
        self.line('live %d' % self.live)
        return self.ev


def rd(v):
    if v is MOVED:
        raise Invalid('read of a moved value')
    if type(v) is SV and (v.t is MOVED or v.w is MOVED):
        raise Invalid('read of a partly moved struct')
    return v


# ---------------------------------------------------------------- places (tree)

class PVar:
    def __init__(self, name):
        self.name = name

    def code(self):
        return self.name

    def place(self, it, fr):
        return fr.lookup(self.name)

    def root(self):
        return self.name


class PField:
    def __init__(self, base, f):
        self.base = base
        self.f = f

    def code(self):
        return '%s.%s' % (self.base.code(), self.f)

    def place(self, it, fr):
        obj = self.base.place(it, fr).get()
        if obj is MOVED:
            raise Invalid('field of a moved value')
        return AttrPlace(obj, self.f)

    def root(self):
        return self.base.root()


class PIdx:
    def __init__(self, base, i):
        self.base = base
        self.i = i

    def code(self):
        return '%s[%d]' % (self.base.code(), self.i)

    def place(self, it, fr):
        lst = rd(self.base.place(it, fr).get())
        if self.i >= len(lst):
            raise Invalid('index out of bounds (unguarded)')
        return IdxPlace(lst, self.i)

    def root(self):
        return self.base.root()


# ---------------------------------------------------------------- expressions

class E:
    """An expression: code() and ev(it, fr)."""
    pass


class Lit(E):
    def __init__(self, n):
        self.n = n

    def code(self):
        return str(self.n) if self.n >= 0 else '(%d)' % self.n

    def ev(self, it, fr):
        return self.n


class BoolLit(E):
    def __init__(self, b):
        self.b = b

    def code(self):
        return 'true' if self.b else 'false'

    def ev(self, it, fr):
        return self.b


class Read(E):
    """A place read as a value: `x.v`, `n`; a plain value is copied."""
    def __init__(self, p):
        self.p = p

    def code(self):
        return self.p.code()

    def ev(self, it, fr):
        return copy_plain(rd(self.p.place(it, fr).get()))


class Move(E):
    """`x` where an owned value moves (a plain one is copied)."""
    def __init__(self, p):
        self.p = p

    def code(self):
        return self.p.code()

    def ev(self, it, fr):
        pl = self.p.place(it, fr)
        v = rd(pl.get())
        if is_plain(v):
            return copy_plain(v)
        pl.set(MOVED)
        return v


class Bin(E):
    def __init__(self, a, op, b):
        self.a = a
        self.op = op
        self.b = b

    def code(self):
        return '(%s %s %s)' % (self.a.code(), self.op, self.b.code())

    def ev(self, it, fr):
        a = self.a.ev(it, fr)
        b = self.b.ev(it, fr)
        op = self.op
        if op == '+':
            return wrap(a + b)
        if op == '-':
            return wrap(a - b)
        if op == '*':
            return wrap(a * b)
        if op == '%':
            return cmod(a, b)
        if op == '==':
            return a == b
        if op == '!=':
            return a != b
        if op == '<':
            return a < b
        if op == '>':
            return a > b
        if op == '&&':
            return a and b
        raise ValueError(op)


class Arg:
    """An argument: conv 'let' (a place or, for a plain value, an
    expression), 'inout' (a place, `&p`), 'sink' or 'val' (an expression)."""
    def __init__(self, conv, x):
        self.conv = conv
        self.x = x

    def code(self):
        if self.conv == 'inout':
            return '&' + self.x.code()
        return self.x.code()


def eval_args(it, fr, args):
    out = []
    for a in args:
        if a.conv == 'inout':
            pl = a.x.place(it, fr)
            rd(pl.get())
            out.append(pl)
        elif a.conv == 'let' and isinstance(a.x, (PVar, PField, PIdx)):
            pl = a.x.place(it, fr)
            rd(pl.get())
            out.append(pl)
        elif a.conv == 'let':
            # a temporary lent to the call: dropped at the end of the
            # statement
            v = a.x.ev(it, fr)
            if not is_plain(v):
                it.temps[-1].append(v)
                out.append(Cell(v, owned=False))
            else:
                out.append(v)
        else:
            out.append(a.x.ev(it, fr))
    return out


def val(x):
    """A let argument's value (a place, or a temporary)."""
    if isinstance(x, (Cell, AliasCell, AttrPlace, IdxPlace)):
        return rd(x.get())
    return x


class Call(E):
    """A call of one of the header's functions, or a method: its meaning
    is HELPERS[name]."""
    def __init__(self, name, args, method=False, recv=None, recv_conv='let'):
        self.name = name
        self.args = args
        self.method = method
        self.recv = recv
        self.recv_conv = recv_conv

    def code(self):
        a = ', '.join(x.code() for x in self.args)
        if self.method:
            return '%s.%s(%s)' % (self.recv.code(), self.name, a)
        return '%s(%s)' % (self.name, a)

    def ev(self, it, fr):
        args = eval_args(it, fr, self.args)
        recv = None
        if self.method:
            # (the receiver is taken after the arguments)
            if self.recv_conv == 'sink':
                recv = self.recv.ev(it, fr)
            else:
                recv = self.recv.place(it, fr)
                rd(recv.get())
        return HELPERS[self.name](it, recv, *args)


def h_obs(it, r, t):
    return val(t).v


def h_bump(it, r, t, k):
    x = rd(t.get())
    x.v = wrap(x.v + k)


def h_eat(it, r, t):
    n = t.v
    it.drop(t)
    return n


def h_ident(it, r, t):
    return t


def h_vsig(it, r, w):
    h = 7
    for x in val(w):
        h = wrap(wrap(h * 31) + wrap(x.id * 100) + x.v)
    return h


def h_vbump(it, r, w, k):
    for x in rd(w.get()):
        x.v = wrap(x.v + k)


def h_veat(it, r, w):
    n = len(w)
    it.drop(w)
    return n


def h_keep(it, r, w, t):
    rd(w.get()).append(t)


def h_pick(it, r, a, b, c):
    if c:
        it.drop(b)
        return a
    it.drop(a)
    return b


def h_ssig(it, r, s):
    s = rd(val(s))
    return wrap(wrap(s.t.id * 1000) + wrap(s.t.v * 7) + h_vsig(it, None, s.w) + s.n)


def h_esig(it, r, e):
    e = val(e)
    if e.tag == 'One':
        a = e.items[0]
        return wrap(a.id * 10 + a.v)
    if e.tag == 'Two':
        a, b = e.items
        return wrap(a.id * 100 + b.id * 10 + a.v - b.v)
    return -3


def h_osig(it, r, o):
    o = val(o)
    if o.val is None:
        return -1
    return wrap(o.val.id * 10 + o.val.v)


def h_total(it, r, x):
    x = val(x)
    if type(x) is TV:
        return wrap(x.v * 2 + 1)
    return wrap(x.t.v + len(x.w) + x.n)


def h_gid(it, r, x):
    return x


def h_chk(it, r, t, lim):
    t = val(t)
    if t.v > lim:
        return RV(False, t.v)
    return RV(True, wrap(t.v + 1))


def h_tchk(it, r, t, lim):
    if t.v > lim:
        n = t.v
        it.drop(t)
        return RV(False, n)
    return RV(True, t)


def h_pget(it, r, p):
    p = val(p)
    return wrap(p.x * 10 + p.y)


def h_pbump(it, r, p, k):
    x = rd(p.get())
    x.x = wrap(x.x + k)


def h_psink(it, r, p):
    p.x = wrap(p.x + 1)
    return wrap(p.x * 10 + p.y)


def h_seat(it, r, s):
    return len(s.s)


def h_callf(it, r, f):
    n = wrap(f.cap.v + f.k)
    it.drop(f)
    return n


# methods: recv is a place (let, inout) or a value (sink)

def m_get(it, r):
    return rd(r.get()).v


def m_add(it, r, k):
    x = rd(r.get())
    x.v = wrap(x.v + k)


def m_into_v(it, r):
    n = r.v
    it.drop(r)
    return n


def m_clone(it, r):
    return it.clone(rd(r.get()))


def m_push(it, r, x):
    rd(r.get()).append(x)


def m_pop(it, r):
    w = rd(r.get())
    return OV(w.pop() if w else None)


def m_remove(it, r, i):
    w = rd(r.get())
    if i >= len(w):
        raise Invalid('remove out of bounds (unguarded)')
    return w.pop(i)


def m_insert(it, r, i, x):
    w = rd(r.get())
    if i > len(w):
        raise Invalid('insert out of bounds (unguarded)')
    w.insert(i, x)


def m_truncate(it, r, n):
    w = rd(r.get())
    if 0 <= n < len(w):
        rest = w[n:]
        del w[n:]
        for e in rest:
            it.drop(e)


def m_clear(it, r):
    m_truncate(it, r, 0)


def m_swap(it, r, i, j):
    w = rd(r.get())
    if i >= len(w) or j >= len(w):
        raise Invalid('swap out of bounds (unguarded)')
    w[i], w[j] = w[j], w[i]


def m_set(it, r, i, x):
    w = rd(r.get())
    if i >= len(w):
        raise Invalid('set out of bounds (unguarded)')
    old = w[i]
    w[i] = x
    it.drop(old)


def m_len(it, r):
    v = rd(r.get())
    if type(v) is StrV:
        return len(v.s)
    return len(v)


def m_is_some(it, r):
    return rd(r.get()).val is not None


def m_unwrap_or(it, r, other):
    o = r
    if o.val is not None:
        it.drop(other)
        return o.val
    return other


def m_push_str(it, r, s):
    x = rd(r.get())
    x.s = x.s + s


def h_swap(it, r, a, b):
    va = rd(a.get())
    vb = rd(b.get())
    a.set(vb)
    b.set(va)


def h_replace(it, r, dest, v):
    old = rd(dest.get())
    dest.set(v)
    return old


def h_drop(it, r, x):
    it.drop(x)


HELPERS = {
    'obs': h_obs, 'bump': h_bump, 'eat': h_eat, 'ident': h_ident,
    'vsig': h_vsig, 'vbump': h_vbump, 'veat': h_veat, 'keep': h_keep,
    'pick': h_pick, 'ssig': h_ssig, 'esig': h_esig, 'osig': h_osig,
    'total': h_total, 'gid': h_gid, 'chk': h_chk, 'tchk': h_tchk,
    'pget': h_pget, 'pbump': h_pbump, 'psink': h_psink, 'seat': h_seat,
    'callf': h_callf, 'std::swap': h_swap, 'std::replace': h_replace,
    'drop': h_drop,
    'get': m_get, 'add': m_add, 'into_v': m_into_v, 'clone': m_clone,
    'push': m_push, 'pop': m_pop, 'remove': m_remove, 'insert': m_insert,
    'truncate': m_truncate, 'clear': m_clear, 'swap': m_swap, 'set': m_set,
    'len': m_len, 'is_some': m_is_some, 'unwrap_or': m_unwrap_or,
    'push_str': m_push_str,
}


class Mk(E):
    def __init__(self, k):
        self.k = k

    def code(self):
        return 'mk(%s)' % self.k.code()

    def ev(self, it, fr):
        return it.mk(self.k.ev(it, fr))


class NewVec(E):
    def code(self):
        return 'Vec::new_in(gpa)'

    def ev(self, it, fr):
        return []


class NewS(E):
    def __init__(self, t, w, n):
        self.t = t
        self.w = w
        self.n = n

    def code(self):
        return 'S { t: %s, w: %s, n: %d }' % (self.t.code(), self.w.code(), self.n)

    def ev(self, it, fr):
        t = self.t.ev(it, fr)
        w = self.w.ev(it, fr)
        return SV(t, w, self.n)


class NewE(E):
    def __init__(self, tag, items):
        self.tag = tag
        self.items = items

    def code(self):
        if self.tag == 'Nada':
            return 'E::Nada'
        return 'E::%s(%s)' % (self.tag, ', '.join(x.code() for x in self.items))

    def ev(self, it, fr):
        return EV(self.tag, [x.ev(it, fr) for x in self.items])


class NewO(E):
    def __init__(self, x):
        self.x = x

    def code(self):
        return 'None' if self.x is None else 'Some(%s)' % self.x.code()

    def ev(self, it, fr):
        return OV(None if self.x is None else self.x.ev(it, fr))


class NewP(E):
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def code(self):
        return 'Pt { x: %d, y: %d }' % (self.x, self.y)

    def ev(self, it, fr):
        return PV(self.x, self.y)


class NewStr(E):
    def __init__(self, s):
        self.s = s

    def code(self):
        return 'String::from_in("%s", gpa)' % self.s

    def ev(self, it, fr):
        return StrV(self.s)


class Wrap(E):
    """`Some(e)`, `Ok(e)`, `Err(e)`, `None` as a function's result."""
    def __init__(self, kind, x):
        self.kind = kind
        self.x = x

    def code(self):
        if self.kind == 'None':
            return 'None'
        return '%s(%s)' % (self.kind, self.x.code())

    def ev(self, it, fr):
        if self.kind == 'None':
            return OV(None)
        v = self.x.ev(it, fr)
        if self.kind == 'Some':
            return OV(v)
        return RV(self.kind == 'Ok', v)


class Unres(E):
    """An int from an Option<i64> or a Result<i64, i64> call: `match e {
    Some(n) => n, None => -7 }`."""
    def __init__(self, x, kind):
        self.x = x
        self.kind = kind

    def code(self):
        if self.kind == 'OI':
            return 'match %s { Some(q) => q, None => -7 }' % self.x.code()
        return 'match %s { Ok(q) => q, Err(q) => -q }' % self.x.code()

    def ev(self, it, fr):
        v = self.x.ev(it, fr)
        if self.kind == 'OI':
            return -7 if v.val is None else v.val
        return v.val if v.ok else wrap(-v.val)


class CloCall(E):
    """`f()` of a sink closure local: its capture's v plus k."""
    def __init__(self, name):
        self.name = name

    def code(self):
        return '%s()' % self.name

    def ev(self, it, fr):
        f = rd(fr.lookup(self.name).get())
        return wrap(rd(f.cap).v + f.k)


class NewClo(E):
    """`sink || x.v + k`: x moves into the closure."""
    def __init__(self, p, k):
        self.p = p
        self.k = k

    def code(self):
        return 'sink || %s.v + %d' % (self.p.code(), self.k)

    def ev(self, it, fr):
        pl = self.p.place(it, fr)
        v = rd(pl.get())
        pl.set(MOVED)
        return CloV(v, self.k)


class Apply(E):
    """`apply(|a: i64| obs(x) + a, k)`: a closure borrowing x."""
    def __init__(self, p, k):
        self.p = p
        self.k = k

    def code(self):
        return 'apply(|a: i64| obs(%s) + a, %d)' % (self.p.code(), self.k)

    def ev(self, it, fr):
        return wrap(rd(self.p.place(it, fr).get()).v + self.k)


class IterSum(E):
    def __init__(self, p, kind, k=0):
        self.p = p
        self.kind = kind
        self.k = k

    def code(self):
        if self.kind == 'sum':
            return '%s.iter().map(|t| t.v).sum()' % self.p.code()
        return '%s.iter().filter(|t| t.v > %d).count()' % (self.p.code(), self.k)

    def ev(self, it, fr):
        w = rd(self.p.place(it, fr).get())
        if self.kind == 'sum':
            s = 0
            for x in w:
                s = wrap(s + x.v)
            return s
        return sum(1 for x in w if x.v > self.k)


class CallGen(E):
    def __init__(self, fn, args):
        self.fn = fn
        self.args = args

    def code(self):
        return '%s(%s)' % (self.fn.name, ', '.join(['gpa'] + [a.code() for a in self.args]))

    def ev(self, it, fr):
        vals = eval_args(it, fr, self.args)
        nf = Frame()
        sc = [('gpa', Cell(0, owned=False))]
        for (pname, conv, ty), v in zip(self.fn.params, vals):
            if conv in ('let', 'inout') and isinstance(v, (Cell, AliasCell, AttrPlace, IdxPlace)):
                sc.append((pname, AliasCell(v)))
            else:
                sc.append((pname, Cell(copy_plain(v), owned=True)))
        nf.scopes.append(sc)
        try:
            try:
                r = self.fn.body.run(it, nf)
            except ReturnEx as e:
                r = e.val
        finally:
            nf.scopes.pop()
            it.drop_scope(sc)
        return r


# ---------------------------------------------------------------- statements

class S_:
    pass


class Decl(S_):
    def __init__(self, name, mut, ann, init):
        self.name = name
        self.mut = mut
        self.ann = ann
        self.init = init

    def emit(self, out, ind):
        a = ': ' + self.ann if self.ann else ''
        out.append('%s%s %s%s = %s;' % (ind, 'var' if self.mut else 'let', self.name, a, self.init.code()))

    def run(self, it, fr):
        v = self.init.ev(it, fr)
        fr.scopes[-1].append((self.name, Cell(v)))


class Assign(S_):
    def __init__(self, p, x):
        self.p = p
        self.x = x

    def emit(self, out, ind):
        out.append('%s%s = %s;' % (ind, self.p.code(), self.x.code()))

    def run(self, it, fr):
        v = self.x.ev(it, fr)
        pl = self.p.place(it, fr)
        old = pl.get()
        pl.set(v)
        it.drop(old)


class OpAssign(S_):
    def __init__(self, p, k):
        self.p = p
        self.k = k

    def emit(self, out, ind):
        out.append('%s%s += %s;' % (ind, self.p.code(), self.k.code()))

    def run(self, it, fr):
        k = self.k.ev(it, fr)
        pl = self.p.place(it, fr)
        pl.set(wrap(rd(pl.get()) + k))


class Do(S_):
    """An expression statement: an owned result is a temporary, dropped
    at the end of the statement."""
    def __init__(self, x):
        self.x = x

    def emit(self, out, ind):
        out.append('%s%s;' % (ind, self.x.code()))

    def run(self, it, fr):
        v = self.x.ev(it, fr)
        it.drop(v)


class Print(S_):
    def __init__(self, n, holes):
        self.n = n
        self.holes = holes

    def emit(self, out, ind):
        hs = ''.join(' {%s}' % h.code() for h in self.holes)
        out.append('%sprintln(f"o%d%s");' % (ind, self.n, hs))

    def run(self, it, fr):
        vals = []
        for h in self.holes:
            v = h.ev(it, fr)
            if type(v) is StrV:
                vals.append(v.s)
            elif type(v) is bool:
                vals.append('true' if v else 'false')
            else:
                vals.append(str(v))
        it.line('o%d%s' % (self.n, ''.join(' ' + v for v in vals)))


class Block(S_):
    def __init__(self, stmts, tail=None):
        self.stmts = stmts
        self.tail = tail

    def emit_body(self, out, ind):
        for s in self.stmts:
            s.emit(out, ind)
        if self.tail is not None:
            out.append(ind + self.tail.code())

    def emit(self, out, ind):
        out.append(ind + '{')
        self.emit_body(out, ind + '    ')
        out.append(ind + '}')

    def run(self, it, fr, pre=None):
        sc = list(pre or [])
        fr.scopes.append(sc)
        r = None
        try:
            for s in self.stmts:
                it.tick()
                it.temps.append([])
                try:
                    s.run(it, fr)
                finally:
                    for v in reversed(it.temps.pop()):
                        it.drop(v)
            if self.tail is not None:
                r = self.tail.ev(it, fr)
        finally:
            fr.scopes.pop()
            it.drop_scope(sc)
        return r


class If(S_):
    def __init__(self, cond, then, els):
        self.cond = cond
        self.then = then
        self.els = els

    def emit(self, out, ind):
        out.append('%sif %s {' % (ind, self.cond.code()))
        self.then.emit_body(out, ind + '    ')
        if self.els is not None and (self.els.stmts or self.els.tail):
            out.append(ind + '} else {')
            self.els.emit_body(out, ind + '    ')
        out.append(ind + '}')

    def run(self, it, fr):
        if self.cond.ev(it, fr):
            self.then.run(it, fr)
        elif self.els is not None:
            self.els.run(it, fr)


class For(S_):
    def __init__(self, var, n, body):
        self.var = var
        self.n = n
        self.body = body

    def emit(self, out, ind):
        out.append('%sfor %s in 0..%d {' % (ind, self.var, self.n))
        self.body.emit_body(out, ind + '    ')
        out.append(ind + '}')

    def run(self, it, fr):
        for i in range(self.n):
            try:
                self.body.run(it, fr, pre=[(self.var, Cell(i, owned=False))])
            except BreakEx:
                break
            except ContinueEx:
                continue


class Break(S_):
    def __init__(self, cont=False):
        self.cont = cont

    def emit(self, out, ind):
        out.append(ind + ('continue;' if self.cont else 'break;'))

    def run(self, it, fr):
        raise ContinueEx() if self.cont else BreakEx()


class Return(S_):
    def __init__(self, x):
        self.x = x

    def emit(self, out, ind):
        out.append('%sreturn %s;' % (ind, self.x.code()))

    def run(self, it, fr):
        raise ReturnEx(self.x.ev(it, fr))


class Question(S_):
    """`let t = e?;` in a function returning Option<i64> or Result<i64, i64>."""
    def __init__(self, name, x):
        self.name = name
        self.x = x

    def emit(self, out, ind):
        out.append('%slet %s = %s?;' % (ind, self.name, self.x.code()))

    def run(self, it, fr):
        v = self.x.ev(it, fr)
        if type(v) is OV:
            if v.val is None:
                raise ReturnEx(OV(None))
            fr.scopes[-1].append((self.name, Cell(v.val)))
        else:
            if not v.ok:
                raise ReturnEx(RV(False, v.val))
            fr.scopes[-1].append((self.name, Cell(v.val)))


class MatchE(S_):
    """`match e { E::One(a) => {..}, E::Two(a, b) => {..}, E::Nada => {..} }`
    on an owned local: e moves, the arm's bindings are its own."""
    def __init__(self, p, arms):
        self.p = p
        self.arms = arms   # tag -> (names or None for `_`, Block)

    def emit(self, out, ind):
        out.append('%smatch %s {' % (ind, self.p.code()))
        for tag in ('One', 'Two', 'Nada'):
            if tag not in self.arms:
                continue
            names, blk = self.arms[tag]
            if tag == 'Nada':
                pat = 'E::Nada'
            else:
                pat = 'E::%s(%s)' % (tag, ', '.join(names))
            out.append('%s    %s => {' % (ind, pat))
            blk.emit_body(out, ind + '        ')
            out.append(ind + '    }')
        if '_' in self.arms:
            out.append('%s    _ => {' % ind)
            self.arms['_'][1].emit_body(out, ind + '        ')
            out.append(ind + '    }')
        out.append(ind + '}')

    def run(self, it, fr):
        pl = self.p.place(it, fr)
        v = rd(pl.get())
        if v.tag in self.arms:
            names, blk = self.arms[v.tag]
            pre = []
            moved_all = True
            for i, nm in enumerate(names or []):
                if nm == '_':
                    moved_all = False
                    continue
                pre.append((nm, Cell(v.items[i])))
                v.items[i] = MOVED
            if moved_all:
                pl.set(MOVED)
            blk.run(it, fr, pre=pre)
        else:
            # (the `_` arm: nothing moves; e drops at its scope's end)
            self.arms['_'][1].run(it, fr)


class IfLet(S_):
    """`if let Some(t) = o { .. } else { .. }` (or the match form): o moves."""
    def __init__(self, p, name, then, els, form):
        self.p = p
        self.name = name
        self.then = then
        self.els = els
        self.form = form

    def emit(self, out, ind):
        if self.form == 'iflet':
            out.append('%sif let Some(%s) = %s {' % (ind, self.name, self.p.code()))
            self.then.emit_body(out, ind + '    ')
            if self.els.stmts:
                out.append(ind + '} else {')
                self.els.emit_body(out, ind + '    ')
            out.append(ind + '}')
        else:
            out.append('%smatch %s {' % (ind, self.p.code()))
            out.append('%s    Some(%s) => {' % (ind, self.name))
            self.then.emit_body(out, ind + '        ')
            out.append(ind + '    }')
            out.append(ind + '    None => {')
            self.els.emit_body(out, ind + '        ')
            out.append(ind + '    }')
            out.append(ind + '}')

    def run(self, it, fr):
        pl = self.p.place(it, fr)
        v = rd(pl.get())
        pl.set(MOVED)
        if v.val is not None:
            self.then.run(it, fr, pre=[(self.name, Cell(v.val))])
        else:
            self.els.run(it, fr)


class CloBlock(S_):
    """A block with a closure and its calls:
    'let'  { let f = || obs(x) + k; println(f"oN {f()} {f()}"); }
    'var'  { var f = || { x.v += k; x.v }; println(f"oN {f()} {f()}"); }
    'sink' { let f = sink || x.v + k; println(f"oN {f()}"); }   x moves in
    'twice' twice(|a: i64| { x.v += a * k; });"""
    def __init__(self, kind, p, k, n, fname):
        self.kind = kind
        self.p = p
        self.k = k
        self.n = n
        self.f = fname

    def emit(self, out, ind):
        x = self.p.code()
        f = self.f
        if self.kind == 'let':
            out.append('%s{ let %s = || obs(%s) + %d; println(f"o%d {%s()} {%s()}"); }' % (ind, f, x, self.k, self.n, f, f))
        elif self.kind == 'var':
            out.append('%s{ var %s = || { %s.v += %d; %s.v }; println(f"o%d {%s()} {%s()}"); }' % (ind, f, x, self.k, x, self.n, f, f))
        elif self.kind == 'sink':
            out.append('%s{ let %s = sink || %s.v + %d; println(f"o%d {%s()}"); }' % (ind, f, x, self.k, self.n, f))
        else:
            out.append('%stwice(|a: i64| { %s.v += a * %d; });' % (ind, x, self.k))

    def run(self, it, fr):
        pl = self.p.place(it, fr)
        t = rd(pl.get())
        if self.kind == 'let':
            it.line('o%d %d %d' % (self.n, wrap(t.v + self.k), wrap(t.v + self.k)))
        elif self.kind == 'var':
            t.v = wrap(t.v + self.k)
            a = t.v
            t.v = wrap(t.v + self.k)
            it.line('o%d %d %d' % (self.n, a, t.v))
        elif self.kind == 'sink':
            pl.set(MOVED)
            it.line('o%d %d' % (self.n, wrap(t.v + self.k)))
            it.drop(t)
        else:
            t.v = wrap(t.v + self.k)
            t.v = wrap(t.v + 2 * self.k)


class GenFn:
    def __init__(self, name, params, ret, body):
        self.name = name
        self.params = params     # [(name, conv, ty)]
        self.ret = ret           # 'i', 'T', 'OI', 'RI'
        self.body = body

    def emit(self, out):
        ps = ['gpa: Gpa']
        for n, conv, ty in self.params:
            c = '' if conv == 'let' else conv + ' '
            ps.append('%s: %s%s' % (n, c, TYNAME[ty]))
        out.append('fn %s(%s) -> %s {' % (self.name, ', '.join(ps), RETNAME[self.ret]))
        self.body.emit_body(out, '    ')
        out.append('}')
        out.append('')


TYNAME = {'T': 'T', 'V': 'Vec<T>', 'S': 'S', 'E': 'E', 'O': 'Option<T>',
          'P': 'Pt', 'Str': 'String', 'i': 'i64', 'F': None}
RETNAME = {'i': 'i64', 'T': 'T', 'OI': 'Option<i64>', 'RI': 'Result<i64, i64>'}


class Program:
    def __init__(self, fns, run_fn):
        self.fns = fns
        self.run_fn = run_fn

    def code(self):
        out = [HEADER]
        for f in self.fns:
            f.emit(out)
        out.append('fn run(gpa: Gpa) {')
        self.run_fn.body.emit_body(out, '    ')
        out.append('}')
        out.append('')
        out.append(MAIN)
        return '\n'.join(out)

    def expect(self):
        return Interp(self).run()


HEADER = '''// A program of tools/semfuzz/semfuzz.py: o<N> lines observe values, d<id>
// lines are Tracked values' drops, `live` counts the ones not dropped.
static var NEXT: i64 = 0;
static var LIVE: i64 = 0;

struct T { id: i64, v: i64 }

fn mk(v: i64) -> T {
    NEXT += 1;
    LIVE += 1;
    T { id: NEXT, v: v }
}

impl Drop for T {
    fn drop(inout self) {
        LIVE -= 1;
        println(f"d{self.id}");
    }
}

impl Clone for T {
    fn clone(self) -> T { mk(self.v) }
}

impl T {
    fn get(self) -> i64 { self.v }
    fn add(inout self, k: i64) { self.v += k; }
    fn into_v(sink self) -> i64 { self.v }
}

#[derive(Clone)]
struct S { t: T, w: Vec<T>, n: i64 }

#[derive(Clone)]
enum E { One(T), Two(T, T), Nada }

struct Pt { x: i64, y: i64 }

trait Score { fn score(self) -> i64; }
impl Score for T { fn score(self) -> i64 { self.v * 2 + 1 } }
impl Score for S { fn score(self) -> i64 { self.t.v + self.w.len() + self.n } }

fn total<X: Score>(x: X) -> i64 { x.score() }
fn gid<X>(x: sink X) -> X { x }
fn obs(t: T) -> i64 { t.v }
fn bump(t: inout T, k: i64) { t.v += k; }
fn eat(t: sink T) -> i64 { t.v }
fn ident(t: sink T) -> T { t }
fn pick(a: sink T, b: sink T, c: bool) -> T {
    if c { return a; }
    b
}
fn vsig(w: Vec<T>) -> i64 {
    var h = 7;
    for x in w { h = h * 31 + x.id * 100 + x.v; }
    h
}
fn vbump(w: inout Vec<T>, k: i64) {
    for i in 0..w.len() { w[i].v += k; }
}
fn veat(w: sink Vec<T>) -> i64 { w.len() }
fn keep(w: inout Vec<T>, t: sink T) { w.push(t); }
fn ssig(s: S) -> i64 { s.t.id * 1000 + s.t.v * 7 + vsig(s.w) + s.n }
fn esig(e: E) -> i64 {
    match e {
        E::One(a) => a.id * 10 + a.v,
        E::Two(a, b) => a.id * 100 + b.id * 10 + a.v - b.v,
        E::Nada => -3,
    }
}
fn osig(o: Option<T>) -> i64 {
    match o {
        Some(t) => t.id * 10 + t.v,
        None => -1,
    }
}
fn chk(t: T, lim: i64) -> Result<i64, i64> {
    if t.v > lim { return Err(t.v); }
    Ok(t.v + 1)
}
fn tchk(t: sink T, lim: i64) -> Result<T, i64> {
    if t.v > lim { return Err(t.v); }
    Ok(t)
}
fn pget(p: Pt) -> i64 { p.x * 10 + p.y }
fn pbump(p: inout Pt, k: i64) { p.x += k; }
fn psink(p: sink Pt) -> i64 {
    p.x += 1;
    p.x * 10 + p.y
}
fn seat(s: sink String) -> i64 { s.len() }
fn apply<F: Fn(i64) -> i64>(f: F, a: i64) -> i64 { f(a) }
fn twice<F: FnMut(i64)>(f: sink F) { f(1); f(2); }
fn callf<F: Fn() -> i64>(f: sink F) -> i64 { f() }
'''

MAIN = '''fn main(gpa: Gpa) -> i32 {
    run(gpa);
    println(f"live {LIVE}");
    0
}
'''


# ---------------------------------------------------------------- the generator
#
# The generator keeps the checker's view of each variable: live, moved or
# maybe moved ('L', 'M', 'Q'), per field for S, and makes only the uses
# the language accepts. Branches join; a branch that leaves (return,
# break, continue) does not reach the join.

class Var:
    __slots__ = ('name', 'ty', 'mut', 'kind', 'st', 'fst', 'loop')

    def __init__(self, name, ty, mut, kind, loop):
        self.name = name
        self.ty = ty
        self.mut = mut
        self.kind = kind      # 'local', 'let', 'inout', 'sink', 'loopvar'
        self.st = 'L'
        self.fst = {'t': 'L', 'w': 'L'} if ty == 'S' else None
        self.loop = loop


def join_st(a, b):
    if a == b:
        return a
    return 'Q'


OWNED = ('T', 'V', 'S', 'E', 'O', 'Str', 'F')


class Ctx:
    def __init__(self, ret=None):
        self.scopes = [[]]
        self.loop = 0
        self.ret = ret            # None in run
        self.break_states = []    # per loop: states at break/continue
        self.dead = False         # after a return/break: no more statements


class Gen:
    def __init__(self, seed, known=False, size=24):
        self.r = random.Random(seed)
        self.known = known
        self.size = size
        self.nid = 0
        self.nobs = 0
        self.fns = []

    def name(self, p):
        self.nid += 1
        return '%s%d' % (p, self.nid)

    def obsn(self):
        self.nobs += 1
        return self.nobs

    def chance(self, p):
        return self.r.random() < p

    # ---- variables

    def all_vars(self, c):
        for sc in c.scopes:
            for v in sc:
                yield v

    def snapshot(self, c):
        return {v.name: (v.st, dict(v.fst) if v.fst else None) for v in self.all_vars(c)}

    def restore(self, c, snap):
        for v in self.all_vars(c):
            if v.name in snap:
                v.st, f = snap[v.name]
                v.fst = dict(f) if f else None

    def join(self, c, snaps):
        snaps = [s for s in snaps if s is not None]
        if not snaps:
            return None
        res = {}
        for name in snaps[0]:
            sts = [s[name] for s in snaps if name in s]
            st = sts[0][0]
            f = dict(sts[0][1]) if sts[0][1] else None
            for s2, f2 in sts[1:]:
                st = join_st(st, s2)
                if f is not None:
                    for k in f:
                        f[k] = join_st(f[k], f2[k])
            res[name] = (st, f)
        return res

    def declare(self, c, name, ty, mut, kind='local'):
        v = Var(name, ty, mut, kind, c.loop)
        c.scopes[-1].append(v)
        return v

    def whole(self, v):
        return v.st == 'L' and (v.fst is None or all(s == 'L' for s in v.fst.values()))

    def readable(self, c, ty):
        return [v for v in self.all_vars(c) if v.ty == ty and self.whole(v)]

    def mutable(self, c, ty):
        return [v for v in self.readable(c, ty) if v.mut]

    def movable(self, c, ty):
        return [v for v in self.readable(c, ty)
                if v.kind in ('local', 'sink') and (v.loop == c.loop or ty in ('P', 'i'))]

    def assignable(self, c, ty):
        # a var (or a sink parameter) of any state, an inout parameter
        # (live); not in a loop for a moved one (it would be revived only
        # in some iterations)
        out = []
        for v in self.all_vars(c):
            if v.ty != ty or not v.mut or v.st == 'X':
                continue
            if v.kind == 'inout' and v.st != 'L':
                continue
            if v.fst is not None and not self.whole(v) and v.st == 'L':
                continue   # (a partly moved S: assign its fields instead)
            out.append(v)
        return out

    def s_with_field(self, c, f, need_mut=False, movable=False):
        out = []
        for v in self.all_vars(c):
            if v.ty != 'S' or v.st != 'L' or v.fst[f] != 'L':
                continue
            if need_mut and not v.mut:
                continue
            if movable and (v.kind not in ('local', 'sink') or v.loop != c.loop):
                continue
            out.append(v)
        return out

    def t_places(self, c, need_mut=False):
        """Readable places of a T: T variables, S fields `s.t`."""
        ps = [PVar(v.name) for v in (self.mutable(c, 'T') if need_mut else self.readable(c, 'T'))]
        ps += [PField(PVar(v.name), 't') for v in self.s_with_field(c, 't', need_mut)]
        return ps

    def v_places(self, c, need_mut=False):
        ps = [PVar(v.name) for v in (self.mutable(c, 'V') if need_mut else self.readable(c, 'V'))]
        ps += [PField(PVar(v.name), 'w') for v in self.s_with_field(c, 'w', need_mut)]
        return ps

    def var_of(self, c, name):
        for v in self.all_vars(c):
            if v.name == name:
                return v
        raise KeyError(name)

    def mark_moved(self, c, p):
        if isinstance(p, PVar):
            v = self.var_of(c, p.name)
            if v.ty not in ('P', 'i'):
                v.st = 'M'
        elif isinstance(p, PField):
            v = self.var_of(c, p.base.name)
            v.fst[p.f] = 'M'

    def loopvars(self, c):
        return [v for v in self.all_vars(c) if v.kind == 'loopvar']

    # ---- expressions

    def small(self):
        return self.r.randint(-3, 12)

    def int_k(self, c):
        lv = self.loopvars(c)
        if lv and self.chance(0.3):
            return Bin(Read(PVar(self.r.choice(lv).name)), '+', Lit(self.r.randint(0, 9)))
        return Lit(self.small())

    def texpr(self, c, depth=0, used=None):
        """An owned T value; moves what it takes. used: roots this call
        uses already (exclusivity)."""
        used = used if used is not None else set()
        r = self.r.random()
        mv = [v for v in self.movable(c, 'T') if v.name not in used]
        mvf = [v for v in self.s_with_field(c, 't', movable=True) if v.name not in used]
        if depth < 2 and r < 0.30 and mv:
            v = self.r.choice(mv)
            used.add(v.name)
            self.mark_moved(c, PVar(v.name))
            return Move(PVar(v.name))
        if depth < 2 and r < 0.36 and mvf:
            v = self.r.choice(mvf)
            used.add(v.name)
            self.mark_moved(c, PField(PVar(v.name), 't'))
            return Move(PField(PVar(v.name), 't'))
        if r < 0.48:
            ps = [p for p in self.t_places(c) if p.root() not in used]
            if ps:
                p = self.r.choice(ps)
                return Call('clone', [], method=True, recv=p)
        if depth < 2 and r < 0.56:
            return Call('ident', [Arg('sink', self.texpr(c, depth + 1, used))])
        if depth < 2 and r < 0.60:
            return Call('gid', [Arg('sink', self.texpr(c, depth + 1, used))])
        if depth < 1 and r < 0.66:
            a = self.texpr(c, depth + 1, used)
            b = self.texpr(c, depth + 1, used)
            return Call('pick', [Arg('sink', a), Arg('sink', b), Arg('val', BoolLit(self.chance(0.5)))])
        if depth < 1 and r < 0.70:
            ps = [p for p in self.t_places(c, need_mut=True) if p.root() not in used and self.inout_ok(c, p)]
            if ps:
                p = self.r.choice(ps)
                used.add(p.root())
                x = self.texpr(c, depth + 1, used)
                return Call('std::replace', [Arg('inout', p), Arg('sink', x)])
        if depth < 1 and r < 0.76:
            fs = [f for f in self.fns if f.ret == 'T']
            if fs:
                call = self.gen_call(c, self.r.choice(fs), used)
                if call is not None:
                    return call
        return Mk(self.int_k(c))

    def inout_ok(self, c, p):
        """An inout access of p: a whole var that is var/inout/sink, or a field."""
        return True

    def vexpr(self, c, used=None):
        used = used if used is not None else set()
        r = self.r.random()
        mv = [v for v in self.movable(c, 'V') if v.name not in used]
        if r < 0.35 and mv:
            v = self.r.choice(mv)
            used.add(v.name)
            self.mark_moved(c, PVar(v.name))
            return Move(PVar(v.name))
        if r < 0.5:
            ps = [p for p in self.v_places(c) if p.root() not in used]
            if ps:
                return Call('clone', [], method=True, recv=self.r.choice(ps))
        if r < 0.55 and mv:
            v = self.r.choice(mv)
            used.add(v.name)
            self.mark_moved(c, PVar(v.name))
            return Call('gid', [Arg('sink', Move(PVar(v.name)))])
        return NewVec()

    def obs_expr(self, c, used, ints=True):
        """An i64 observing a live value (no change); None if nothing.
        ints=False: also a String's text."""
        opts = []
        tp = [p for p in self.t_places(c)]
        if tp:
            opts += ['tv', 'tid', 'obs', 'get', 'total', 'apply']
        vp = self.v_places(c)
        if vp:
            opts += ['vsig', 'vlen', 'vsig', 'isum', 'icount']
        if self.readable(c, 'S'):
            opts += ['ssig', 'stotal']
        if self.readable(c, 'E'):
            opts += ['esig']
        if self.readable(c, 'O'):
            opts += ['osig'] if ints else ['osig', 'osome']
        if self.readable(c, 'P'):
            opts += ['pget', 'px']
        if self.readable(c, 'Str'):
            opts += ['slen'] if ints else ['slen', 'str']
        if self.readable(c, 'F'):
            opts += ['fcall']
        if self.readable(c, 'i'):
            opts += ['int']
        if not opts:
            return None
        o = self.r.choice(opts)
        if o in ('tv', 'tid', 'obs', 'get', 'total', 'apply'):
            p = self.r.choice(tp)
            if o == 'tv':
                return Read(PField(p, 'v'))
            if o == 'tid':
                return Read(PField(p, 'id'))
            if o == 'obs':
                return Call('obs', [Arg('let', p)])
            if o == 'get':
                return Call('get', [], method=True, recv=p)
            if o == 'total':
                return Call('total', [Arg('let', p)])
            # (a closure captures the variable, not the field: the whole
            # of it must be there)
            cp = [q for q in tp if self.whole(self.var_of(c, q.root()))]
            if not cp:
                return Call('obs', [Arg('let', p)])
            return Apply(self.r.choice(cp), self.small())
        if o in ('vsig', 'vlen', 'isum', 'icount'):
            p = self.r.choice(vp)
            if o == 'vsig':
                return Call('vsig', [Arg('let', p)])
            if o == 'vlen':
                return Call('len', [], method=True, recv=p)
            if o == 'isum':
                return IterSum(p, 'sum')
            return IterSum(p, 'count', self.small())
        if o in ('ssig', 'stotal'):
            v = self.r.choice(self.readable(c, 'S'))
            return Call('ssig' if o == 'ssig' else 'total', [Arg('let', PVar(v.name))])
        if o == 'esig':
            return Call('esig', [Arg('let', PVar(self.r.choice(self.readable(c, 'E')).name))])
        if o == 'osig':
            return Call('osig', [Arg('let', PVar(self.r.choice(self.readable(c, 'O')).name))])
        if o == 'osome':
            return Call('is_some', [], method=True, recv=PVar(self.r.choice(self.readable(c, 'O')).name))
        if o == 'pget':
            return Call('pget', [Arg('let', PVar(self.r.choice(self.readable(c, 'P')).name))])
        if o == 'px':
            v = self.r.choice(self.readable(c, 'P'))
            return Read(PField(PVar(v.name), self.r.choice(['x', 'y'])))
        if o == 'slen':
            return Call('len', [], method=True, recv=PVar(self.r.choice(self.readable(c, 'Str')).name))
        if o == 'str':
            return Read(PVar(self.r.choice(self.readable(c, 'Str')).name))
        if o == 'fcall':
            return CloCall(self.r.choice(self.readable(c, 'F')).name)
        return Read(PVar(self.r.choice(self.readable(c, 'i')).name))

    def consume_expr(self, c, used):
        """An i64 that consumes a value."""
        r = self.r.random()
        if r < 0.35:
            return Call('eat', [Arg('sink', self.texpr(c, 1, used))])
        if r < 0.5:
            x = self.texpr(c, 1, used)
            return Call('into_v', [], method=True, recv=x, recv_conv='sink')
        if r < 0.62:
            return Call('veat', [Arg('sink', self.vexpr(c, used))])
        if r < 0.70:
            fs = [v for v in self.movable(c, 'F') if v.name not in used]
            if fs:
                v = self.r.choice(fs)
                used.add(v.name)
                self.mark_moved(c, PVar(v.name))
                return Call('callf', [Arg('sink', Move(PVar(v.name)))])
        if r < 0.78:
            ss = [v for v in self.movable(c, 'Str') if v.name not in used]
            if ss:
                v = self.r.choice(ss)
                used.add(v.name)
                self.mark_moved(c, PVar(v.name))
                return Call('seat', [Arg('sink', Move(PVar(v.name)))])
        if r < 0.86:
            ps = self.readable(c, 'P')
            if ps:
                return Call('psink', [Arg('sink', Move(PVar(self.r.choice(ps).name)))])
        fs = [f for f in self.fns if f.ret in ('i', 'OI', 'RI')]
        if fs:
            f = self.r.choice(fs)
            call = self.gen_call(c, f, used)
            if call is not None:
                return call if f.ret == 'i' else Unres(call, f.ret)
        return Call('eat', [Arg('sink', Mk(self.int_k(c)))])

    def gen_call(self, c, f, used):
        args = []
        for pname, conv, ty in f.params:
            if ty == 'i':
                args.append(Arg('val', self.int_k(c)))
                continue
            if conv == 'let':
                if ty == 'T':
                    ps = [p for p in self.t_places(c) if p.root() not in used]
                elif ty == 'V':
                    ps = [p for p in self.v_places(c) if p.root() not in used]
                else:
                    ps = [PVar(v.name) for v in self.readable(c, ty) if v.name not in used]
                if ps:
                    p = self.r.choice(ps)
                    used.add(p.root())
                    args.append(Arg('let', p))
                    continue
                if self.known or ty not in ('T', 'V', 'S'):
                    if ty == 'T':
                        args.append(Arg('let', Mk(self.int_k(c))))
                        continue
                return None
            if conv == 'inout':
                if ty == 'T':
                    ps = [p for p in self.t_places(c, need_mut=True) if p.root() not in used]
                elif ty == 'V':
                    ps = [p for p in self.v_places(c, need_mut=True) if p.root() not in used]
                else:
                    ps = [PVar(v.name) for v in self.mutable(c, ty) if v.name not in used]
                if not ps:
                    return None
                p = self.r.choice(ps)
                used.add(p.root())
                args.append(Arg('inout', p))
                continue
            # sink
            if ty == 'T':
                args.append(Arg('sink', self.texpr(c, 1, used)))
            elif ty == 'V':
                args.append(Arg('sink', self.vexpr(c, used)))
            elif ty == 'S':
                args.append(Arg('sink', self.sexpr(c, used)))
            else:
                return None
        return CallGen(f, args)

    def sexpr(self, c, used):
        mv = [v for v in self.movable(c, 'S') if v.name not in used]
        if mv and self.chance(0.4):
            v = self.r.choice(mv)
            used.add(v.name)
            self.mark_moved(c, PVar(v.name))
            return Move(PVar(v.name))
        ps = [v for v in self.readable(c, 'S') if v.name not in used]
        if ps and self.chance(0.3):
            return Call('clone', [], method=True, recv=PVar(self.r.choice(ps).name))
        t = self.texpr(c, 1, used)
        w = self.vexpr(c, used)
        return NewS(t, w, self.small())

    def cond(self, c):
        r = self.r.random()
        tp = self.t_places(c)
        if r < 0.4 and tp:
            p = self.r.choice(tp)
            return Bin(Bin(Read(PField(p, 'v')), '%', Lit(self.r.choice([2, 3]))), self.r.choice(['==', '!=']), Lit(0))
        vp = self.v_places(c)
        if r < 0.6 and vp:
            return Bin(Call('len', [], method=True, recv=self.r.choice(vp)), '>', Lit(self.r.randint(0, 3)))
        os_ = self.readable(c, 'O')
        if r < 0.7 and os_:
            return Call('is_some', [], method=True, recv=PVar(self.r.choice(os_).name))
        lv = self.loopvars(c)
        if r < 0.85 and lv:
            return Bin(Bin(Read(PVar(self.r.choice(lv).name)), '%', Lit(2)), '==', Lit(self.r.randint(0, 1)))
        return BoolLit(self.chance(0.5))

    # ---- statements

    def gen_block(self, c, n, tail_fn=None):
        c.scopes.append([])
        stmts = []
        for _ in range(n):
            if c.dead:
                break
            s = self.gen_stmt(c)
            if isinstance(s, list):
                stmts.extend(s)
            elif s is not None:
                stmts.append(s)
        tail = None
        if tail_fn is not None and not c.dead:
            tail = tail_fn(c)
        c.scopes.pop()
        return Block(stmts, tail)

    def sub_block(self, c, n):
        """A block whose end state is returned (None if it leaves)."""
        b = self.gen_block(c, n)
        if c.dead:
            c.dead = False
            return b, None
        return b, self.snapshot(c)

    def gen_stmt(self, c):
        depth = len(c.scopes)
        r = self.r.random()
        w = [
            (10, self.st_decl),
            (4, self.st_copy),
            (4, self.st_clone),
            (9, self.st_mutate),
            (10, self.st_print),
            (5, self.st_consume),
            (9, self.st_vec),
            (4, self.st_assign),
            (2, self.st_swap),
            (5 if depth < 5 else 0, self.st_if),
            (3 if depth < 4 and c.loop < 2 else 0, self.st_for),
            (2 if depth < 5 else 0, self.st_block),
            (3, self.st_closure),
            (3, self.st_match),
            (2, self.st_struct),
            (2, self.st_plain),
            (1, self.st_string),
            (2 if c.loop > 0 else 0, self.st_break),
            (2 if c.ret is not None and depth < 7 else 0, self.st_return),
            (3 if c.ret in ('OI', 'RI') else 0, self.st_question),
            (1, self.st_drop),
        ]
        tot = sum(x for x, _ in w)
        pick = r * tot
        for wt, f in w:
            if pick < wt:
                return f(c)
            pick -= wt
        return None

    def st_decl(self, c):
        r = self.r.random()
        mut = self.chance(0.75)
        if r < 0.45:
            n = self.name('t')
            x = self.texpr(c)
            self.declare(c, n, 'T', mut)
            return Decl(n, mut, None, x)
        if r < 0.70:
            n = self.name('w')
            x = self.vexpr(c)
            self.declare(c, n, 'V', True)
            return Decl(n, True, 'Vec<T>', x)
        if r < 0.85:
            n = self.name('o')
            x = NewO(self.texpr(c)) if self.chance(0.7) else NewO(None)
            self.declare(c, n, 'O', mut)
            return Decl(n, mut, 'Option<T>', x)
        n = self.name('e')
        k = self.r.random()
        if k < 0.4:
            x = NewE('One', [self.texpr(c)])
        elif k < 0.8:
            used = set()
            x = NewE('Two', [self.texpr(c, 1, used), self.texpr(c, 1, used)])
        else:
            x = NewE('Nada', [])
        self.declare(c, n, 'E', mut)
        return Decl(n, mut, 'E', x)

    def st_copy(self, c):
        """`var b = a;`: a moves (owned) or is copied (plain)."""
        ty = self.r.choice(['T', 'T', 'V', 'O', 'P', 'Str'])
        mv = self.movable(c, ty)
        if not mv:
            return None
        v = self.r.choice(mv)
        n = self.name({'T': 't', 'V': 'w', 'O': 'o', 'P': 'p', 'Str': 'g'}[ty])
        self.mark_moved(c, PVar(v.name))
        self.declare(c, n, ty, True)
        return Decl(n, True, None, Move(PVar(v.name)))

    def st_clone(self, c):
        ty = self.r.choice(['T', 'V', 'S', 'E', 'O', 'Str'])
        if ty == 'T':
            ps = self.t_places(c)
        elif ty == 'V':
            ps = self.v_places(c)
        else:
            ps = [PVar(v.name) for v in self.readable(c, ty)]
        if not ps:
            return None
        p = self.r.choice(ps)
        n = self.name({'T': 't', 'V': 'w', 'S': 's', 'E': 'e', 'O': 'o', 'Str': 'g'}[ty])
        self.declare(c, n, ty, True)
        return Decl(n, True, None, Call('clone', [], method=True, recv=p))

    def st_mutate(self, c):
        r = self.r.random()
        tp = self.t_places(c, need_mut=True)
        if r < 0.5 and tp:
            p = self.r.choice(tp)
            k = self.r.random()
            if k < 0.35:
                return OpAssign(PField(p, 'v'), self.int_k(c))
            if k < 0.7:
                return Do(Call('bump', [Arg('inout', p), Arg('val', self.int_k(c))]))
            return Do(Call('add', [Arg('val', self.int_k(c))], method=True, recv=p))
        vp = self.v_places(c, need_mut=True)
        if r < 0.75 and vp:
            p = self.r.choice(vp)
            if self.chance(0.5):
                return Do(Call('vbump', [Arg('inout', p), Arg('val', self.int_k(c))]))
            # guarded element change
            i = self.r.randint(0, 2)
            k = self.r.random()
            if k < 0.5:
                inner = OpAssign(PField(PIdx(p, i), 'v'), self.int_k(c))
            else:
                inner = Do(Call('bump', [Arg('inout', PIdx(p, i)), Arg('val', self.int_k(c))]))
            return If(Bin(Call('len', [], method=True, recv=p), '>', Lit(i)), Block([inner]), None)
        ss = self.s_with_field(c, 't', need_mut=True)
        if ss and self.chance(0.5):
            return OpAssign(PField(PVar(self.r.choice(ss).name), 'n'), self.int_k(c))
        ints = self.mutable(c, 'i')
        if ints:
            return OpAssign(PVar(self.r.choice(ints).name), self.int_k(c))
        return None

    def st_print(self, c):
        used = set()
        holes = []
        for _ in range(self.r.randint(1, 3)):
            x = self.obs_expr(c, used, ints=False)
            if x is None:
                break
            holes.append(x)
        if not holes:
            return None
        return self.print_of(c, holes)

    def print_of(self, c, holes):
        """A println of holes; a hole that cannot be written in an
        f-string (braces, a ':') is computed into a let first."""
        pre = []
        hs = []
        for h in holes:
            code = h.code()
            if '{' in code or '}' in code or ':' in code or '"' in code:
                n = self.name('n')
                self.declare(c, n, 'i', False)
                pre.append(Decl(n, False, None, h))
                hs.append(Read(PVar(n)))
            else:
                hs.append(h)
        return pre + [Print(self.obsn(), hs)]

    def st_consume(self, c):
        used = set()
        x = self.consume_expr(c, used)
        if self.chance(0.6):
            return self.print_of(c, [x])
        n = self.name('n')
        self.declare(c, n, 'i', False)
        return Decl(n, False, None, x)

    def st_vec(self, c):
        vp = self.v_places(c, need_mut=True)
        if not vp:
            n = self.name('w')
            self.declare(c, n, 'V', True)
            return Decl(n, True, 'Vec<T>', NewVec())
        p = self.r.choice(vp)
        used = {p.root()}
        r = self.r.random()
        if r < 0.25:
            return Do(Call('push', [Arg('sink', self.texpr(c, 0, used))], method=True, recv=p))
        if r < 0.33:
            return Do(Call('keep', [Arg('inout', p), Arg('sink', self.texpr(c, 0, used))]))
        if r < 0.45:
            n = self.name('o')
            self.declare(c, n, 'O', True)
            return Decl(n, True, None, Call('pop', [], method=True, recv=p))
        if r < 0.55:
            i = self.r.randint(0, 2)
            n = self.name('t')
            snap = self.snapshot(c)
            c.scopes.append([])
            self.declare(c, n, 'T', True)
            inner = [Decl(n, True, None, Call('remove', [Arg('val', Lit(i))], method=True, recv=p))]
            body = self.gen_block(c, self.r.randint(0, 3))
            c.scopes.pop()
            if c.dead:
                c.dead = False
                self.restore(c, snap)
            else:
                self.restore(c, self.join(c, [snap, self.snapshot(c)]))
            return If(Bin(Call('len', [], method=True, recv=p), '>', Lit(i)), Block(inner + body.stmts), None)
        if r < 0.62:
            i = self.r.randint(0, 2)
            snap = self.snapshot(c)
            x = self.texpr(c, 1, used)
            self.restore(c, self.join(c, [snap, self.snapshot(c)]))
            return If(Bin(Call('len', [], method=True, recv=p), '>', Lit(i - 1)),
                      Block([Do(Call('insert', [Arg('val', Lit(i)), Arg('sink', x)], method=True, recv=p))]),
                      None)
        if r < 0.68:
            return Do(Call('truncate', [Arg('val', Lit(self.r.randint(0, 3)))], method=True, recv=p))
        if r < 0.71:
            return Do(Call('clear', [], method=True, recv=p))
        if r < 0.77:
            i, j = self.r.randint(0, 2), self.r.randint(0, 2)
            return If(Bin(Call('len', [], method=True, recv=p), '>', Lit(max(i, j))),
                      Block([Do(Call('swap', [Arg('val', Lit(i)), Arg('val', Lit(j))], method=True, recv=p))]), None)
        if r < 0.85 and self.known:
            i = self.r.randint(0, 2)
            # (the guard is evaluated before the value is made; a move in
            # the guarded block is a conditional move)
            snap = self.snapshot(c)
            x = self.texpr(c, 1, used)
            after = self.snapshot(c)
            self.restore(c, self.join(c, [snap, after]))
            if self.chance(0.5):
                inner = Assign(PIdx(p, i), x)
            else:
                inner = Do(Call('set', [Arg('val', Lit(i)), Arg('sink', x)], method=True, recv=p))
            return If(Bin(Call('len', [], method=True, recv=p), '>', Lit(i)), Block([inner]), None)
        if r < 0.92:
            # a loop over the elements, observing
            n = self.obsn()
            return ForEachObs(p, n)
        k = self.r.randint(1, 4)
        iv = self.name('i')
        return For(iv, k, Block([Do(Call('push', [Arg('sink', Mk(Bin(Read(PVar(iv)), '*', Lit(self.r.randint(1, 5)))))], method=True, recv=p))]))

    def st_assign(self, c):
        ty = self.r.choice(['T', 'T', 'V', 'O', 'E', 'S'])
        vs = [v for v in self.assignable(c, ty) if v.st == 'L' or v.loop == c.loop]
        if ty == 'S' and self.chance(0.6):
            # a field of an S: revives a moved one, or drops the old
            ss = [v for v in self.all_vars(c) if v.ty == 'S' and v.st == 'L' and v.mut]
            if ss:
                v = self.r.choice(ss)
                f = self.r.choice(['t', 'w'])
                if v.fst[f] != 'L' and v.loop != c.loop:
                    return None
                x = self.texpr(c, 0, {v.name}) if f == 't' else self.vexpr(c, {v.name})
                v.fst[f] = 'L'
                return Assign(PField(PVar(v.name), f), x)
        if not vs:
            return None
        v = self.r.choice(vs)
        used = {v.name}
        if ty == 'T':
            x = self.texpr(c, 0, used)
        elif ty == 'V':
            x = self.vexpr(c, used)
        elif ty == 'O':
            x = NewO(self.texpr(c, 1, used)) if self.chance(0.6) else NewO(None)
        elif ty == 'E':
            x = NewE('One', [self.texpr(c, 1, used)]) if self.chance(0.6) else NewE('Nada', [])
        else:
            x = self.sexpr(c, used)
        v.st = 'L'
        if v.fst:
            v.fst = {'t': 'L', 'w': 'L'}
        return Assign(PVar(v.name), x)

    def st_swap(self, c):
        ps = self.t_places(c, need_mut=True)
        if len(ps) < 2:
            return None
        a, b = self.r.sample(ps, 2)
        if a.root() == b.root():
            return None
        if self.chance(0.6):
            return Do(Call('std::swap', [Arg('inout', a), Arg('inout', b)]))
        x = self.texpr(c, 1, {a.root()})
        if self.chance(0.5):
            n = self.name('t')
            self.declare(c, n, 'T', True)
            return Decl(n, True, None, Call('std::replace', [Arg('inout', a), Arg('sink', x)]))
        return Do(Call('std::replace', [Arg('inout', a), Arg('sink', x)]))

    def st_if(self, c):
        cond = self.cond(c)
        snap = self.snapshot(c)
        t, st = self.sub_block(c, self.r.randint(1, 4))
        self.restore(c, snap)
        if self.chance(0.6):
            e, se = self.sub_block(c, self.r.randint(0, 3))
        else:
            e, se = None, snap
        j = self.join(c, [st, se])
        if j is None:
            c.dead = True
            self.restore(c, snap)
        else:
            self.restore(c, j)
        return If(cond, t, e)

    def st_for(self, c):
        snap = self.snapshot(c)
        iv = self.name('i')
        c.loop += 1
        c.break_states.append([])
        c.scopes.append([])
        self.declare(c, iv, 'i', False, kind='loopvar')
        body = self.gen_block(c, self.r.randint(1, 5))
        c.scopes.pop()
        end = None if c.dead else self.snapshot(c)
        c.dead = False
        bs = c.break_states.pop()
        c.loop -= 1
        j = self.join(c, [snap, end] + bs)
        self.restore(c, j)
        return For(iv, self.r.randint(0, 4), body)

    def st_block(self, c):
        b = self.gen_block(c, self.r.randint(1, 4))
        return b

    def st_break(self, c):
        # `if cond { break; }`, after the drops of the block's locals
        cond = self.cond(c)
        c.break_states[-1].append(self.snapshot(c))
        return If(cond, Block([Break(self.chance(0.3))]), None)

    def ret_expr(self, c):
        if c.ret == 'i':
            used = set()
            x = self.obs_expr(c, used)
            return x if x is not None else Lit(self.small())
        if c.ret == 'T':
            return self.texpr(c, 0)
        if c.ret == 'OI':
            if self.chance(0.3):
                return Wrap('None', None)
            x = self.obs_expr(c, set())
            return Wrap('Some', x if x is not None else Lit(self.small()))
        if self.chance(0.3):
            return Wrap('Err', Lit(self.small()))
        x = self.obs_expr(c, set())
        return Wrap('Ok', x if x is not None else Lit(self.small()))

    def st_return(self, c):
        cond = self.cond(c)
        snap = self.snapshot(c)
        x = self.ret_expr(c)
        self.restore(c, snap)
        return If(cond, Block([Return(x)]), None)

    def st_question(self, c):
        r = self.r.random()
        if c.ret == 'OI':
            os_ = self.movable(c, 'O')
            if r < 0.5 and os_:
                v = self.r.choice(os_)
                self.mark_moved(c, PVar(v.name))
                n = self.name('t')
                self.declare(c, n, 'T', False)
                return Question(n, Move(PVar(v.name)))
            vp = self.v_places(c, need_mut=True)
            if vp:
                n = self.name('t')
                q = Question(n, Call('pop', [], method=True, recv=self.r.choice(vp)))
                self.declare(c, n, 'T', False)
                return q
            if self.known:
                vp = self.v_places(c)
                if vp:
                    n = self.name('t')
                    q = Question(n, Call('last', [], method=True, recv=self.r.choice(vp)))
                    self.declare(c, n, 'T', False)
                    return q
            return None
        # RI
        if r < 0.5:
            tp = self.t_places(c)
            if tp:
                n = self.name('n')
                q = Question(n, Call('chk', [Arg('let', self.r.choice(tp)), Arg('val', Lit(self.r.randint(0, 12)))]))
                self.declare(c, n, 'i', False)
                return q
        n = self.name('t')
        x = self.texpr(c, 1)
        q = Question(n, Call('tchk', [Arg('sink', x), Arg('val', Lit(self.r.randint(0, 12)))]))
        self.declare(c, n, 'T', False)
        return q

    def st_drop(self, c):
        ty = self.r.choice(['T', 'V', 'O', 'E', 'S'])
        mv = self.movable(c, ty)
        if not mv:
            return None
        v = self.r.choice(mv)
        self.mark_moved(c, PVar(v.name))
        return Do(Call('drop', [Arg('sink', Move(PVar(v.name)))]))

    def st_closure(self, c):
        r = self.r.random()
        if r < 0.3:
            ps = [q for q in self.t_places(c) if self.whole(self.var_of(c, q.root()))]
            if ps:
                return CloBlock('let', self.r.choice(ps), self.small(), self.obsn(), self.name('f'))
        if r < 0.5:
            vs = [v for v in self.mutable(c, 'T') if v.kind in ('local', 'sink')]
            if vs:
                kind = self.r.choice(['var', 'twice'])
                return CloBlock(kind, PVar(self.r.choice(vs).name), self.small(), self.obsn() if kind == 'var' else 0, self.name('f'))
        if r < 0.7:
            vs = self.movable(c, 'T')
            if vs:
                v = self.r.choice(vs)
                self.mark_moved(c, PVar(v.name))
                return CloBlock('sink', PVar(v.name), self.small(), self.obsn(), self.name('f'))
        vs = self.movable(c, 'T')
        if vs:
            # a sink closure kept as a local
            v = self.r.choice(vs)
            self.mark_moved(c, PVar(v.name))
            n = self.name('f')
            self.declare(c, n, 'F', False)
            return Decl(n, False, None, NewClo(PVar(v.name), self.small()))
        return None

    def st_match(self, c):
        r = self.r.random()
        if r < 0.5:
            es = self.movable(c, 'E')
            if not es:
                return None
            v = self.r.choice(es)
            self.mark_moved(c, PVar(v.name))
            snap = self.snapshot(c)
            arms = {}
            ends = []
            wild = self.known and self.chance(0.3)
            for tag, k in (('One', 1), ('Two', 2), ('Nada', 0)):
                if wild and tag != 'One' and self.chance(0.5):
                    continue
                self.restore(c, snap)
                names = []
                c.scopes.append([])
                for _ in range(k):
                    if wild and self.chance(0.4):
                        names.append('_')
                    else:
                        nm = self.name('t')
                        names.append(nm)
                        self.declare(c, nm, 'T', False)
                b, s = self.sub_block(c, self.r.randint(0, 3))
                c.scopes.pop()
                arms[tag] = (names, b)
                ends.append(s)
            if len(arms) < 3:
                self.restore(c, snap)
                b, s = self.sub_block(c, self.r.randint(0, 2))
                arms['_'] = (None, b)
                ends.append(s)
            if wild:
                v.st = 'X'
            j = self.join(c, ends)
            if j is None:
                c.dead = True
                self.restore(c, snap)
            else:
                self.restore(c, j)
            if wild:
                v.st = 'X'
            return MatchE(PVar(v.name), arms)
        os_ = self.movable(c, 'O')
        if not os_:
            return None
        v = self.r.choice(os_)
        self.mark_moved(c, PVar(v.name))
        snap = self.snapshot(c)
        n = self.name('t')
        c.scopes.append([])
        self.declare(c, n, 'T', self.chance(0.3) and False)
        t, st = self.sub_block(c, self.r.randint(0, 3))
        c.scopes.pop()
        self.restore(c, snap)
        e, se = self.sub_block(c, self.r.randint(0, 2))
        j = self.join(c, [st, se])
        if j is None:
            c.dead = True
            self.restore(c, snap)
        else:
            self.restore(c, j)
        return IfLet(PVar(v.name), n, t, e, self.r.choice(['iflet', 'match']))

    def st_struct(self, c):
        r = self.r.random()
        ss = [v for v in self.all_vars(c) if v.ty == 'S' and v.st == 'L']
        if r < 0.4 or not ss:
            n = self.name('s')
            x = self.sexpr(c, set())
            self.declare(c, n, 'S', True)
            return Decl(n, True, None, x)
        v = self.r.choice(ss)
        if r < 0.7 and v.kind in ('local', 'sink') and v.loop == c.loop:
            f = self.r.choice(['t', 'w'])
            if v.fst[f] == 'L':
                # a partial move out of the struct
                n = self.name('t' if f == 't' else 'w')
                v.fst[f] = 'M'
                self.declare(c, n, 'T' if f == 't' else 'V', True)
                return Decl(n, True, None, Move(PField(PVar(v.name), f)))
        if v.fst['w'] == 'L' and v.mut:
            return Do(Call('push', [Arg('sink', self.texpr(c, 1, {v.name}))], method=True, recv=PField(PVar(v.name), 'w')))
        return None

    def st_plain(self, c):
        ps = self.readable(c, 'P')
        r = self.r.random()
        if r < 0.3 or not ps:
            n = self.name('p')
            self.declare(c, n, 'P', True)
            return Decl(n, True, None, NewP(self.small(), self.small()))
        v = self.r.choice(ps)
        if r < 0.5:
            # a copy, changed: the original is not
            n = self.name('p')
            return Block([Decl(n, True, None, Read(PVar(v.name))),
                          OpAssign(PField(PVar(n), 'x'), Lit(self.r.randint(1, 9))),
                          Print(self.obsn(), [Read(PField(PVar(v.name), 'x')), Read(PField(PVar(n), 'x'))])])
        if r < 0.7 and v.mut:
            return Do(Call('pbump', [Arg('inout', PVar(v.name)), Arg('val', self.int_k(c))]))
        return self.print_of(c, [Call('psink', [Arg('sink', Read(PVar(v.name)))]), Call('pget', [Arg('let', PVar(v.name))])])

    def st_string(self, c):
        ss = self.readable(c, 'Str')
        r = self.r.random()
        if r < 0.4 or not ss:
            n = self.name('g')
            self.declare(c, n, 'Str', True)
            return Decl(n, True, None, NewStr(self.r.choice(['ab', 'x', 'hello', ''])))
        v = self.r.choice(ss)
        if v.mut and r < 0.7:
            return Do(Call('push_str', [Arg('val', StrLit(self.r.choice(['z', 'yy', '!'])))], method=True, recv=PVar(v.name)))
        n = self.name('g')
        self.declare(c, n, 'Str', True)
        return Decl(n, True, None, Call('clone', [], method=True, recv=PVar(v.name)))

    # ---- functions

    def gen_fn(self):
        name = 'f%d' % (len(self.fns) + 1)
        ret = self.r.choice(['i', 'i', 'T', 'OI', 'RI'])
        c = Ctx(ret)
        params = []
        for _ in range(self.r.randint(1, 3)):
            ty = self.r.choice(['T', 'T', 'V', 'S', 'i'])
            conv = self.r.choice(['let', 'inout', 'sink'])
            if ty == 'i':
                conv = 'let'
            pn = self.name('a')
            params.append((pn, conv, ty))
            self.declare(c, pn, ty, conv in ('inout', 'sink'), kind=conv if ty != 'i' else 'let')
        def tail(c2):
            return self.ret_expr(c2)
        body = self.gen_block(c, self.r.randint(2, 8), tail_fn=tail)
        if body.tail is None:
            # (the body left on every path: still give it a value)
            body.tail = None
        f = GenFn(name, params, ret, body)
        return f

    def program(self):
        for _ in range(self.r.randint(0, 3)):
            f = self.gen_fn()
            if f.body.tail is not None or (f.body.stmts and self._ends_return(f.body)):
                self.fns.append(f)
        c = Ctx(None)
        c.scopes[0].append(Var('gpa', 'gpa', False, 'let', 0))
        body = self.gen_block(c, self.size + self.r.randint(-self.size // 3, self.size // 3))
        return Program(self.fns, GenFn('run', [], None, body))

    def _ends_return(self, b):
        return False


class StrLit(E):
    def __init__(self, s):
        self.s = s

    def code(self):
        return '"%s"' % self.s

    def ev(self, it, fr):
        return self.s


class ForEachObs(S_):
    """`for x in w { print(f"{x.v} "); }` then a newline: a loop over the
    borrowed elements."""
    def __init__(self, p, n):
        self.p = p
        self.n = n

    def emit(self, out, ind):
        out.append('%sprint("o%d");' % (ind, self.n))
        out.append('%sfor x in %s { print(f" {x.id}:{x.v}"); }' % (ind, self.p.code()))
        out.append('%sprintln("");' % ind)

    def run(self, it, fr):
        w = rd(self.p.place(it, fr).get())
        it.line('o%d%s' % (self.n, ''.join(' %d:%d' % (x.id, x.v) for x in w)))


# m_last for --known (a borrowed copy; the model gives the element)
def m_last(it, r):
    w = rd(r.get())
    return OV(w[-1] if w else None)


HELPERS['last'] = m_last


# ---------------------------------------------------------------- checking

def render(events):
    out = []
    for e in events:
        if e[0] == 'l':
            out.append(e[1])
        else:
            out.append('{' + ' '.join(e[1]) + '}')
    return '\n'.join(out) + '\n'


def compare(events, lines):
    """None if lines are what events say, else the first difference."""
    i = 0
    for e in events:
        if e[0] == 'l':
            if i >= len(lines):
                return 'line %d: expected %r, got the end' % (i + 1, e[1])
            if lines[i] != e[1]:
                return 'line %d: expected %r, got %r' % (i + 1, e[1], lines[i])
            i += 1
        else:
            k = len(e[1])
            got = lines[i:i + k]
            if sorted(got) != sorted(e[1]):
                return 'line %d: expected the set {%s}, got %r' % (i + 1, ' '.join(e[1]), got)
            i += k
    if i != len(lines):
        return 'line %d: expected the end, got %r' % (i + 1, lines[i])
    return None


CONFIGS = [
    ('O0', ['-O0', '-j1', '--check-alloc']),
    ('O1', ['-O1', '-j1', '--check-alloc']),
    ('O2', ['-O2', '-j1', '--check-alloc']),
    ('O2j8', ['-O2', '-j8', '--check-alloc']),
    ('O2plain', ['-O2', '-j8']),
]


def run_cmd(cmd, timeout=60, env=None):
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, env=env)
        return p.returncode, p.stdout.decode('utf-8', 'replace'), p.stderr.decode('utf-8', 'replace')
    except subprocess.TimeoutExpired:
        return 124, '', 'timeout'


def check_program(volec, prog, work, tag, configs=CONFIGS):
    """('ok', None) or (kind, detail)."""
    try:
        events = prog.expect()
    except Invalid as e:
        return ('invalid', str(e))
    except RecursionError:
        return ('invalid', 'recursion')
    src = os.path.join(work, tag + '.vl')
    with open(src, 'w') as f:
        f.write(prog.code())
    rc, out, err = run_cmd([volec, 'check', src])
    if rc != 0:
        msg = (out + err).strip().splitlines()
        first = next((l for l in msg if 'error' in l), msg[0] if msg else 'no message')
        if rc not in (0, 1):
            return ('crash', 'volec check exit %d: %s' % (rc, first))
        return ('reject', first)
    outputs = {}
    for name, flags in configs:
        exe = os.path.join(work, '%s.%s' % (tag, name))
        rc, out, err = run_cmd([volec] + flags + [src, '-o', exe], timeout=120)
        if rc != 0:
            msg = (out + err).strip().splitlines()
            return ('crash', '%s: compile failed (exit %d): %s' % (name, rc, msg[-1] if msg else ''))
        rc, out, err = run_cmd([exe], timeout=20)
        try:
            os.unlink(exe)
        except OSError:
            pass
        lines = out.rstrip('\n').split('\n') if out else []
        if rc != 0:
            return ('exit', '%s: exit %d: %s' % (name, rc, err.strip().splitlines()[0] if err.strip() else ''))
        if 'check-alloc' in err or 'use after free' in err or 'double free' in err:
            return ('alloc', '%s: %s' % (name, err.strip().splitlines()[0]))
        d = compare(events, lines)
        if d is not None:
            return ('oracle', '%s: %s' % (name, d))
        outputs[name] = out
    if len(set(outputs.values())) > 1:
        return ('levels', 'outputs differ: ' + ' '.join(sorted(outputs)))
    return ('ok', None)


# ---------------------------------------------------------------- shrinking

def blocks_of(prog):
    """Every statement list of the program, as (list owner, list)."""
    out = []

    def walk_block(b):
        out.append(b.stmts)
        for s in b.stmts:
            walk_stmt(s)

    def walk_stmt(s):
        if isinstance(s, Block):
            walk_block(s)
        elif isinstance(s, If):
            walk_block(s.then)
            if s.els is not None:
                walk_block(s.els)
        elif isinstance(s, For):
            walk_block(s.body)
        elif isinstance(s, MatchE):
            for _, b in s.arms.values():
                walk_block(b)
        elif isinstance(s, IfLet):
            walk_block(s.then)
            walk_block(s.els)

    for f in prog.fns:
        walk_block(f.body)
    walk_block(prog.run_fn.body)
    return out


def shrink(volec, prog, kind, work, log=None):
    """Deletes statements (and unused functions) while check_program keeps
    giving `kind`."""
    def still(p, tag):
        k, _ = check_program(volec, p, work, tag)
        return k == kind
    n = 0
    progress = True
    while progress:
        progress = False
        # functions no longer called
        for f in list(prog.fns):
            saved = prog.fns
            prog.fns = [g for g in prog.fns if g is not f]
            n += 1
            if still(prog, 'shrink%d' % n):
                progress = True
            else:
                prog.fns = saved
        for lst in blocks_of(prog):
            i = len(lst) - 1
            while i >= 0:
                if i >= len(lst):
                    i -= 1
                    continue
                s = lst[i]
                del lst[i]
                n += 1
                if still(prog, 'shrink%d' % n):
                    progress = True
                else:
                    lst.insert(i, s)
                    # an if: keep one branch only
                    if isinstance(s, If) and (s.then.stmts or (s.els and s.els.stmts)):
                        for repl in ([s.then], [s.els] if s.els else []):
                            if not repl:
                                continue
                            lst[i] = repl[0]
                            n += 1
                            if still(prog, 'shrink%d' % n):
                                progress = True
                                break
                            lst[i] = s
                i -= 1
    return prog


# ---------------------------------------------------------------- the runner

class Slots:
    """The jobs: $VOLE_JOBSERVER's slots (bootstrap/gate.sh), else a
    semaphore."""
    def __init__(self, jobs):
        self.fd = None
        js = os.environ.get('VOLE_JOBSERVER')
        if jobs is None and js and os.path.exists(js):
            self.fd = os.open(js, os.O_RDWR)
            self.n = os.cpu_count() or 4
        else:
            self.n = jobs or os.cpu_count() or 4
        self.sem = threading.Semaphore(self.n)

    def __enter__(self):
        if self.fd is not None:
            while os.read(self.fd, 1) != b'\n':
                pass
        else:
            self.sem.acquire()

    def __exit__(self, *a):
        if self.fd is not None:
            os.write(self.fd, b'\n')
        else:
            self.sem.release()


def main():
    ap = argparse.ArgumentParser(add_help=False)
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument('-c', default=os.path.join(root, 'target', 'volec'))
    ap.add_argument('-n', type=int, default=100)
    ap.add_argument('-f', type=int, default=1)
    ap.add_argument('-k', default=os.path.join(root, 'tests', 'fuzz', 'failures', 'sem'))
    ap.add_argument('-j', type=int, default=None)
    ap.add_argument('--known', action='store_true')
    ap.add_argument('--no-shrink', action='store_true')
    ap.add_argument('--print', type=int, default=None)
    ap.add_argument('--shrink', type=int, default=None)
    ap.add_argument('--size', type=int, default=24)
    ap.add_argument('-h', '--help', action='store_true')
    a = ap.parse_args()
    if a.help:
        print(__doc__)
        return 0
    if a.print is not None:
        prog = Gen(a.print, a.known, a.size).program()
        print(prog.code())
        try:
            print('// expected:\n' + ''.join('// ' + l + '\n' for l in render(prog.expect()).splitlines()))
        except Invalid as e:
            print('// invalid: %s' % e)
        return 0
    volec = os.path.abspath(a.c)
    work = tempfile.mkdtemp(prefix='vole-semfuzz.')
    if a.shrink is not None:
        prog = Gen(a.shrink, a.known, a.size).program()
        kind, detail = check_program(volec, prog, work, 'p')
        print('// %s: %s' % (kind, detail))
        if kind != 'ok':
            small = shrink(volec, prog, kind, work)
            print(small.code())
            print('// expected:\n' + ''.join('// ' + l + '\n' for l in render(small.expect()).splitlines()))
            print('// %s: %s' % check_program(volec, small, work, 'q'))
        shutil.rmtree(work, ignore_errors=True)
        return 0
    slots = Slots(a.j)
    results = {}
    lock = threading.Lock()

    def one(seed):
        prog = Gen(seed, a.known, a.size).program()
        d = os.path.join(work, 's%d' % seed)
        os.makedirs(d, exist_ok=True)
        with slots:
            kind, detail = check_program(volec, prog, d, 'p')
        if kind != 'ok':
            os.makedirs(a.k, exist_ok=True)
            base = os.path.join(a.k, 'sem%d' % seed)
            with open(base + '.vl', 'w') as f:
                f.write(prog.code())
            try:
                with open(base + '.expect', 'w') as f:
                    f.write(render(prog.expect()))
            except Invalid:
                pass
            if kind not in ('invalid',) and not a.no_shrink:
                with slots:
                    small = shrink(volec, Gen(seed, a.known, a.size).program(), kind, d)
                with open(base + '.min.vl', 'w') as f:
                    f.write(small.code())
                with open(base + '.min.expect', 'w') as f:
                    f.write(render(small.expect()))
        shutil.rmtree(d, ignore_errors=True)
        with lock:
            results[seed] = (kind, detail)

    seeds = list(range(a.f, a.f + a.n))
    with concurrent.futures.ThreadPoolExecutor(max_workers=slots.n) as ex:
        list(ex.map(one, seeds))
    shutil.rmtree(work, ignore_errors=True)
    bad = 0
    counts = {}
    for s in seeds:
        kind, detail = results[s]
        counts[kind] = counts.get(kind, 0) + 1
        if kind != 'ok':
            bad += 1
            print('FAIL seed %d: %s: %s (kept as %s)' % (s, kind, detail, os.path.join(a.k, 'sem%d.vl' % s)))
    summary = ', '.join('%d %s' % (counts[k], k) for k in sorted(counts))
    print('sem-fuzz: %d programs, %d failing (%s)' % (len(seeds), bad, summary))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
