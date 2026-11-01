use std::{path::Path, process::Command};

// `diatweaks update` compares this with the newest commit to tell whether there's anything new.
fn main() {
    let commit = git(&["rev-parse", "HEAD"]).unwrap_or_else(|| "unknown".into());
    println!("cargo:rustc-env=DIATWEAKS_COMMIT={commit}");

    let mut watched = vec!["HEAD".to_string(), "packed-refs".to_string()];
    watched.extend(git(&["symbolic-ref", "-q", "HEAD"]));
    for name in watched {
        let Some(path) = git(&["rev-parse", "--git-path", &name]) else {
            continue;
        };
        // A missing path would make Cargo rerun this on every build, and install.sh relies on a no-op rebuild.
        if Path::new(&path).exists() {
            println!("cargo:rerun-if-changed={path}");
        }
    }
}

fn git(args: &[&str]) -> Option<String> {
    let output = Command::new("git").args(args).output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    (output.status.success() && !text.is_empty()).then_some(text)
}
