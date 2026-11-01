use anyhow::Result;

use crate::{
    dia::{self, Diapatch},
    env::Env,
    manifest::Manifest,
    prefs::Prefs,
    ui::{self, Spinner, Ui},
};

pub const COMMIT: &str = env!("DIATWEAKS_COMMIT");

/// `diatweaks status`: plain lines for reading or grepping.
pub fn print(env: &Env, ui: &Ui) -> Result<()> {
    let lines = report(env, &ui.spinner(""))?;
    ui::say(lines.join("\n"));
    Ok(())
}

/// The Status screen of the menu.
pub fn show(env: &Env, ui: &Ui) -> Result<()> {
    let spinner = ui.spinner("Checking Dia");
    let lines = spinner.check(report(env, &spinner))?;
    spinner.stop("Checked Dia");
    ui.note("Status", lines.join("\n"));
    Ok(())
}

fn report(env: &Env, spinner: &Spinner) -> Result<Vec<String>> {
    let manifest = Manifest::load(&env.manifest())?;
    let status = Diapatch::find(env)?.status(spinner)?;
    let none = || "none".to_string();

    let installed = match &status.installed {
        Some(version) if status.patched => format!("{version}, patched"),
        Some(version) => format!("{version}, not patched"),
        None => format!("not installed at {}", env.app.display()),
    };
    let staged = status.staged.as_ref().map_or_else(none, |version| {
        format!("{version}, installs when Dia quits")
    });
    let latest = match &status.feed {
        Some(version) => format!("{version} on the {} channel", status.channel),
        None => "couldn't check (are you online?)".into(),
    };
    let safe_mode = match dia::safe_mode(&env.support) {
        0 => "off",
        1 => "on: tweaks are off because Dia quit unexpectedly right after opening",
        _ => "on: DiaTweaks is off because Dia kept quitting right after opening",
    };
    let mut lines = vec![
        format!("Dia        {installed}"),
        format!("Official   {}", status.official.unwrap_or_else(none)),
        format!("Staged     {staged}"),
        format!("Latest     {latest}"),
        format!("Safe mode  {safe_mode}"),
        format!("DiaTweaks  {}", short(COMMIT)),
        "Tweaks".into(),
    ];

    let state = manifest.state(&Prefs::new(&env.domain));
    for (index, patch) in manifest.patches.iter().enumerate() {
        let mut line = format!(
            "  {:<4} {}",
            if state[index] { "on" } else { "off" },
            patch.title
        );
        let unmet = manifest
            .requirement(index)
            .filter(|&required| state[index] && !state[required]);
        if let Some(required) = unmet {
            line.push_str(&format!(
                " (does nothing while {} is off)",
                manifest.title(required)
            ));
        }
        if let Some(disabler) = manifest.disabler(index).filter(|&disabler| state[disabler]) {
            line.push_str(&format!(
                " (no difference while {} is on)",
                manifest.title(disabler)
            ));
        }
        lines.push(line);
    }
    Ok(lines)
}

pub fn short(commit: &str) -> &str {
    commit.get(..7).unwrap_or(commit)
}
