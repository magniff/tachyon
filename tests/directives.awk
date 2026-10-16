# The directives of a test case (listed at the top of tests/run.sh), one
# file per directive in directory `dir`: args, stdin, expect, exit, errors,
# xfail, flags, ... Shared by tests/run.sh and tests/objcheck.sh:
#   awk -v dir=DIR -v target=TARGET -f tests/directives.awk CASE
{
    line = $0
    sub(/\r$/, "", line)
    sub(/^[ \t]+/, "", line)
    if (substr(line, 1, 2) != "//") next
    c = substr(line, 3)
    if (substr(c, 1, 1) == " ") c = substr(c, 2)
    i = index(c, ":")
    if (i == 0) next
    key = substr(c, 1, i - 1)
    value = substr(c, i + 1)
    if (substr(value, 1, 1) == " ") value = substr(value, 2)
    if (key == "ARGS") args = value
    else if (key == "STDIN") stdin = stdin (nstdin++ ? "\n" : "") value
    else if (key == "EXPECT") expect = expect (nexpect++ ? "\n" : "") value
    else if (key == "EXIT") exitcode = value + 0
    else if (key == "STDERR") stderrs = stderrs value "\n"
    else if (key == "ERROR") errors = errors value "\n"
    else if (key == "ERROR-COUNT") errcount = value
    else if (key == "XFAIL" || key == "XFAIL(" target ")") xfail = value
    else if (key == "SOURCE") source = value
    else if (key == "CSOURCE") csources = csources " " value
    else if (key == "CHEADER") cheader = value
    else if (key == "BUILD") build = 1
    else if (key == "CHECK") checks = checks "+" value "\n"
    else if (key == "CHECK-NOT") checks = checks "-" value "\n"
    else if (key == "CHECK-OPT") checkopt = value
    else if (key == "ASM(" target ")") asms = asms "+" value "\n"
    else if (key == "ASM-NOT(" target ")") asms = asms "-" value "\n"
    else if (key == "FIXIMPORTS") fiximports = 1
    else if (key == "FIXUNSAFE") fiximports = 2
    else if (key == "FIXED") fixed = fixed value "\n"
    else if (key == "FLAGS") flags = flags " " value
    else if (key == "WARNING") warnings = warnings value "\n"
    else if (key == "PROFILE") profile = 1
    else if (key == "LINK") link = 1
    else if (key == "NO-EXTRA-FLAGS") noextra = 1
    else if (key == "REQUIRES") requires = requires " " value
}
END {
    printf "%s", args > (dir "/args")
    printf "%s", stdin > (dir "/stdin")
    printf "%s", expect > (dir "/expect")
    printf "%d", exitcode > (dir "/exit")
    printf "%s", stderrs > (dir "/stderrs")
    printf "%s", errors > (dir "/errors")
    printf "%s", errcount > (dir "/errcount")
    printf "%s", xfail > (dir "/xfail")
    printf "%s", source > (dir "/source")
    printf "%s", csources > (dir "/csources")
    printf "%s", cheader > (dir "/cheader")
    printf "%d", build > (dir "/build")
    printf "%s", checks > (dir "/checks")
    printf "%s", asms > (dir "/asms")
    printf "%s", (checkopt == "" ? "2" : checkopt) > (dir "/checkopt")
    printf "%d", fiximports > (dir "/fiximports")
    printf "%s", fixed > (dir "/fixed")
    printf "%s", flags > (dir "/flags")
    printf "%s", warnings > (dir "/warnings")
    printf "%d", profile > (dir "/profile")
    printf "%d", link > (dir "/link")
    printf "%d", noextra > (dir "/noextra")
    printf "%s", requires > (dir "/requires")
}
