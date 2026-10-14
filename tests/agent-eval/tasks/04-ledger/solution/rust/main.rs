// Bank ledger: commands on named accounts, errors per line, sorted reports.
use std::collections::HashMap;
use std::io::{self, Read, Write};

#[derive(Clone, Copy)]
struct Account<'a> {
    name: &'a [u8],
    balance: i64,
    txns: i64,
}

enum Command<'a> {
    Open(&'a [u8]),
    Deposit(&'a [u8], i64),
    Withdraw(&'a [u8], i64),
    Transfer(&'a [u8], &'a [u8], i64),
    Close(&'a [u8]),
    Balance(&'a [u8]),
    Report,
    Blank,
    Bad(&'static str),
}

fn valid_name(s: &[u8]) -> bool {
    if s.is_empty() || s.len() > 16 {
        return false;
    }
    for &ch in s {
        let ok = (ch >= b'a' && ch <= b'z') || (ch >= b'0' && ch <= b'9') || ch == b'_';
        if !ok {
            return false;
        }
    }
    true
}

// The amount, or 0 when it is not valid.
fn parse_amount(s: &[u8]) -> i64 {
    if s.is_empty() || s.len() > 12 {
        return 0;
    }
    let mut n: i64 = 0;
    for &ch in s {
        if ch < b'0' || ch > b'9' {
            return 0;
        }
        n = n * 10 + (ch - b'0') as i64;
    }
    n
}

fn split_tokens(line: &[u8]) -> Vec<&[u8]> {
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < line.len() {
        if line[i] == b' ' {
            i += 1;
            continue;
        }
        let start = i;
        while i < line.len() && line[i] != b' ' {
            i += 1;
        }
        tokens.push(&line[start..i]);
    }
    tokens
}

fn parse_command(line: &[u8]) -> Command<'_> {
    let t = split_tokens(line);
    if t.is_empty() {
        return Command::Blank;
    }
    let (args, names, amount): (usize, usize, bool) = match t[0] {
        b"open" | b"close" | b"balance" => (1, 1, false),
        b"deposit" | b"withdraw" => (2, 1, true),
        b"transfer" => (3, 2, true),
        b"report" => (0, 0, false),
        _ => return Command::Bad("error: bad command"),
    };
    if t.len() != args + 1 {
        return Command::Bad("error: bad command");
    }
    for k in 1..names + 1 {
        if !valid_name(t[k]) {
            return Command::Bad("error: bad name");
        }
    }
    let mut amt = 0;
    if amount {
        amt = parse_amount(t[args]);
        if amt == 0 {
            return Command::Bad("error: bad amount");
        }
    }
    match t[0] {
        b"open" => Command::Open(t[1]),
        b"close" => Command::Close(t[1]),
        b"balance" => Command::Balance(t[1]),
        b"deposit" => Command::Deposit(t[1], amt),
        b"withdraw" => Command::Withdraw(t[1], amt),
        b"transfer" => Command::Transfer(t[1], t[2], amt),
        _ => Command::Report,
    }
}

fn push_account(out: &mut Vec<u8>, a: &Account) {
    out.extend_from_slice(a.name);
    out.push(b' ');
    out.extend_from_slice(a.balance.to_string().as_bytes());
    out.push(b' ');
    out.extend_from_slice(a.txns.to_string().as_bytes());
    out.push(b'\n');
}

fn report(accounts: &HashMap<&[u8], Account>, out: &mut Vec<u8>) {
    let mut list: Vec<Account> = Vec::new();
    let mut total: i64 = 0;
    for a in accounts.values() {
        list.push(*a);
        total += a.balance;
    }
    list.sort_by(|a, b| a.name.cmp(b.name));
    out.extend_from_slice(format!("accounts: {}, total: {}\n", list.len(), total).as_bytes());
    for a in &list {
        push_account(out, a);
    }
}

fn execute<'a>(
    cmd: Command<'a>,
    accounts: &mut HashMap<&'a [u8], Account<'a>>,
    out: &mut Vec<u8>,
) -> Result<(), &'static str> {
    match cmd {
        Command::Blank => {}
        Command::Bad(msg) => return Err(msg),
        Command::Report => report(accounts, out),
        Command::Open(name) => {
            if accounts.contains_key(name) {
                return Err("error: account exists");
            }
            accounts.insert(name, Account { name, balance: 0, txns: 0 });
        }
        Command::Balance(name) => match accounts.get(name) {
            Some(a) => push_account(out, a),
            None => return Err("error: no such account"),
        },
        Command::Close(name) => {
            let a = match accounts.get(name) {
                Some(a) => *a,
                None => return Err("error: no such account"),
            };
            if a.balance != 0 {
                return Err("error: balance not zero");
            }
            accounts.remove(name);
        }
        Command::Deposit(name, amt) => {
            let a = accounts.get_mut(name).ok_or("error: no such account")?;
            a.balance += amt;
            a.txns += 1;
        }
        Command::Withdraw(name, amt) => {
            let a = accounts.get_mut(name).ok_or("error: no such account")?;
            if a.balance < amt {
                return Err("error: insufficient funds");
            }
            a.balance -= amt;
            a.txns += 1;
        }
        Command::Transfer(from, to, amt) => {
            let mut src = *accounts.get(from).ok_or("error: no such account")?;
            let mut dst = *accounts.get(to).ok_or("error: no such account")?;
            if from == to {
                return Err("error: same account");
            }
            if src.balance < amt {
                return Err("error: insufficient funds");
            }
            src.balance -= amt;
            src.txns += 1;
            dst.balance += amt;
            dst.txns += 1;
            accounts.insert(from, src);
            accounts.insert(to, dst);
        }
    }
    Ok(())
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).unwrap();
    let mut accounts: HashMap<&[u8], Account> = HashMap::new();
    let mut out = Vec::new();
    for line in input.split(|&b| b == b'\n') {
        if let Err(msg) = execute(parse_command(line), &mut accounts, &mut out) {
            out.extend_from_slice(msg.as_bytes());
            out.push(b'\n');
        }
    }
    io::stdout().write_all(&out).unwrap();
}
