# tests/examples/voltty-core_pty.test: a 200 KB paste through the pty (the
# terminal in raw mode; `ready` tells voltty to start typing), then a
# cursor position report answered by the terminal.
stty raw -echo
printf 'ready'
n=$(head -c 200000 | wc -c | tr -d ' ')
printf '\r\n%s\r\n\033[1;31mred\033[0m\033[6n' "$n"
r=$(dd bs=1 count=6 2>/dev/null | tr '\033' E)
printf '\r\n%s\r\n' "$r"
