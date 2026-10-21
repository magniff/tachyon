# Run by compiler/std/embed.sh over std's source (std.tach and the files
# appended to it, as std_source writes it): the index of its sections,
# one line each, for the loader (front/modules: std_sections), which lexes
# only the sections a program can reach (0.15).
#
# A section starts at a banner line `// ---- Title ----` (the text before
# the first one is a section too). A line of the index:
#
#     START END CORE|WORDS|ITEMS|IMPLS|DEPS
#
# START, END: its bytes in the text; CORE: 1 when it is always loaded;
# WORDS: the words of a program that ask for it: the items it defines, the
# methods of its impls of other sections' types (`Option::map`), and
# TRIGGERS below; ITEMS: the items it defines; IMPLS: `Trait Type` pairs of
# its trait impls (Type `*` for one that is no item of std: a primitive, a
# slice, a type parameter); DEPS: the sections it needs (it names what
# they define, or uses an impl of theirs; 0.21: a name it can see, as
# std's modules resolve it, not one another module defines too).
#
# LAZY lists the titles of the sections loaded only when reached, and
# TRIGGERS words that ask for one besides its names (what the compiler
# itself calls). Every other section is core, and so is what a core
# section needs. (POSIX awk; LC_ALL=C: lengths are bytes.)
#
# (0.20) std's modules: embed.sh puts each between the banners `// ---- mod
# std::a ----` and `// ---- end mod std::a ----`; the first section holds
# its `mod a {` line and its file's header and `use` lines, the last its
# `}`, and both are core. The module's items before its first banner are
# a section titled `std::a`. `use` lines need no section (a `use` of a
# section not read imports nothing: front/modules/lookup).

