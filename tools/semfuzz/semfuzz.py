#!/usr/bin/env python3
"""The semantics fuzzer (0.25): random well-typed vole programs over owned
values, each with the outcome its value semantics give, computed here.

A program is generated as a tree (the classes below) that is both printed
as vole and run by a small interpreter of the value semantics: moves,
copies, clones, inout accesses, sink parameters, drops at scope end in
reverse declaration order (with the `defer`s), temporaries at the end of
their statement, drop flags of conditionally moved locals and fields,
early returns, `break`, `?`. The interpreter gives the expected output:
every observation the program prints (`o<N> ...`) and every drop of a
Tracked value (`d<id>`), in order where the order is specified (an
enum's payload is a set), and at the end `live 0`. The program is then
compiled at -O0, -O1 and -O2, at -j1 and -j8, with --check-alloc (and
once without), run, and compared with the expectation. A program the
checker rejects is a possible OVERSTRICT finding (or a generator bug).
Failing programs are shrunk (statements and functions deleted while the
failure stays the same) and kept, with their expected output.

usage: tools/semfuzz/semfuzz.py [-c VOLEC] [-n COUNT] [-f FIRST] [-k DIR]
                                [-j JOBS] [--known] [--no-shrink]
                                [--print SEED] [--shrink SEED] [--size N]

  -c VOLEC      the compiler (default: target/volec)
  -n COUNT      programs (default 100); -f FIRST: the first seed (default 1)
  -k DIR        where failing programs are kept (default tests/fuzz/failures/sem)
  -j JOBS       programs at once (default: $VOLE_JOBSERVER's slots, or the CPUs)
  --known       also generate the constructs of known bugs (KNOWN below)
  --print SEED  print the program of SEED and its expected output
  --shrink SEED check SEED, and print it shrunk if it fails
  --size N      statements in run's body, about (default 24)

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


class TupV:
    __slots__ = ('_0', '_1')

    def __init__(self, a, b):
        self._0 = a
        self._1 = b


class GV:
    """struct G { t: T, k: i64 } with a Drop of its own."""
    __slots__ = ('t', 'k')

    def __init__(self, t, k):
        self.t = t
        self.k = k


class ArrV(list):
    pass


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


class DeferMark:
    __slots__ = ('n',)

    def __init__(self, n):
        self.n = n


def copy_plain(v):
    if type(v) is PV:
        return PV(v.x, v.y)
    return v


def is_plain(v):
    return type(v) in (int, bool, PV)


def attr(f):
    return '_' + f if f[0].isdigit() else f


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
    """A let or inout parameter, an inout local: the place it accesses,
    never dropped here."""
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

    def __init__(self, obj, a):
        self.obj = obj
        self.attr = a

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


PLACES = (Cell, AliasCell, AttrPlace, IdxPlace)


class ReturnEx(Exception):
    def __init__(self, val):
        self.val = val


class BreakEx(Exception):
    def __init__(self, label=None):
        self.label = label


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
        if self.steps > 100000:
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
        if t is TupV:
            return TupV(self.clone(v._0), self.clone(v._1))
        return v

    def drop(self, v):
        if v is MOVED or v is None:
            return
        t = type(v)
        if t is TV:
            self.live -= 1
            self.line('d%d' % v.id)
        elif t is list or t is ArrV:
            for e in v:
                self.drop(e)
        elif t is SV:
            self.drop(v.t)
            self.drop(v.w)
        elif t is TupV:
            self.drop(v._0)
            self.drop(v._1)
        elif t is GV:
            self.line('dg%d %d' % (v.k, v.t.id))
            self.drop(v.t)
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
            if type(c) is DeferMark:
                self.line('df%d' % c.n)
            elif c.owned:
                v = c.val
                c.val = MOVED
                self.drop(v)

    def run(self):
        fr = Frame()
        fr.scopes.append([('gpa', Cell(0, owned=False))])
        try:
            self.prog.run_fn.body.run(self, fr)
        except ReturnEx:
            pass
        self.line('live %d' % self.live)
        return self.ev


def rd(v):
    if v is MOVED:
        raise Invalid('read of a moved value')
    t = type(v)
    if t is SV and (v.t is MOVED or v.w is MOVED):
        raise Invalid('read of a partly moved struct')
    if t is TupV and (v._0 is MOVED or v._1 is MOVED):
        raise Invalid('read of a partly moved tuple')
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
        return AttrPlace(obj, attr(self.f))

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


class StrLit(E):
    def __init__(self, s):
        self.s = s

    def code(self):
        return '"%s"' % self.s

    def ev(self, it, fr):
        return self.s


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
        if self.op == '&&' and not a:
            return False
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
            return bool(b)
        raise ValueError(op)


class Not(E):
    def __init__(self, x):
        self.x = x

    def code(self):
        return '!%s' % self.x.code()

    def ev(self, it, fr):
        return not self.x.ev(it, fr)


class Arg:
    """An argument: conv 'let' (a place or a temporary), 'inout' (a
    place, `&p`), 'sink' or 'val' (an expression)."""
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
    if isinstance(x, PLACES):
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


# The header's functions, in the model. A let argument is a place (or a
# temporary's cell), an inout one a place, a sink one the value.

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


def h_dup(it, r, x):
    return it.clone(val(x))


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


def h_geat(it, r, g):
    k = g.k
    it.drop(g)
    return k


def h_usig(it, r, u):
    u = rd(val(u))
    return wrap(u._0.id * 100 + u._1.id * 10 + u._0.v + u._1.v)


def h_vssig(it, r, ws):
    h = 3
    for s in val(ws):
        h = wrap(wrap(h * 17) + h_ssig(it, None, s))
    return h


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


def m_last(it, r):
    # (for --known: a borrowed copy; the model gives the element)
    w = rd(r.get())
    return OV(w[-1] if w else None)


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


def m_is_empty(it, r):
    return len(rd(r.get())) == 0


def m_is_some(it, r):
    return rd(r.get()).val is not None


def m_unwrap(it, r):
    if r.val is None:
        raise Invalid('unwrap of None (unguarded)')
    return r.val


def m_unwrap_or(it, r, other):
    if r.val is not None:
        it.drop(other)
        return r.val
    return other


def m_push_str(it, r, s):
    x = rd(r.get())
    x.s = x.s + s


def m_take(it, r):
    w = rd(r.get())
    r.set([])
    return w


def m_tv(it, r):
    s = rd(r.get())
    return wrap(s.t.v + s.n)


def m_grow(it, r, k):
    s = rd(r.get())
    s.w.append(it.mk(k))
    s.n = wrap(s.n + 1)


def m_into_t(it, r):
    s = rd(r)
    t = s.t
    it.drop(s.w)
    return t


HELPERS = {
    'obs': h_obs, 'bump': h_bump, 'eat': h_eat, 'ident': h_ident,
    'vsig': h_vsig, 'vbump': h_vbump, 'veat': h_veat, 'keep': h_keep,
    'pick': h_pick, 'ssig': h_ssig, 'esig': h_esig, 'osig': h_osig,
    'total': h_total, 'gid': h_gid, 'dup': h_dup, 'chk': h_chk,
    'tchk': h_tchk, 'pget': h_pget, 'pbump': h_pbump, 'psink': h_psink,
    'seat': h_seat, 'callf': h_callf, 'geat': h_geat, 'usig': h_usig,
    'vssig': h_vssig, 'std::swap': h_swap, 'std::replace': h_replace,
    'drop': h_drop,
    'get': m_get, 'add': m_add, 'into_v': m_into_v, 'clone': m_clone,
    'push': m_push, 'pop': m_pop, 'last': m_last, 'remove': m_remove,
    'insert': m_insert, 'truncate': m_truncate, 'clear': m_clear,
    'swap': m_swap, 'set': m_set, 'len': m_len, 'is_empty': m_is_empty,
    'is_some': m_is_some, 'unwrap': m_unwrap, 'unwrap_or': m_unwrap_or,
    'push_str': m_push_str, 'take': m_take, 'tv': m_tv, 'grow': m_grow,
    'into_t': m_into_t,
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


class NewG(E):
    def __init__(self, t, k):
        self.t = t
        self.k = k

    def code(self):
        return 'G { t: %s, k: %d }' % (self.t.code(), self.k)

    def ev(self, it, fr):
        return GV(self.t.ev(it, fr), self.k)


class NewTup(E):
    def __init__(self, a, b):
        self.a = a
        self.b = b

    def code(self):
        return '(%s, %s)' % (self.a.code(), self.b.code())

    def ev(self, it, fr):
        a = self.a.ev(it, fr)
        return TupV(a, self.b.ev(it, fr))


class NewArr(E):
    def __init__(self, items):
        self.items = items

    def code(self):
        return '[%s]' % ', '.join(x.code() for x in self.items)

    def ev(self, it, fr):
        return ArrV([x.ev(it, fr) for x in self.items])


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
    """An i64 from an Option<i64> or a Result<i64, i64>: `match e {
    Some(q) => q, None => -7 }`."""
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
            if conv in ('let', 'inout') and isinstance(v, PLACES):
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


class Destructure(S_):
    """`let (a, b) = u;`: u moves, a and b are its parts."""
    def __init__(self, a, b, p):
        self.a = a
        self.b = b
        self.p = p

    def emit(self, out, ind):
        out.append('%slet (%s, %s) = %s;' % (ind, self.a, self.b, self.p.code()))

    def run(self, it, fr):
        pl = self.p.place(it, fr)
        u = rd(pl.get())
        pl.set(MOVED)
        fr.scopes[-1].append((self.a, Cell(u._0)))
        fr.scopes[-1].append((self.b, Cell(u._1)))


class Defer(S_):
    def __init__(self, n):
        self.n = n

    def emit(self, out, ind):
        out.append('%sdefer println("df%d");' % (ind, self.n))

    def run(self, it, fr):
        fr.scopes[-1].append(('#defer', DeferMark(self.n)))


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


def loop_body(it, fr, body, label, pre=None):
    """One iteration; False when the loop ends here."""
    try:
        body.run(it, fr, pre=pre)
    except BreakEx as b:
        if b.label is None or b.label == label:
            return False
        raise
    except ContinueEx:
        pass
    return True


class For(S_):
    def __init__(self, var, n, body, label=None):
        self.var = var
        self.n = n
        self.body = body
        self.label = label

    def emit(self, out, ind):
        lab = '%s: ' % self.label if self.label else ''
        out.append('%s%sfor %s in 0..%d {' % (ind, lab, self.var, self.n))
        self.body.emit_body(out, ind + '    ')
        out.append(ind + '}')

    def run(self, it, fr):
        for i in range(self.n):
            it.tick()
            if not loop_body(it, fr, self.body, self.label, pre=[(self.var, Cell(i, owned=False))]):
                break


class While(S_):
    """`while c < K { c += 1; body }` (the count first: a continue does
    not skip it)."""
    def __init__(self, cname, n, body):
        self.cname = cname
        self.n = n
        self.body = body

    def emit(self, out, ind):
        out.append('%swhile %s < %d {' % (ind, self.cname, self.n))
        out.append('%s    %s += 1;' % (ind, self.cname))
        self.body.emit_body(out, ind + '    ')
        out.append(ind + '}')

    def run(self, it, fr):
        c = fr.lookup(self.cname)
        while c.get() < self.n:
            it.tick()
            c.set(c.get() + 1)
            if not loop_body(it, fr, self.body, None):
                break


class Break(S_):
    def __init__(self, cont=False, label=None):
        self.cont = cont
        self.label = label

    def emit(self, out, ind):
        if self.cont:
            out.append(ind + 'continue;')
        elif self.label:
            out.append('%sbreak :%s;' % (ind, self.label))
        else:
            out.append(ind + 'break;')

    def run(self, it, fr):
        if self.cont:
            raise ContinueEx()
        raise BreakEx(self.label)


class Return(S_):
    def __init__(self, x):
        self.x = x

    def emit(self, out, ind):
        if self.x is None:
            out.append(ind + 'return;')
        else:
            out.append('%sreturn %s;' % (ind, self.x.code()))

    def run(self, it, fr):
        raise ReturnEx(None if self.x is None else self.x.ev(it, fr))


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


class MatchOpt(S_):
    """`if let Some(t) = x { .. } else { .. }`, its match form, or the same
    on a Result<T, i64> (`Ok(t)`, `Err(n)`); x is an owned local (which
    moves) or a call (a temporary). `while let Some(t) = w.pop() { .. }`
    with form 'while'."""
    def __init__(self, x, kind, name, then, ename, els, form):
        self.x = x
        self.kind = kind     # 'O' or 'R'
        self.name = name
        self.then = then
        self.ename = ename   # the Err binding (R)
        self.els = els
        self.form = form     # 'iflet', 'match', 'while'

    def emit(self, out, ind):
        some = 'Some(%s)' % self.name if self.kind == 'O' else 'Ok(%s)' % self.name
        none = 'None' if self.kind == 'O' else 'Err(%s)' % self.ename
        if self.form == 'while':
            out.append('%swhile let %s = %s {' % (ind, some, self.x.code()))
            self.then.emit_body(out, ind + '    ')
            out.append(ind + '}')
        elif self.form == 'iflet':
            out.append('%sif let %s = %s {' % (ind, some, self.x.code()))
            self.then.emit_body(out, ind + '    ')
            if self.els.stmts:
                out.append(ind + '} else {')
                self.els.emit_body(out, ind + '    ')
            out.append(ind + '}')
        else:
            out.append('%smatch %s {' % (ind, self.x.code()))
            out.append('%s    %s => {' % (ind, some))
            self.then.emit_body(out, ind + '        ')
            out.append(ind + '    }')
            out.append('%s    %s => {' % (ind, none))
            self.els.emit_body(out, ind + '        ')
            out.append(ind + '    }')
            out.append(ind + '}')

    def run(self, it, fr):
        if self.form == 'while':
            while True:
                it.tick()
                v = self.x.ev(it, fr)
                if v.val is None:
                    break
                if not loop_body(it, fr, self.then, None, pre=[(self.name, Cell(v.val))]):
                    break
            return
        v = self.x.ev(it, fr)
        if self.kind == 'O':
            if v.val is not None:
                self.then.run(it, fr, pre=[(self.name, Cell(v.val))])
            else:
                self.els.run(it, fr)
        else:
            if v.ok:
                self.then.run(it, fr, pre=[(self.name, Cell(v.val))])
            else:
                pre = [(self.ename, Cell(v.val))] if self.form == 'match' else []
                self.els.run(it, fr, pre=pre)


class InoutBlock(S_):
    """`{ inout r = &place; ops on r }`."""
    def __init__(self, name, p, body):
        self.name = name
        self.p = p
        self.body = body

    def emit(self, out, ind):
        out.append(ind + '{')
        out.append('%s    inout %s = &%s;' % (ind, self.name, self.p.code()))
        self.body.emit_body(out, ind + '    ')
        out.append(ind + '}')

    def run(self, it, fr):
        pl = self.p.place(it, fr)
        rd(pl.get())
        self.body.run(it, fr, pre=[(self.name, AliasCell(pl))])


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


class ForEachObs(S_):
    """`for x in w { print(f" {x.id}:{x.v}"); }` and a newline: a loop
    over the borrowed elements."""
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


class GenFn:
    def __init__(self, name, params, ret, body):
        self.name = name
        self.params = params     # [(name, conv, ty)]
        self.ret = ret           # 'i', 'T', 'V', 'OI', 'RI'
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
          'P': 'Pt', 'Str': 'String', 'i': 'i64', 'G': 'G', 'VS': 'Vec<S>'}
RETNAME = {'i': 'i64', 'T': 'T', 'V': 'Vec<T>', 'OI': 'Option<i64>',
           'RI': 'Result<i64, i64>'}


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

impl S {
    fn tv(self) -> i64 { self.t.v + self.n }
    fn grow(inout self, k: i64) {
        self.w.push(mk(k));
        self.n += 1;
    }
    fn into_t(sink self) -> T { self.t }
}

#[derive(Clone)]
enum E { One(T), Two(T, T), Nada }

struct G { t: T, k: i64 }

impl Drop for G {
    fn drop(inout self) { println(f"dg{self.k} {self.t.id}"); }
}

struct Pt { x: i64, y: i64 }

trait Score { fn score(self) -> i64; }
impl Score for T { fn score(self) -> i64 { self.v * 2 + 1 } }
impl Score for S { fn score(self) -> i64 { self.t.v + self.w.len() + self.n } }

fn total<X: Score>(x: X) -> i64 { x.score() }
fn gid<X>(x: sink X) -> X { x }
fn dup<X: Clone>(x: X) -> X { x.clone() }
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
fn vssig(ws: Vec<S>) -> i64 {
    var h = 3;
    for s in ws { h = h * 17 + ssig(s); }
    h
}
fn usig(u: (T, T)) -> i64 { u.0.id * 100 + u.1.id * 10 + u.0.v + u.1.v }
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
fn geat(g: sink G) -> i64 { g.k }
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
# The generator keeps the checker's view of each variable: live, moved,
# maybe moved ('L', 'M', 'Q'; 'X': not to be touched again), per field
# for S and tuples, and makes only the uses the language accepts.
# Branches join; a branch that leaves (return, break, continue) does not
# reach the join.

FIELDS = {'S': ('t', 'w'), 'Tu': ('0', '1')}


class Var:
    __slots__ = ('name', 'ty', 'mut', 'kind', 'st', 'fst', 'loop')

    def __init__(self, name, ty, mut, kind, loop):
        self.name = name
        self.ty = ty
        self.mut = mut
        self.kind = kind      # 'local', 'let', 'inout', 'sink', 'loopvar'
        self.st = 'L'
        self.fst = {f: 'L' for f in FIELDS[ty]} if ty in FIELDS else None
        self.loop = loop


def join_st(a, b):
    if a == b:
        return a
    if 'X' in (a, b):
        return 'X'
    return 'Q'


class Ctx:
    def __init__(self, ret=None):
        self.scopes = [[]]
        self.loop = 0
        self.ret = ret            # None in run
        self.loops = []           # per loop: (label, [states at its breaks])
        self.dead = False         # after a return/break: no more statements
        self.frozen = set()       # vars not to change (a while let's Vec)


class Gen:
    def __init__(self, seed, known=False, size=24):
        self.r = random.Random(seed)
        self.known = known
        self.size = size
        self.nid = 0
        self.nobs = 0
        self.fns = []
        self.calls = 0

    def name(self, p):
        self.nid += 1
        return '%s%d' % (p, self.nid)

    def obsn(self):
        self.nobs += 1
        return self.nobs

    def chance(self, p):
        return self.r.random() < p

    # ---- variables

    def raw_vars(self, c):
        for sc in c.scopes:
            for v in sc:
                yield v

    def all_vars(self, c):
        """The visible variables (a shadowed one is not)."""
        seen = set()
        out = []
        for sc in reversed(c.scopes):
            for v in reversed(sc):
                if v.name in seen:
                    continue
                seen.add(v.name)
                out.append(v)
        out.reverse()
        return out

    def snapshot(self, c):
        return {id(v): (v.st, dict(v.fst) if v.fst else None) for v in self.raw_vars(c)}

    def restore(self, c, snap):
        for v in self.raw_vars(c):
            if id(v) in snap:
                v.st, f = snap[id(v)]
                v.fst = dict(f) if f else None

    def join(self, c, snaps):
        snaps = [s for s in snaps if s is not None]
        if not snaps:
            return None
        res = {}
        for key in snaps[0]:
            sts = [s[key] for s in snaps if key in s]
            st = sts[0][0]
            f = dict(sts[0][1]) if sts[0][1] else None
            for s2, f2 in sts[1:]:
                st = join_st(st, s2)
                if f is not None:
                    for k in f:
                        f[k] = join_st(f[k], f2[k])
            res[key] = (st, f)
        return res

    def branch_join(self, c, snap, ends):
        """After branches with end states `ends` (None: it left)."""
        j = self.join(c, ends)
        if j is None:
            c.dead = True
            self.restore(c, snap)
        else:
            self.restore(c, j)

    def declare(self, c, name, ty, mut, kind='local'):
        v = Var(name, ty, mut, kind, c.loop)
        c.scopes[-1].append(v)
        return v

    def whole(self, v):
        return v.st == 'L' and (v.fst is None or all(s == 'L' for s in v.fst.values()))

    def readable(self, c, ty):
        return [v for v in self.all_vars(c) if v.ty == ty and self.whole(v)]

    def mutable(self, c, ty):
        return [v for v in self.readable(c, ty) if v.mut and v.name not in c.frozen]

    def movable(self, c, ty):
        return [v for v in self.readable(c, ty)
                if v.kind in ('local', 'sink') and v.name not in c.frozen
                and (v.loop == c.loop or ty in ('P', 'i'))]

    def assignable(self, c, ty):
        # a var (or a sink parameter) of any state, an inout parameter
        # (live); a moved one only outside loops it was declared out of
        out = []
        for v in self.all_vars(c):
            if v.ty != ty or not v.mut or v.st == 'X' or v.name in c.frozen:
                continue
            if v.kind == 'inout' and v.st != 'L':
                continue
            if v.fst is not None and not self.whole(v) and v.st == 'L':
                continue   # (a partly moved one: assign its fields instead)
            if v.st != 'L' and v.loop != c.loop:
                continue
            out.append(v)
        return out

    def with_field(self, c, ty, f, need_mut=False, movable=False):
        out = []
        for v in self.all_vars(c):
            if v.ty != ty or v.st != 'L':
                continue
            if v.fst is not None and v.fst[f] != 'L':
                continue
            if need_mut and (not v.mut or v.name in c.frozen):
                continue
            if movable and (v.kind not in ('local', 'sink') or v.loop != c.loop or v.name in c.frozen):
                continue
            if ty == 'G' and not self.whole(v):
                continue
            out.append(v)
        return out

    def t_places(self, c, need_mut=False, elems=True):
        """Readable places of a T: T variables, fields (`s.t`, `u.0`,
        `g.t`), array elements."""
        ps = [PVar(v.name) for v in (self.mutable(c, 'T') if need_mut else self.readable(c, 'T'))]
        ps += [PField(PVar(v.name), 't') for v in self.with_field(c, 'S', 't', need_mut)]
        ps += [PField(PVar(v.name), 't') for v in self.with_field(c, 'G', 't', need_mut)]
        for f in ('0', '1'):
            ps += [PField(PVar(v.name), f) for v in self.with_field(c, 'Tu', f, need_mut)]
        if elems:
            vs = self.mutable(c, 'A') if need_mut else self.readable(c, 'A')
            ps += [PIdx(PVar(v.name), i) for v in vs for i in (0, 1)]
        return ps

    def t_movable_fields(self, c):
        ps = [PField(PVar(v.name), 't') for v in self.with_field(c, 'S', 't', movable=True)]
        for f in ('0', '1'):
            ps += [PField(PVar(v.name), f) for v in self.with_field(c, 'Tu', f, movable=True)]
        return ps

    def v_places(self, c, need_mut=False):
        ps = [PVar(v.name) for v in (self.mutable(c, 'V') if need_mut else self.readable(c, 'V'))]
        ps += [PField(PVar(v.name), 'w') for v in self.with_field(c, 'S', 'w', need_mut)]
        return ps

    def var_of(self, c, name):
        for v in reversed(self.all_vars(c)):
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

    def take_var(self, c, ty, used):
        """A movable variable of ty, moved (or None)."""
        mv = [v for v in self.movable(c, ty) if v.name not in used]
        if not mv:
            return None
        v = self.r.choice(mv)
        used.add(v.name)
        self.mark_moved(c, PVar(v.name))
        return Move(PVar(v.name))

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
        """An owned T value; moves what it takes. used: the roots this
        call uses already (exclusivity)."""
        used = used if used is not None else set()
        r = self.r.random()
        if depth < 2 and r < 0.26:
            m = self.take_var(c, 'T', used)
            if m is not None:
                return m
        if depth < 2 and r < 0.32:
            ps = [p for p in self.t_movable_fields(c) if p.root() not in used]
            if ps:
                p = self.r.choice(ps)
                used.add(p.root())
                self.mark_moved(c, p)
                return Move(p)
        if r < 0.42:
            ps = [p for p in self.t_places(c) if p.root() not in used]
            if ps:
                p = self.r.choice(ps)
                if self.chance(0.2):
                    return Call('dup', [Arg('let', p)])
                return Call('clone', [], method=True, recv=p)
        if depth < 2 and r < 0.49:
            return Call('ident', [Arg('sink', self.texpr(c, depth + 1, used))])
        if depth < 2 and r < 0.52:
            return Call('gid', [Arg('sink', self.texpr(c, depth + 1, used))])
        if depth < 1 and r < 0.57:
            a = self.texpr(c, depth + 1, used)
            b = self.texpr(c, depth + 1, used)
            return Call('pick', [Arg('sink', a), Arg('sink', b), Arg('val', BoolLit(self.chance(0.5)))])
        if depth < 1 and r < 0.61:
            ps = [p for p in self.t_places(c, need_mut=True) if p.root() not in used]
            if ps:
                p = self.r.choice(ps)
                used.add(p.root())
                x = self.texpr(c, depth + 1, used)
                return Call('std::replace', [Arg('inout', p), Arg('sink', x)])
        if depth < 2 and r < 0.65:
            o = self.take_var(c, 'O', used)
            if o is not None:
                return Call('unwrap_or', [Arg('sink', self.texpr(c, depth + 1, used))], method=True, recv=o, recv_conv='sink')
        if depth < 2 and r < 0.68:
            s = self.take_var(c, 'S', used)
            if s is not None:
                return Call('into_t', [], method=True, recv=s, recv_conv='sink')
        if depth < 1 and r < 0.73:
            fs = [f for f in self.fns if f.ret == 'T']
            if fs:
                call = self.gen_call(c, self.r.choice(fs), used)
                if call is not None:
                    return call
        if r < 0.78:
            ws = self.v_places(c)
            if ws:
                # (two-phase: the argument reads the Vec the call is on)
                return Mk(Call('len', [], method=True, recv=self.r.choice(ws)))
        return Mk(self.int_k(c))

    def vexpr(self, c, used=None):
        used = used if used is not None else set()
        r = self.r.random()
        if r < 0.3:
            m = self.take_var(c, 'V', used)
            if m is not None:
                return m
        if r < 0.45:
            ps = [p for p in self.v_places(c) if p.root() not in used]
            if ps:
                p = self.r.choice(ps)
                if self.chance(0.25):
                    return Call('dup', [Arg('let', p)])
                return Call('clone', [], method=True, recv=p)
        if r < 0.55:
            ps = [p for p in self.v_places(c, need_mut=True) if p.root() not in used]
            if ps:
                p = self.r.choice(ps)
                used.add(p.root())
                return Call('take', [], method=True, recv=p)
        if r < 0.6:
            m = self.take_var(c, 'V', used)
            if m is not None:
                return Call('gid', [Arg('sink', m)])
        if r < 0.66:
            fs = [f for f in self.fns if f.ret == 'V']
            if fs:
                call = self.gen_call(c, self.r.choice(fs), used)
                if call is not None:
                    return call
        return NewVec()

    def obs_expr(self, c, used, ints=True):
        """An i64 observing a live value (no change); None if nothing.
        ints=False: also a bool or a String's text."""
        opts = []
        tp = self.t_places(c)
        if tp:
            opts += ['tv', 'tid', 'obs', 'get', 'total', 'apply']
        vp = self.v_places(c)
        if vp:
            opts += ['vsig', 'vlen', 'vsig', 'isum', 'icount']
        if self.readable(c, 'S'):
            opts += ['ssig', 'stotal', 'stv']
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
        if self.readable(c, 'Tu'):
            opts += ['usig']
        if self.readable(c, 'G'):
            opts += ['gk']
        if self.readable(c, 'VS'):
            opts += ['vssig', 'vslen']
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
        if o in ('ssig', 'stotal', 'stv'):
            v = self.r.choice(self.readable(c, 'S'))
            if o == 'stv':
                return Call('tv', [], method=True, recv=PVar(v.name))
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
        if o == 'usig':
            return Call('usig', [Arg('let', PVar(self.r.choice(self.readable(c, 'Tu')).name))])
        if o == 'gk':
            return Read(PField(PVar(self.r.choice(self.readable(c, 'G')).name), 'k'))
        if o == 'vssig':
            return Call('vssig', [Arg('let', PVar(self.r.choice(self.readable(c, 'VS')).name))])
        if o == 'vslen':
            return Call('len', [], method=True, recv=PVar(self.r.choice(self.readable(c, 'VS')).name))
        return Read(PVar(self.r.choice(self.readable(c, 'i')).name))

    def consume_expr(self, c, used):
        """An i64 that consumes a value."""
        r = self.r.random()
        if r < 0.3:
            return Call('eat', [Arg('sink', self.texpr(c, 1, used))])
        if r < 0.42:
            x = self.texpr(c, 1, used)
            return Call('into_v', [], method=True, recv=x, recv_conv='sink')
        if r < 0.52:
            return Call('veat', [Arg('sink', self.vexpr(c, used))])
        if r < 0.58:
            m = self.take_var(c, 'F', used)
            if m is not None:
                return Call('callf', [Arg('sink', m)])
        if r < 0.64:
            m = self.take_var(c, 'Str', used)
            if m is not None:
                return Call('seat', [Arg('sink', m)])
        if r < 0.70:
            m = self.take_var(c, 'G', used)
            if m is not None:
                return Call('geat', [Arg('sink', m)])
        if r < 0.76:
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
        if self.calls > 1:
            return None
        self.calls += 1
        try:
            return self.gen_call1(c, f, used)
        finally:
            self.calls -= 1

    def gen_call1(self, c, f, used):
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
                if self.known and ty == 'T':
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
        if self.chance(0.4):
            m = self.take_var(c, 'S', used)
            if m is not None:
                return m
        ps = [v for v in self.readable(c, 'S') if v.name not in used]
        if ps and self.chance(0.3):
            return Call('clone', [], method=True, recv=PVar(self.r.choice(ps).name))
        t = self.texpr(c, 1, used)
        w = self.vexpr(c, used)
        return NewS(t, w, self.small())

    def cond(self, c):
        r = self.r.random()
        tp = self.t_places(c)
        if r < 0.35 and tp:
            p = self.r.choice(tp)
            return Bin(Bin(Read(PField(p, 'v')), '%', Lit(self.r.choice([2, 3]))), self.r.choice(['==', '!=']), Lit(0))
        vp = self.v_places(c)
        if r < 0.5 and vp:
            return Bin(Call('len', [], method=True, recv=self.r.choice(vp)), '>', Lit(self.r.randint(0, 3)))
        if r < 0.55 and vp:
            return Not(Call('is_empty', [], method=True, recv=self.r.choice(vp)))
        os_ = self.readable(c, 'O')
        if r < 0.65 and os_:
            return Call('is_some', [], method=True, recv=PVar(self.r.choice(os_).name))
        lv = self.loopvars(c)
        if r < 0.82 and lv:
            return Bin(Bin(Read(PVar(self.r.choice(lv).name)), '%', Lit(2)), '==', Lit(self.r.randint(0, 1)))
        return BoolLit(self.chance(0.5))

    # ---- statements

    def gen_block(self, c, n, tail_fn=None, pre=None):
        c.scopes.append([])
        for (nm, ty, mut, kind) in (pre or []):
            self.declare(c, nm, ty, mut, kind)
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

    def sub_block(self, c, n, pre=None):
        """A block and its end state (None if it leaves)."""
        b = self.gen_block(c, n, pre=pre)
        if c.dead:
            c.dead = False
            return b, None
        return b, self.snapshot(c)

    def guarded(self, c, make):
        """make() builds what a guard (an if) runs: its moves are
        conditional."""
        snap = self.snapshot(c)
        x = make()
        if c.dead:
            c.dead = False
            self.restore(c, snap)
        else:
            self.restore(c, self.join(c, [snap, self.snapshot(c)]))
        return x

    def gen_stmt(self, c):
        depth = len(c.scopes)
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
            (3 if depth < 4 and c.loop < 2 else 0, self.st_loop),
            (2 if depth < 5 else 0, self.st_block),
            (3, self.st_closure),
            (3, self.st_match),
            (2, self.st_option),
            (3, self.st_struct),
            (2, self.st_tuple),
            (1, self.st_array),
            (1, self.st_g),
            (1, self.st_vs),
            (2, self.st_plain),
            (1, self.st_string),
            (1, self.st_inout),
            (1, self.st_defer),
            (1, self.st_shadow),
            (2 if c.loop > 0 else 0, self.st_break),
            (2 if depth < 7 else 0, self.st_return),
            (3 if c.ret in ('OI', 'RI') else 0, self.st_question),
            (1, self.st_drop),
        ]
        tot = sum(x for x, _ in w)
        pick = self.r.random() * tot
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
        ty = self.r.choice(['T', 'T', 'V', 'O', 'P', 'Str', 'S', 'Tu', 'A', 'G', 'E'])
        mv = self.movable(c, ty)
        if not mv:
            return None
        v = self.r.choice(mv)
        n = self.name({'T': 't', 'V': 'w', 'O': 'o', 'P': 'p', 'Str': 'g', 'S': 's',
                       'Tu': 'u', 'A': 'a', 'G': 'k', 'E': 'e'}[ty])
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
        # (a clone is independent: changed, the original is not)
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
        if r < 0.72 and vp:
            p = self.r.choice(vp)
            if self.chance(0.5):
                return Do(Call('vbump', [Arg('inout', p), Arg('val', self.int_k(c))]))
            # a guarded element change
            i = self.r.randint(0, 2)
            if self.chance(0.5):
                inner = OpAssign(PField(PIdx(p, i), 'v'), self.int_k(c))
            else:
                inner = Do(Call('bump', [Arg('inout', PIdx(p, i)), Arg('val', self.int_k(c))]))
            return If(Bin(Call('len', [], method=True, recv=p), '>', Lit(i)), Block([inner]), None)
        ss = self.with_field(c, 'S', 't', need_mut=True)
        if r < 0.85 and ss:
            v = self.r.choice(ss)
            if self.chance(0.5) and v.fst['w'] == 'L':
                return Do(Call('grow', [Arg('val', self.int_k(c))], method=True, recv=PVar(v.name)))
            return OpAssign(PField(PVar(v.name), 'n'), self.int_k(c))
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
        f-string (braces, a ':', a string) is computed into a let first."""
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
        lenp = Call('len', [], method=True, recv=p)
        if r < 0.25:
            return Do(Call('push', [Arg('sink', self.texpr(c, 0, used))], method=True, recv=p))
        if r < 0.33:
            return Do(Call('keep', [Arg('inout', p), Arg('sink', self.texpr(c, 0, used))]))
        if r < 0.43:
            n = self.name('o')
            self.declare(c, n, 'O', True)
            return Decl(n, True, None, Call('pop', [], method=True, recv=p))
        if r < 0.53:
            i = self.r.randint(0, 2)
            n = self.name('t')

            def make():
                body = self.gen_block(c, self.r.randint(0, 3), pre=[(n, 'T', True, 'local')])
                return body
            body = self.guarded(c, make)
            inner = [Decl(n, True, None, Call('remove', [Arg('val', Lit(i))], method=True, recv=p))]
            return If(Bin(lenp, '>', Lit(i)), Block(inner + body.stmts), None)
        if r < 0.60:
            i = self.r.randint(0, 2)
            x = self.guarded(c, lambda: self.texpr(c, 1, used))
            return If(Bin(lenp, '>', Lit(i - 1)),
                      Block([Do(Call('insert', [Arg('val', Lit(i)), Arg('sink', x)], method=True, recv=p))]),
                      None)
        if r < 0.66:
            return Do(Call('truncate', [Arg('val', Lit(self.r.randint(0, 3)))], method=True, recv=p))
        if r < 0.69:
            return Do(Call('clear', [], method=True, recv=p))
        if r < 0.75:
            i, j = self.r.randint(0, 2), self.r.randint(0, 2)
            return If(Bin(lenp, '>', Lit(max(i, j))),
                      Block([Do(Call('swap', [Arg('val', Lit(i)), Arg('val', Lit(j))], method=True, recv=p))]), None)
        if r < 0.80 and self.known:
            i = self.r.randint(0, 2)
            x = self.guarded(c, lambda: self.texpr(c, 1, used))
            if self.chance(0.5):
                inner = Assign(PIdx(p, i), x)
            else:
                inner = Do(Call('set', [Arg('val', Lit(i)), Arg('sink', x)], method=True, recv=p))
            return If(Bin(lenp, '>', Lit(i)), Block([inner]), None)
        if r < 0.87:
            return ForEachObs(p, self.obsn())
        if r < 0.93 and isinstance(p, PVar) and c.loop < 2:
            # while let over pops; the Vec is not changed in the body
            n = self.name('t')
            v = self.var_of(c, p.name)
            snap = self.snapshot(c)
            c.loop += 1
            c.loops.append((None, []))
            c.frozen.add(v.name)
            body = self.gen_block(c, self.r.randint(0, 3), pre=[(n, 'T', False, 'local')])
            c.frozen.discard(v.name)
            end = None if c.dead else self.snapshot(c)
            c.dead = False
            _, bs = c.loops.pop()
            c.loop -= 1
            self.restore(c, self.join(c, [snap, end] + bs))
            return MatchOpt(Call('pop', [], method=True, recv=p), 'O', n, body, None, None, 'while')
        k = self.r.randint(1, 4)
        iv = self.name('i')
        return For(iv, k, Block([Do(Call('push', [Arg('sink', Mk(Bin(Read(PVar(iv)), '*', Lit(self.r.randint(1, 5)))))], method=True, recv=p))]))

    def st_assign(self, c):
        ty = self.r.choice(['T', 'T', 'V', 'O', 'E', 'S', 'G', 'Tu'])
        if ty in ('S', 'Tu', 'G') and self.chance(0.6):
            # a field: revives a moved one, or drops the old value
            fs = {'S': ('t', 'w'), 'Tu': ('0', '1'), 'G': ('t',)}[ty]
            vs = [v for v in self.all_vars(c) if v.ty == ty and v.st == 'L' and v.mut
                  and v.name not in c.frozen and (ty != 'G' or self.whole(v))]
            if vs:
                v = self.r.choice(vs)
                f = self.r.choice(fs)
                if v.fst is not None and v.fst[f] != 'L' and v.loop != c.loop:
                    return None
                x = self.vexpr(c, {v.name}) if f == 'w' else self.texpr(c, 0, {v.name})
                if v.fst is not None:
                    v.fst[f] = 'L'
                return Assign(PField(PVar(v.name), f), x)
        vs = self.assignable(c, ty)
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
        elif ty == 'S':
            x = self.sexpr(c, used)
        elif ty == 'G':
            x = NewG(self.texpr(c, 1, used), self.small())
        else:
            x = NewTup(self.texpr(c, 1, used), self.texpr(c, 1, used))
        v.st = 'L'
        if v.fst:
            v.fst = {f: 'L' for f in v.fst}
        return Assign(PVar(v.name), x)

    def st_swap(self, c):
        ps = self.t_places(c, need_mut=True, elems=False)
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
        self.branch_join(c, snap, [st, se])
        return If(cond, t, e)

    def st_loop(self, c):
        snap = self.snapshot(c)
        kind = 'for' if self.chance(0.75) else 'while'
        label = self.name('l') if kind == 'for' and self.chance(0.25) else None
        c.loop += 1
        c.loops.append((label, []))
        pre = []
        iv = None
        cn = None
        if kind == 'for':
            iv = self.name('i')
            pre = [(iv, 'i', False, 'loopvar')]
        else:
            cn = self.name('c')
        body = self.gen_block(c, self.r.randint(1, 5), pre=pre)
        end = None if c.dead else self.snapshot(c)
        c.dead = False
        _, bs = c.loops.pop()
        c.loop -= 1
        self.restore(c, self.join(c, [snap, end] + bs))
        n = self.r.randint(0, 4)
        if kind == 'for':
            return For(iv, n, body, label)
        self.declare(c, cn, 'i', True)
        return [Decl(cn, True, None, Lit(0)), While(cn, n, body)]

    def st_block(self, c):
        return self.gen_block(c, self.r.randint(1, 4))

    def st_break(self, c):
        # `if cond { break; }`: the block's locals are dropped first
        cond = self.cond(c)
        labeled = [i for i, (lab, _) in enumerate(c.loops) if lab]
        if labeled and self.chance(0.4):
            i = self.r.choice(labeled)
            c.loops[i][1].append(self.snapshot(c))
            return If(cond, Block([Break(False, c.loops[i][0])]), None)
        c.loops[-1][1].append(self.snapshot(c))
        return If(cond, Block([Break(self.chance(0.3))]), None)

    def ret_expr(self, c):
        if c.ret is None:
            return None
        if c.ret == 'i':
            x = self.obs_expr(c, set())
            return x if x is not None else Lit(self.small())
        if c.ret == 'T':
            return self.texpr(c, 0)
        if c.ret == 'V':
            return self.vexpr(c)
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
        if c.ret is None and self.chance(0.6):
            return None
        cond = self.cond(c)
        snap = self.snapshot(c)
        x = self.ret_expr(c)
        self.restore(c, snap)
        return If(cond, Block([Return(x)]), None)

    def st_question(self, c):
        r = self.r.random()
        if c.ret == 'OI':
            if r < 0.5:
                m = self.take_var(c, 'O', set())
                if m is not None:
                    n = self.name('t')
                    self.declare(c, n, 'T', False)
                    return Question(n, m)
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
        ty = self.r.choice(['T', 'V', 'O', 'E', 'S', 'G', 'Tu', 'VS'])
        m = self.take_var(c, ty, set())
        if m is None:
            return None
        return Do(Call('drop', [Arg('sink', m)]))

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
            m = self.take_var(c, 'T', set())
            if m is not None:
                return CloBlock('sink', m.p, self.small(), self.obsn(), self.name('f'))
        m = self.take_var(c, 'T', set())
        if m is not None:
            # a sink closure kept as a local
            n = self.name('f')
            self.declare(c, n, 'F', False)
            return Decl(n, False, None, NewClo(m.p, self.small()))
        return None

    def st_match(self, c):
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
            pre = []
            for _ in range(k):
                if wild and self.chance(0.4):
                    names.append('_')
                else:
                    nm = self.name('t')
                    names.append(nm)
                    pre.append((nm, 'T', False, 'local'))
            b, s = self.sub_block(c, self.r.randint(0, 3), pre=pre)
            arms[tag] = (names, b)
            ends.append(s)
        if len(arms) < 3:
            self.restore(c, snap)
            b, s = self.sub_block(c, self.r.randint(0, 2))
            arms['_'] = (None, b)
            ends.append(s)
        self.branch_join(c, snap, ends)
        if wild:
            v.st = 'X'
        return MatchE(PVar(v.name), arms)

    def st_option(self, c):
        r = self.r.random()
        form = self.r.choice(['iflet', 'match'])
        if r < 0.45:
            m = self.take_var(c, 'O', set())
            if m is None:
                return None
            x, kind = m, 'O'
        elif r < 0.65:
            vp = self.v_places(c, need_mut=True)
            if not vp:
                return None
            x, kind = Call('pop', [], method=True, recv=self.r.choice(vp)), 'O'
        elif r < 0.85:
            x, kind = Call('tchk', [Arg('sink', self.texpr(c, 1)), Arg('val', Lit(self.r.randint(0, 12)))]), 'R'
        else:
            # `if o.is_some() { var t = o.unwrap(); .. }`: a conditional move
            os_ = self.movable(c, 'O')
            if not os_:
                return None
            v = self.r.choice(os_)
            n = self.name('t')

            def make():
                self.mark_moved(c, PVar(v.name))
                return self.gen_block(c, self.r.randint(0, 3), pre=[(n, 'T', True, 'local')])
            body = self.guarded(c, make)
            inner = Decl(n, True, None, Call('unwrap', [], method=True, recv=Move(PVar(v.name)), recv_conv='sink'))
            return If(Call('is_some', [], method=True, recv=PVar(v.name)), Block([inner] + body.stmts), None)
        snap = self.snapshot(c)
        n = self.name('t')
        en = self.name('n') if kind == 'R' else None
        t, st = self.sub_block(c, self.r.randint(0, 3), pre=[(n, 'T', False, 'local')])
        self.restore(c, snap)
        epre = [(en, 'i', False, 'local')] if kind == 'R' and form == 'match' else None
        e, se = self.sub_block(c, self.r.randint(0, 2), pre=epre)
        self.branch_join(c, snap, [st, se])
        return MatchOpt(x, kind, n, t, en, e, form)

    def st_struct(self, c):
        r = self.r.random()
        ss = [v for v in self.all_vars(c) if v.ty == 'S' and v.st == 'L' and v.name not in c.frozen]
        if r < 0.35 or not ss:
            n = self.name('s')
            x = self.sexpr(c, set())
            self.declare(c, n, 'S', True)
            return Decl(n, True, None, x)
        v = self.r.choice(ss)
        local = v.kind in ('local', 'sink') and v.loop == c.loop
        if r < 0.6 and local:
            f = self.r.choice(['t', 'w'])
            if v.fst[f] == 'L':
                # a partial move out of the struct
                n = self.name('t' if f == 't' else 'w')
                v.fst[f] = 'M'
                self.declare(c, n, 'T' if f == 't' else 'V', True)
                return Decl(n, True, None, Move(PField(PVar(v.name), f)))
        if r < 0.75 and local and v.mut and v.fst['t'] == 'L' and v.fst['w'] == 'L':
            # disjoint fields: s.t moves into s.w
            v.fst['t'] = 'M'
            return Do(Call('keep', [Arg('inout', PField(PVar(v.name), 'w')), Arg('sink', Move(PField(PVar(v.name), 't')))]))
        if r < 0.85 and v.mut and v.fst['t'] == 'L' and v.fst['w'] == 'L':
            return Do(Call('bump', [Arg('inout', PField(PVar(v.name), 't')), Arg('val', Read(PField(PVar(v.name), 'n')))]))
        if v.fst['w'] == 'L' and v.mut:
            return Do(Call('push', [Arg('sink', self.texpr(c, 1, {v.name}))], method=True, recv=PField(PVar(v.name), 'w')))
        return None

    def st_tuple(self, c):
        us = [v for v in self.all_vars(c) if v.ty == 'Tu' and v.st == 'L' and v.name not in c.frozen]
        r = self.r.random()
        if r < 0.45 or not us:
            n = self.name('u')
            used = set()
            a = self.texpr(c, 1, used)
            b = self.texpr(c, 1, used)
            self.declare(c, n, 'Tu', True)
            return Decl(n, True, None, NewTup(a, b))
        v = self.r.choice(us)
        local = v.kind in ('local', 'sink') and v.loop == c.loop
        if r < 0.65 and local:
            f = self.r.choice(['0', '1'])
            if v.fst[f] == 'L':
                n = self.name('t')
                v.fst[f] = 'M'
                self.declare(c, n, 'T', True)
                return Decl(n, True, None, Move(PField(PVar(v.name), f)))
        if r < 0.8 and local and self.whole(v):
            a, b = self.name('t'), self.name('t')
            v.st = 'M'
            self.declare(c, a, 'T', False)
            self.declare(c, b, 'T', False)
            return Destructure(a, b, PVar(v.name))
        return None

    def st_array(self, c):
        arrs = self.readable(c, 'A')
        if not arrs or self.chance(0.4):
            n = self.name('a')
            used = set()
            items = [self.texpr(c, 1, used), self.texpr(c, 1, used)]
            self.declare(c, n, 'A', True)
            return Decl(n, True, None, NewArr(items))
        v = self.r.choice(arrs)
        i = self.r.randint(0, 1)
        if v.mut and v.name not in c.frozen:
            if self.known and self.chance(0.3):
                return Assign(PIdx(PVar(v.name), i), self.texpr(c, 1, {v.name}))
            return Do(Call('bump', [Arg('inout', PIdx(PVar(v.name), i)), Arg('val', self.int_k(c))]))
        return Print(self.obsn(), [Read(PField(PIdx(PVar(v.name), i), 'v'))])

    def st_g(self, c):
        gs = self.readable(c, 'G')
        if not gs or self.chance(0.5):
            n = self.name('k')
            x = NewG(self.texpr(c, 1), self.r.randint(0, 9))
            self.declare(c, n, 'G', True)
            return Decl(n, True, None, x)
        v = self.r.choice(gs)
        if v.mut and v.name not in c.frozen:
            return OpAssign(PField(PVar(v.name), 'k'), Lit(self.r.randint(1, 5)))
        return None

    def st_vs(self, c):
        vss = self.readable(c, 'VS')
        if not vss or self.chance(0.3):
            n = self.name('q')
            self.declare(c, n, 'VS', True)
            return Decl(n, True, 'Vec<S>', NewVec())
        v = self.r.choice(vss)
        p = PVar(v.name)
        r = self.r.random()
        if not v.mut or v.name in c.frozen:
            return Print(self.obsn(), [Call('vssig', [Arg('let', p)])])
        if r < 0.4:
            return Do(Call('push', [Arg('sink', self.sexpr(c, {v.name}))], method=True, recv=p))
        i = self.r.randint(0, 2)
        lenp = Call('len', [], method=True, recv=p)
        if r < 0.6:
            x = self.guarded(c, lambda: self.texpr(c, 1, {v.name}))
            return If(Bin(lenp, '>', Lit(i)), Block([Do(Call('push', [Arg('sink', x)], method=True, recv=PField(PIdx(p, i), 'w')))]), None)
        if r < 0.75:
            return If(Bin(lenp, '>', Lit(i)), Block([OpAssign(PField(PField(PIdx(p, i), 't'), 'v'), self.int_k(c))]), None)
        if r < 0.9:
            n = self.name('s')
            body = self.guarded(c, lambda: self.gen_block(c, self.r.randint(0, 2), pre=[(n, 'S', True, 'local')]))
            inner = [Decl(n, True, None, Call('remove', [Arg('val', Lit(i))], method=True, recv=p))]
            return If(Bin(lenp, '>', Lit(i)), Block(inner + body.stmts), None)
        return Do(Call('truncate', [Arg('val', Lit(self.r.randint(0, 2)))], method=True, recv=p))

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
        if r < 0.7 and v.mut and v.name not in c.frozen:
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
        if v.mut and r < 0.7 and v.name not in c.frozen:
            return Do(Call('push_str', [Arg('val', StrLit(self.r.choice(['z', 'yy', '!'])))], method=True, recv=PVar(v.name)))
        n = self.name('g')
        self.declare(c, n, 'Str', True)
        return Decl(n, True, None, Call('clone', [], method=True, recv=PVar(v.name)))

    def st_inout(self, c):
        """`{ inout r = &place; .. }`: r used as the place itself."""
        ps = self.t_places(c, need_mut=True, elems=False)
        if not ps:
            return None
        p = self.r.choice(ps)
        n = self.name('r')
        rp = PVar(n)
        ops = []
        for _ in range(self.r.randint(1, 3)):
            k = self.r.random()
            if k < 0.25:
                ops.append(OpAssign(PField(rp, 'v'), self.int_k(c)))
            elif k < 0.45:
                ops.append(Do(Call('bump', [Arg('inout', rp), Arg('val', self.int_k(c))])))
            elif k < 0.6:
                ops.append(Do(Call('add', [Arg('val', self.int_k(c))], method=True, recv=rp)))
            elif k < 0.8:
                ops.append(Assign(rp, Mk(self.int_k(c))))
            else:
                ops.append(Print(self.obsn(), [Call('obs', [Arg('let', rp)]), Read(PField(rp, 'id'))]))
        return InoutBlock(n, p, Block(ops))

    def st_defer(self, c):
        return Defer(self.obsn())

    def st_shadow(self, c):
        """`let t = ..;` with the name of a visible T: the old one stays
        until its scope ends."""
        ts = [v for v in self.all_vars(c) if v.ty == 'T' and v.kind == 'local']
        if not ts:
            return None
        old = self.r.choice(ts)
        x = self.texpr(c)
        self.declare(c, old.name, 'T', self.chance(0.5))
        return Decl(old.name, self.var_of(c, old.name).mut, None, x)

    # ---- functions

    def gen_fn(self):
        name = 'f%d' % (len(self.fns) + 1)
        ret = self.r.choice(['i', 'i', 'T', 'V', 'OI', 'RI'])
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
        body = self.gen_block(c, self.r.randint(2, 8), tail_fn=self.ret_expr)
        return GenFn(name, params, ret, body)

    def program(self):
        for _ in range(self.r.randint(0, 3)):
            f = self.gen_fn()
            if f.body.tail is not None:
                self.fns.append(f)
        c = Ctx(None)
        c.scopes[0].append(Var('gpa', 'gpa', False, 'let', 0))
        body = self.gen_block(c, self.size + self.r.randint(-self.size // 3, self.size // 3))
        return Program(self.fns, GenFn('run', [], None, body))


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


def run_cmd(cmd, timeout=60):
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return p.returncode, p.stdout.decode('utf-8', 'replace'), p.stderr.decode('utf-8', 'replace')
    except subprocess.TimeoutExpired:
        return 124, '', 'timeout'


def check_program(volec, prog, work, tag, configs=CONFIGS):
    """('ok', None) or (kind, detail): invalid (the model's), reject (the
    checker's: OVERSTRICT or a generator bug), crash, exit, alloc
    (--check-alloc's report), oracle (not the expected output)."""
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
        if rc != 1:
            return ('crash', 'volec check exit %d: %s' % (rc, first))
        return ('reject', first.replace(src, 'p.vl'))
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
        if err.strip():
            return ('alloc', '%s: %s' % (name, err.strip().splitlines()[0]))
        d = compare(events, lines)
        if d is not None:
            return ('oracle', '%s: %s' % (name, d))
    return ('ok', None)


# ---------------------------------------------------------------- shrinking

def blocks_of(prog):
    """Every statement list of the program."""
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
        elif isinstance(s, (For, While)):
            walk_block(s.body)
        elif isinstance(s, MatchE):
            for _, b in s.arms.values():
                walk_block(b)
        elif isinstance(s, MatchOpt):
            walk_block(s.then)
            if s.els is not None:
                walk_block(s.els)
        elif isinstance(s, InoutBlock):
            walk_block(s.body)

    for f in prog.fns:
        walk_block(f.body)
    walk_block(prog.run_fn.body)
    return out


def shrink(volec, prog, kind, work, budget=600):
    """Deletes statements (and functions) while check_program keeps giving
    `kind`; an if is also replaced by one of its blocks."""
    state = {'n': 0}

    def still(p):
        state['n'] += 1
        if state['n'] > budget:
            return False
        k, _ = check_program(volec, p, work, 'shrink%d' % state['n'])
        return k == kind
    progress = True
    while progress and state['n'] <= budget:
        progress = False
        for f in list(prog.fns):
            saved = prog.fns
            prog.fns = [g for g in prog.fns if g is not f]
            if still(prog):
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
                if still(prog):
                    progress = True
                else:
                    lst.insert(i, s)
                    if isinstance(s, If):
                        for repl in (s.then, s.els):
                            if repl is None:
                                continue
                            lst[i] = repl
                            if still(prog):
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
    if not os.access(volec, os.X_OK):
        print('sem-fuzz: no compiler at %s' % volec)
        return 2
    work = tempfile.mkdtemp(prefix='vole-semfuzz.')
    if a.shrink is not None:
        prog = Gen(a.shrink, a.known, a.size).program()
        kind, detail = check_program(volec, prog, work, 'p')
        print('// %s: %s' % (kind, detail))
        if kind not in ('ok', 'invalid'):
            small = shrink(volec, prog, kind, work, budget=2000)
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
            if kind != 'invalid' and not a.no_shrink:
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
    print('fuzz: %d value-semantics programs, %d failing (%s)' % (len(seeds), bad, summary))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
