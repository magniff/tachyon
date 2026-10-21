fn main() {
    let rustc = std::env::var("RUSTC").unwrap_or_else(|_| "rustc".into());
    let v = std::process::Command::new(rustc).arg("--version").output().ok()
        .and_then(|o| String::from_utf8(o.stdout).ok()).unwrap_or_default();
    let v = v.split_whitespace().nth(1).unwrap_or("unknown").to_string();
    println!("cargo:rustc-env=RUSTC_VERSION={v}");
}