BEGIN {
    n = split("Stable sort (0.15)|HashMap|Debug of HashMap (0.15)|== on HashMap (0.15)|Iterators (0.14)|Adapters|Sources|Text (0.14)|Errors of reading and parsing (0.15)|Integer limits (0.15)|Bits (0.16)|Conversions (0.15)|Clone and hashing (0.15)|Clone, Eq, Ord and Hash without an impl (0.15)|Arenas (0.16)|FixedBuf (0.16)|HashMap's room (0.16)|Slices (0.16)|Gpa's leak checks (0.16)|The checking allocator's hooks for arenas (0.16)|Panic and unreachable, the prelude's (0.17)|Testing (0.18)|Non-null pointers (0.18)|The test runtime's implementation (0.18)|The fuzzer's implementation (0.18)|Heaps (0.18.1)|More of Vec and Range (0.18.1)|Run-time CPU features (0.19)|CPU features on macOS (0.19)|CPU features on Linux (0.19)|CPU features on x86-64 (0.19)|std::iter|std::convert|std::clone|Numbers: bits and wide products (0.20)|Numbers: digits (0.20)|Numbers: integer text (0.20)|Numbers: the shortest digits of a float (0.20)|Numbers: float text (0.20)|Numbers: float parsing (0.20)|Numbers: float parsing's slow path (0.20)|Numbers: powers of ten (0.20)|Numbers: the slow path's digits of 5^s (0.20)|Display and Debug of floats (0.20)|Sorting (0.9)|Sort kernels (0.20)|Sort, unstable (0.20)|Sort, stable (0.20)|Slice searches (0.20)|Slice algorithms (0.20)|Random numbers (0.20)|The target's system (0.20)|Duration (0.20)|Clocks (0.20)|Sys: errors (0.20)|Sys: paths (0.20)|Sys: files (0.20)|Sys: file status (0.20)|Sys: directories (0.20)|Sys: the environment (0.20)|Sys: processes (0.20)|Sys: terminals (0.20)|Sys: clocks and entropy (0.20)|UTF-8 (0.20)|UTF-8 with NEON (0.20)|Unicode tables: properties (0.20)|Unicode tables: classes (0.20)|Unicode tables: case (0.20)|Unicode properties (0.20)|Grapheme clusters (0.20)|Display width (0.20)|Unicode classes and case (0.20)|Text: str (0.20)|Text: str's iterators (0.20)|Text: parsing (0.20)|Text: String (0.20)|I/O errors (0.20)|Reading and writing (0.20)|Buffered reading and writing (0.20)|The standard streams (0.20)|Paths (0.20)|Files (0.20)|Whole files (0.20)|Directories (0.20)|Arguments (0.20)|The environment (0.20)|The working directory (0.20)|Processes (0.20)|Hashing and comparing helpers (0.15)|HashSet (0.20)|Swiss table (0.20 implementation)|Swiss-table groups (0.20 implementation)|B-tree nodes (0.20 implementation)|BTreeMap and BTreeSet (0.20)|foldhash (0.20 implementation)|SipHash (0.20 implementation)|Hasher builders (0.20 implementation)", lz, "|")
    for (i = 1; i <= n; i++) LAZY[lz[i]] = 1
    # (0.20) GATES: modules whose items no program reaches without naming
    # the module (no re-export outside it): a word of one of their lazy
    # sections asks for it only from a program that also names the module's
    # gate word, written first in the section's words as `+WORD` (the
    # loader: front/modules/stdsections.tach), so that a program's own
    # `props` or `to_lower` loads no Unicode table.
    GATES["std::str"] = "str"
    GATES["std::unicode"] = "unicode"
    GATES["std::unicode::tables"] = "unicode"
    nmod = 0
    TRIGGERS["Iterators (0.14)"] = "Iterator IntoIterator"
    # (0.20: the Iterator trait in std::iter, before its first banner)
    TRIGGERS["std::iter"] = "Iterator IntoIterator"
    # (0.20) str's methods, which a string literal has ("a,b".split(','))
    TRIGGERS["Text: str (0.20)"] = "str String trim chars char_indices lines split splitn split_once rsplit_once split_whitespace split_ascii_whitespace trim_start trim_end trim_matches trim_start_matches trim_end_matches strip_prefix strip_suffix starts_with ends_with find rfind matches parse to_uppercase_in to_lowercase_in to_ascii_uppercase_in to_ascii_lowercase_in replace_in replacen_in repeat_in to_string_in to_owned_in to_uppercase to_lowercase to_string to_owned replace repeat eq_ignore_ascii_case is_char_boundary char_count width graphemes from_utf8"
    TRIGGERS["Conversions (0.15)"] = "From Into main_error"
    TRIGGERS["Clone, Eq, Ord and Hash without an impl (0.15)"] = "Eq Ord Hash Clone clone cmp eq hash sort sort_by sort_stable HashMap distinct NonNull BinaryHeap MinHeap contains sort_by_key"
    # (0.17) Words std's own code uses that need a section too: `x.clone()`
    # of a number (Vec::filled_in) is copy_clone
    NEEDS["Clone, Eq, Ord and Hash without an impl (0.15)"] = "clone"
    s = 0
    start[0] = 0
    title[0] = ""
    pos = 0
    secmod[0] = "std"
}

function use_word(sec, w) {
    if (!((sec, w) in USES)) {
        USES[sec, w] = 1
        uses_list[sec] = uses_list[sec] " " w
    }
}

# Name w defined in section sec; `key` when it is an item (what another
# section needs it for), not a method.
function def_word(sec, w, key) {
    if (!((sec, w) in DEFS)) {
        DEFS[sec, w] = 1
        defs_list[sec] = defs_list[sec] " " w
        DEFINED[w] = 1
    }
    if (key && !((sec, w) in KEYS)) {
        KEYS[sec, w] = 1
        keys_list[sec] = keys_list[sec] " " w
    }
}

# The text of a type or trait without its generic arguments: `HashMap<K, V>`
# is `HashMap`, `std::Ord` is `Ord`.
function head_name(t,    m) {
    sub(/^[ \t]+/, "", t)
    if (match(t, /^[A-Za-z_][A-Za-z0-9_:]*/)) {
        t = substr(t, 1, RLENGTH)
        while ((m = index(t, "::")) > 0) t = substr(t, m + 2)
        return t
    }
    return "*"
}

