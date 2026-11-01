use std::{
    path::{Path, PathBuf},
    process::Command,
    thread,
    time::{Duration, Instant},
};

use anyhow::{bail, Context, Result};
use serde::Deserialize;

use crate::{
    child::{self, Finished, OnInterrupt},
    env::Env,
    signals::{self, Cancelled},
    ui::Spinner,
};

/// The installed diapatch, which does everything that touches Dia's app bundles.
pub struct Diapatch(PathBuf);

/// `diapatch status --json`. Versions look like "1.55.1 (89833)".
#[derive(Deserialize)]
pub struct Status {
    pub official: Option<String>,
    pub installed: Option<String>,
    pub patched: bool,
    pub staged: Option<String>,
    pub feed: Option<String>,
    pub channel: String,
}

impl Diapatch {
    pub fn find(env: &Env) -> Result<Self> {
        let path = env.diapatch();
        if !path.is_file() {
            bail!(
                "DiaTweaks isn't installed: {} is missing. Run install.sh first.",
                path.display()
            );
        }
        Ok(Self(path))
    }

    pub fn run(
        &self,
        args: &[&str],
        on_interrupt: OnInterrupt,
        spinner: &Spinner,
    ) -> Result<Finished> {
        child::run(Command::new(&self.0).args(args), on_interrupt, spinner)
    }

    /// Also asks Dia's update feed, for up to 15 seconds.
    pub fn status(&self, spinner: &Spinner) -> Result<Status> {
        let done = self.run(&["status", "--json"], OnInterrupt::StopDownloads, spinner)?;
        if signals::interrupted() {
            bail!(Cancelled::nothing_changed());
        }
        let json = done.output.lines().rev().find(|line| line.starts_with('{'));
        match (done.status.success(), json) {
            (true, Some(json)) => serde_json::from_str(json)
                .context("diapatch status gave an answer diatweaks can't read"),
            _ => bail!("diapatch status failed:\n{}", done.tail(5)),
        }
    }
}

/// Compares the build numbers the way diapatch does.
pub fn is_newer(version: &str, than: &str) -> bool {
    numbers(build(version)) > numbers(build(than))
}

fn build(version: &str) -> &str {
    version
        .rsplit_once(" (")
        .and_then(|(_, build)| build.strip_suffix(')'))
        .unwrap_or(version)
}

fn numbers(text: &str) -> Vec<u64> {
    text.split(|c: char| !c.is_ascii_digit())
        .filter_map(|part| part.parse().ok())
        .collect()
}

/// "1.55.1 (89833)", like diapatch prints it.
pub fn version_of(app: &Path) -> Option<String> {
    let info = plist::Value::from_file(app.join("Contents/Info.plist")).ok()?;
    let info = info.as_dictionary()?;
    let short = info.get("CFBundleShortVersionString")?.as_string()?;
    let build = info.get("CFBundleVersion")?.as_string()?;
    Some(format!("{short} ({build})"))
}

pub fn is_patched(app: &Path) -> bool {
    plist::Value::from_file(app.join("Contents/Info.plist"))
        .ok()
        .and_then(|info| info.as_dictionary()?.get("DiaPatches")?.as_boolean())
        .unwrap_or(false)
}

/// 0 normally; 1 or 2 after Dia quit unexpectedly right after opening (see SafeMode.m).
pub fn safe_mode(support: &Path) -> i64 {
    plist::Value::from_file(support.join("safe-mode.plist"))
        .ok()
        .and_then(|state| state.as_dictionary()?.get("level")?.as_signed_integer())
        .unwrap_or(0)
}

/// Dia's processes, helpers included: everything running from inside the app bundle.
fn processes(app: &Path) -> Vec<(libc::pid_t, PathBuf)> {
    let Ok(root) = app.canonicalize() else {
        return Vec::new();
    };
    child::all_pids()
        .into_iter()
        .filter_map(|pid| child::pid_path(pid).map(|path| (pid, path)))
        .filter(|(_, path)| path.starts_with(&root))
        .collect()
}

pub fn is_running(app: &Path) -> bool {
    !processes(app).is_empty()
}

/// Quits Dia the way ⌘Q does, so it saves its windows, and waits for every Dia process to end.
/// Only the Dia at `app` is asked, by process ID, in case another copy is open.
pub fn quit(app: &Path) -> Result<()> {
    let macos = app.canonicalize()?.join("Contents/MacOS");
    for (pid, path) in processes(app) {
        if path.parent() != Some(macos.as_path()) {
            continue;
        }
        let script = format!(
            "ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationWithProcessIdentifier({pid}).terminate"
        );
        child::quick(Command::new("/usr/bin/osascript").args(["-l", "JavaScript", "-e", &script]));
    }
    let deadline = Instant::now() + Duration::from_secs(60);
    while is_running(app) {
        if Instant::now() > deadline {
            bail!(
                "Dia didn't quit. If it's showing a dialog, answer it, quit Dia, then try again."
            );
        }
        thread::sleep(Duration::from_millis(250));
    }
    Ok(())
}
