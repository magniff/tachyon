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
# they define, or uses an impl of theirs).
#
# LAZY lists the titles of the sections loaded only when reached, and
# TRIGGERS words that ask for one besides its names (what the compiler
# itself calls). Every other section is core, and so is what a core
# section needs. (POSIX awk; LC_ALL=C: lengths are bytes.)

BEGIN {
    n = split("Stable sort (0.15)|HashMap|Debug of HashMap (0.15)|== on HashMap (0.15)|Iterators (0.14)|Adapters|Sources|Text (0.14)|Errors of reading and parsing (0.15)|Integer limits (0.15)|Bits (0.16)|Conversions (0.15)|Clone and hashing (0.15)|Clone, Eq, Ord and Hash without an impl (0.15)|Arenas (0.16)|FixedBuf (0.16)|HashMap's room (0.16)|Slices (0.16)|Gpa's leak checks (0.16)|The checking allocator's hooks for arenas (0.16)|Panic and unreachable, the prelude's (0.17)|Testing (0.18)|Non-null pointers (0.18)|The test runtime's implementation (0.18)|The fuzzer's implementation (0.18)", lz, "|")
    for (i = 1; i <= n; i++) LAZY[lz[i]] = 1
    TRIGGERS["Iterators (0.14)"] = "Iterator IntoIterator"
    TRIGGERS["Conversions (0.15)"] = "From Into main_error"
    TRIGGERS["Clone, Eq, Ord and Hash without an impl (0.15)"] = "Eq Ord Hash Clone clone cmp eq hash sort sort_by sort_stable HashMap distinct NonNull"
    # (0.17) Words std's own code uses that need a section too: `x.clone()`
    # of a number (Vec::filled_in) is copy_clone
    NEEDS["Clone, Eq, Ord and Hash without an impl (0.15)"] = "clone"
    s = 0
    start[0] = 0
    title[0] = ""
    pos = 0
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

{
    line = $0
    len = length(line) + 1
    if (line ~ /^\/\/ ---- .* ----$/) {
        end_[s] = pos
        s++
        start[s] = pos
        t = line
        sub(/^\/\/ ---- /, "", t)
        sub(/ ----$/, "", t)
        title[s] = t
    }
    pos += len
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
    while (match(rest, /[A-Za-z_][A-Za-z0-9_]*/)) {
        w = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        if (w == "fn" || w == "struct" || w == "enum" || w == "trait" || w == "type" || w == "const" || w == "static") {
            if (match(rest, /^[ \t]+(mut[ \t]+)?[A-Za-z_][A-Za-z0-9_]*/)) {
                d = substr(rest, RSTART, RLENGTH)
                sub(/^[ \t]+(mut[ \t]+)?/, "", d)
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
            if (!(ty in DEFINED)) ty = "*"
            out = out " " ip[k] " " ty
        }
        impls[i] = out
    }
    # What each section needs.
    for (i = 0; i <= count; i++) {
        for (j = 0; j <= count; j++) {
            if (i == j) continue
            need = 0
            nd = split(keys_list[j], dw, " ")
            for (k = 1; k <= nd && !need; k++) if ((i, dw[k]) in USES) need = 1
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
        printf "%d %d %d|%s|%s|%s|%s\n", start[i], end_[i], core[i], substr(words, 2), substr(keys_list[i], 2), substr(impls[i], 2), substr(deps[i], 2)
    }
    # (the titles, for a reader of the index: not read by the compiler)
    for (i = 0; i <= count; i++) printf "# %d %s%s\n", i, title[i], core[i] ? "" : " (lazy)"
}