# `impl<T> Type<T> {`: `Type`.
function inherent_type(h,    i, c, depth) {
    sub(/^impl/, "", h)
    if (substr(h, 1, 1) == "<") {
        depth = 0
        for (i = 1; i <= length(h); i++) {
            c = substr(h, i, 1)
            if (c == "<") depth++
            else if (c == ">") { depth--; if (depth == 0) break }
        }
        h = substr(h, i + 1)
    }
    return head_name(h)
}

# `impl<...> Trait<..> for Type<..> {`: the pair, or "" for an inherent impl.
function impl_pair(h,    i, c, depth, rest, f) {
    sub(/^impl/, "", h)
    sub(/\{.*$/, "", h)
    # (the impl's own parameters)
    if (substr(h, 1, 1) == "<") {
        depth = 0
        for (i = 1; i <= length(h); i++) {
            c = substr(h, i, 1)
            if (c == "<") depth++
            else if (c == ">") { depth--; if (depth == 0) break }
        }
        h = substr(h, i + 1)
    }
    # ` for ` outside brackets
    depth = 0
    for (i = 1; i <= length(h); i++) {
        c = substr(h, i, 1)
        if (c == "<" || c == "(" || c == "[") depth++
        else if (c == ">" || c == ")" || c == "]") depth--
        else if (depth == 0 && substr(h, i, 5) == " for ") {
            return head_name(substr(h, 1, i - 1)) " " head_name(substr(h, i + 5))
        }
    }
    return ""
}

# (0.20) Section s starts at byte pos, titled t.
function new_section(t) {
    end_[s] = pos
    s++
    start[s] = pos
    title[s] = t
    gate[s] = nmod > 0 && (modstack[nmod] in GATES) ? GATES[modstack[nmod]] : ""
    secmod[s] = nmod > 0 ? modstack[nmod] : "std"
}

# (0.21) The module a `use` path's first segments name, from module m:
# `std::a`, `crate::a`, `super::a`, `self::a`, or `a` (a child of m).
function use_source(m, segs, n,    k, r) {
    k = 1
    if (segs[1] == "std" || segs[1] == "crate") { r = "std"; k = 2 }
    else if (segs[1] == "self") { r = m; k = 2 }
    else {
        r = m
        while (k < n && segs[k] == "super") { sub(/::[A-Za-z0-9_]*$/, "", r); k++ }
    }
    for (; k < n; k++) r = r "::" segs[k]
    return r
}

# (0.21) A `use` line's path `a::b::w`: w imported into module m from the
# module the rest names (IMPORT; `self`, a module, imports no item).
function use_path(m, path,    segs, n) {
    n = split(path, segs, "::")
    if (n < 2 || segs[n] == "self") return
    IMPORT[m, segs[n]] = IMPORT[m, segs[n]] " " use_source(m, segs, n)
}

# (0.21) A `use` statement's text (without `use` and `pub`), its tree
# flattened into paths.
function use_tree(m, t,    d, cur, pre, tok) {
    d = 0
    pre[0] = ""
    cur = ""
    while (match(t, /[A-Za-z_][A-Za-z0-9_]*|[{},;]/)) {
        tok = substr(t, RSTART, RLENGTH)
        t = substr(t, RSTART + RLENGTH)
        if (tok == "{") { pre[++d] = cur }
        else if (tok == "," || tok == ";") { if (cur != pre[d]) use_path(m, cur); cur = pre[d] }
        else if (tok == "}") { if (cur != pre[d]) use_path(m, cur); d--; cur = pre[d] }
        else cur = cur == "" ? tok : cur "::" tok
    }
}

# (0.21) Whether name w in module m can be the item of section j: j in m,
# or w imported into m from a module where it can be (re-exports).
function visible_in(m, w, j, depth,    n, src, k) {
    if (secmod[j] == m) return 1
    if (depth > 8) return 0
    n = split(IMPORT[m, w], src, " ")
    for (k = 1; k <= n; k++) if (visible_in(src[k], w, j, depth + 1)) return 1
    return 0
}

# (0.21) Whether section i's use of w (a key item of section j) can mean
# j's: a bare w resolved in i's module, std's root (its items and
# imports: the prelude and more); a path `q::w` when q is a module j is
# in (a type's `T::w` is an associated item, no item of j); `std::w`,
# `crate::w` as in the root; any other path (`super::`, `<T as A>::`) as
# can be.
function sees(i, w, j,    n, qs, k, q) {
    if ((i, w) in BARE && (secmod[j] == "std" || visible_in(secmod[i], w, j, 0) || visible_in("std", w, j, 0)))
        return 1
    n = split(QUALBY[i, w], qs, " ")
    for (k = 1; k <= n; k++) {
        q = qs[k]
        if (q == "std" || q == "crate") { if (secmod[j] == "std" || visible_in("std", w, j, 0)) return 1 }
        else if (q ~ /^[A-Z]/ || q == "Self") continue
        else if (q == "?" || q == "super" || q == "self") return 1
        else if (("::" secmod[j] "::") ~ ("::" q "::")) return 1
    }
    return 0
}

{
    line = $0
    len = length(line) + 1
    if (line ~ /^\/\/ ---- .* ----$/) {
        t = line
        sub(/^\/\/ ---- /, "", t)
        sub(/ ----$/, "", t)
        # (the module a section is in: `mod std::a`, `end mod std::a`)
        if (t ~ /^mod std::/) modstack[++nmod] = substr(t, 5)
        else if (t ~ /^end mod std::/ && nmod > 0) nmod--
        new_section(t)
    } else if (title[s] ~ /^mod / && line ~ /^[^ \t\/}]/ && line !~ /^(pub )?(mod|use) /) {
        # (0.20) A module's items before its first banner: a section of
        # their own, titled with the module's path, not its `mod` line's
        # (always read)
        t = title[s]
        sub(/^mod /, "", t)
        new_section(t)
    }
    pos += len
    # (0.20) `use` lines name what the code below them uses, and a `use`
    # of a section not read imports nothing: they need no section. (0.21)
    # What they import is visible in their module (IMPORT). `mod` lines
    # name a module, no item.
    if (in_use || line ~ /^(pub )?use /) {
        u = line
        sub(/\/\/.*$/, "", u)
        if (!in_use) { sub(/^(pub )?use /, "", u); use_text = "" }
        use_text = use_text " " u
        in_use = index(line, ";") == 0
        if (!in_use) use_tree(secmod[s], use_text)
        next
    }
    if (line ~ /^(pub )?mod [A-Za-z_][A-Za-z0-9_]*( \{|;)/) next
    code = line
    # (comments, strings and characters hold no names)
    gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
    gsub(/'([^'\\]|\\.)*'/, "' '", code)
    sub(/\/\/.*$/, "", code)
    if (code ~ /^impl[ <]/) {
        p = impl_pair(code)
        if (p != "") impls[s] = impls[s] " " p
        # (an inherent impl's type: its methods ask for the section when
        # the type is another section's, `Option::map`)
        cur_type = p == "" ? inherent_type(code) : ""
    }
    if (code ~ /^}/) cur_type = ""
    key = code !~ /^[ \t]/
    # (`for x in it` with no range needs the iterators; `?`, From)
    if (match(code, /(^|[^A-Za-z0-9_])for [^{]* in [^{]*/)) {
        f = substr(code, RSTART, RLENGTH)
        sub(/^.* in /, "", f)
        if (index(f, "..") == 0) use_word(s, "IntoIterator")
    }
    if (index(code, "?") > 0) use_word(s, "From")
    rest = code
    defined_here = 0
    prev = ""
    while (match(rest, /[A-Za-z_][A-Za-z0-9_]*/)) {
        w = substr(rest, RSTART, RLENGTH)
        # (0.21) how w is named: by a path `q::w` (QUALBY: q, or `?` when
        # the path's start is no name), after a `.` (a method or field: no
        # item), or bare
        before = RSTART > 2 ? substr(rest, RSTART - 2, 2) : ""
        if (before == "::") QUALBY[s, w] = QUALBY[s, w] " " (RSTART == 3 && prev != "" ? prev : "?")
        else if (substr(before, 2, 1) != "." || before == "..") BARE[s, w] = 1
        prev = w
        rest = substr(rest, RSTART + RLENGTH)
        if (w == "fn" || w == "struct" || w == "enum" || w == "trait" || w == "type" || w == "const" || w == "static") {
            # (`static var X`, 0.20's spelling: X, not `var`)
            if (match(rest, /^[ \t]+((mut|var)[ \t]+)?[A-Za-z_][A-Za-z0-9_]*/)) {
                d = substr(rest, RSTART, RLENGTH)
                sub(/^[ \t]+((mut|var)[ \t]+)?/, "", d)
                def_word(s, d, key && !defined_here)
                if (!key && cur_type != "") {
                    nm++
                    meth_sec[nm] = s
                    meth_name[nm] = d
                    meth_type[nm] = cur_type
                }
                defined_here = 1
            }
            continue
        }
        use_word(s, w)
    }
}

END {
    end_[s] = pos
    count = s
    # The impls' types that are no item of std: `*`.
    for (i = 0; i <= count; i++) {
        np = split(impls[i], ip, " ")
        out = ""
        for (k = 1; k + 1 <= np; k += 2) {
            ty = ip[k + 1]
            if (!(ty in DEFINED) && ty != "f64" && ty != "f32") ty = "*"
            out = out " " ip[k] " " ty
        }
        impls[i] = out
    }
    # What each section needs.
    for (i = 0; i <= count; i++) {
        for (j = 0; j <= count; j++) {
            if (i == j) continue
            need = 0
            # (0.21) an item of j by its name in i, when i can see it (sees):
            # std's modules (0.20) define the same names for other things
            # (std::io's Result, std::fs's write, std::env's get)
            nd = split(keys_list[j], dw, " ")
            for (k = 1; k <= nd && !need; k++) if ((i, dw[k]) in USES && sees(i, dw[k], j)) need = 1
            nd = split(NEEDS[title[j]], dw, " ")
            for (k = 1; k <= nd && !need; k++) if ((i, dw[k]) in USES) need = 1
            np = split(impls[j], ip, " ")
            for (k = 1; k + 1 <= np && !need; k += 2) {
                tr = ip[k]
                ty = ip[k + 1]
                if (((i, tr) in USES || (i, tr) in DEFS) && (ty == "*" || (i, ty) in USES || (i, ty) in DEFS)) need = 1
            }
            if (need) deps[i] = deps[i] " " j
        }
        core[i] = !(title[i] in LAZY)
    }
    # What a core section needs is core.
    changed = 1
    while (changed) {
        changed = 0
        for (i = 0; i <= count; i++) {
            if (!core[i]) continue
            nd = split(deps[i], dd, " ")
            for (k = 1; k <= nd; k++) if (!core[dd[k]]) { core[dd[k]] = 1; changed = 1 }
        }
    }
    for (i = 0; i <= count; i++) {
        words = keys_list[i]
        for (k = 1; k <= nm; k++) {
            if (meth_sec[k] == i && !((i, meth_type[k]) in KEYS) && !((i, meth_name[k]) in SAID)) {
                SAID[i, meth_name[k]] = 1
                words = words " " meth_name[k]
            }
        }
        if (title[i] in TRIGGERS) words = words " " TRIGGERS[title[i]]
        if (!core[i] && gate[i] != "") words = " +" gate[i] words
        printf "%d %d %d|%s|%s|%s|%s\n", start[i], end_[i], core[i], substr(words, 2), substr(keys_list[i], 2), substr(impls[i], 2), substr(deps[i], 2)
    }
    # (the titles, for a reader of the index: not read by the compiler)
    for (i = 0; i <= count; i++) printf "# %d %s%s\n", i, title[i], core[i] ? "" : " (lazy)"
}
