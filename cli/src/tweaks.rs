use anyhow::Result;

use crate::{
    dia,
    env::Env,
    lock,
    manifest::Manifest,
    prefs::Prefs,
    signals::Cancelled,
    ui::{self, Ui},
};

pub fn list(env: &Env) -> Result<()> {
    let manifest = Manifest::load(&env.manifest())?;
    let state = manifest.state(&Prefs::new(&env.domain));
    let width = manifest
        .patches
        .iter()
        .map(|patch| patch.key.len())
        .max()
        .unwrap_or(0);
    for (patch, on) in manifest.patches.iter().zip(state) {
        ui::say(format_args!(
            "{:<4} {:<width$}  {}",
            on_off(on),
            patch.key,
            patch.title
        ));
    }
    Ok(())
}

/// `diatweaks enable` and `disable`.
pub fn set(env: &Env, ui: &Ui, names: &[String], on: bool) -> Result<()> {
    let manifest = Manifest::load(&env.manifest())?;
    let targets = manifest.resolve(names)?;
    let current = manifest.state(&Prefs::new(&env.domain));
    let mut wanted = current.clone();
    for &index in &targets {
        if current[index] == on {
            ui.info(format_args!(
                "{} is already {}.",
                manifest.title(index),
                on_off(on)
            ));
        }
        wanted[index] = on;
    }
    add_requirements(ui, &manifest, &current, &mut wanted)?;
    let changes = save(env, &manifest, &current, &wanted)?;
    if changes.is_empty() {
        ui.done("Nothing to change.");
        return Ok(());
    }
    for &index in &changes {
        ui.success(format_args!(
            "Turned {} {}.",
            on_off(wanted[index]),
            manifest.title(index)
        ));
    }
    for note in notes(&manifest, &current, &wanted) {
        ui.warn(note);
    }
    ui.done(where_it_shows(env));
    Ok(())
}

/// The Tweaks screen of the menu.
pub fn menu(env: &Env, ui: &Ui) -> Result<()> {
    let manifest = Manifest::load(&env.manifest())?;
    let current = manifest.state(&Prefs::new(&env.domain));
    let mut prompt = cliclack::multiselect("Turn tweaks on or off (space toggles, enter saves)")
        .required(false)
        .initial_values((0..current.len()).filter(|&index| current[index]).collect());
    for (index, patch) in manifest.patches.iter().enumerate() {
        prompt = prompt.item(index, &patch.title, hint(&manifest, &current, index));
    }
    let selected = ui::prompt(prompt.interact())?;
    let mut wanted = vec![false; current.len()];
    for index in selected {
        wanted[index] = true;
    }
    add_requirements(ui, &manifest, &current, &mut wanted)?;

    let summary: Vec<String> = (0..wanted.len())
        .filter(|&index| wanted[index] != current[index])
        .map(|index| {
            let verb = if wanted[index] {
                "Turn on "
            } else {
                "Turn off"
            };
            format!("{verb}  {}", manifest.title(index))
        })
        .collect();
    if summary.is_empty() {
        ui.done("Nothing changed.");
        return Ok(());
    }
    ui.note("Changes", summary.join("\n"));
    for note in notes(&manifest, &current, &wanted) {
        ui.warn(note);
    }
    if !ui.choose("Save these changes?", true)? {
        return Err(Cancelled::nothing_changed().into());
    }
    save(env, &manifest, &current, &wanted)?;
    ui.done(format_args!("Saved. {}", where_it_shows(env)));
    Ok(())
}

fn hint(manifest: &Manifest, current: &[bool], index: usize) -> String {
    let mut hint = manifest.patches[index].detail.clone();
    if let Some(required) = manifest.requirement(index) {
        hint.push_str(&format!(" Needs {}.", manifest.title(required)));
    }
    if let Some(disabler) = manifest
        .disabler(index)
        .filter(|&disabler| current[disabler])
    {
        hint.push_str(&format!(
            " No difference while {} is on.",
            manifest.title(disabler)
        ));
    }
    hint
}

/// Turning on a patch that needs another one offers to turn that on too.
fn add_requirements(
    ui: &Ui,
    manifest: &Manifest,
    current: &[bool],
    wanted: &mut [bool],
) -> Result<()> {
    for index in 0..wanted.len() {
        if !wanted[index] || current[index] {
            continue;
        }
        let mut needer = index;
        while let Some(required) = manifest.requirement(needer) {
            if wanted[required] {
                break;
            }
            let question = format!(
                "{} needs {}, which is off. Turn that on too?",
                manifest.title(needer),
                manifest.title(required)
            );
            if !ui.choose(question, true)? {
                break;
            }
            wanted[required] = true;
            needer = required;
        }
    }
    Ok(())
}

/// What won't show the way the user might expect, for the patches this run touches.
fn notes(manifest: &Manifest, current: &[bool], wanted: &[bool]) -> Vec<String> {
    let changed = |index: usize| current[index] != wanted[index];
    let mut notes = Vec::new();
    for index in 0..wanted.len() {
        if let Some(required) = manifest.requirement(index) {
            if wanted[index] && !wanted[required] && (changed(index) || changed(required)) {
                notes.push(format!(
                    "{} does nothing while {} is off.",
                    manifest.title(index),
                    manifest.title(required)
                ));
            }
        }
        if let Some(disabler) = manifest.disabler(index) {
            if changed(index) && wanted[disabler] {
                notes.push(format!(
                    "{} makes no difference while {} is on.",
                    manifest.title(index),
                    manifest.title(disabler)
                ));
            }
        }
    }
    notes
}

/// Saves the patches whose wanted state differs from what this run started from, and leaves the
/// rest alone in case something else changed them meanwhile. Returns what it changed.
fn save(env: &Env, manifest: &Manifest, current: &[bool], wanted: &[bool]) -> Result<Vec<usize>> {
    let changes: Vec<usize> = (0..wanted.len())
        .filter(|&index| current[index] != wanted[index])
        .collect();
    if changes.is_empty() {
        return Ok(changes);
    }
    let _lock = lock::acquire(&env.support)?;
    let prefs = Prefs::new(&env.domain);
    for &index in &changes {
        prefs.set(&manifest.patches[index].key, wanted[index]);
    }
    prefs.save()?;
    Ok(changes)
}

fn where_it_shows(env: &Env) -> String {
    if dia::safe_mode(&env.support) > 0 {
        return "Tweaks are paused because Dia quit unexpectedly right after opening. Turn them back on in Dia → Settings → Patches.".into();
    }
    if !dia::is_patched(&env.app) {
        return "Dia isn't patched right now, so they won't show. Run `diatweaks update` to patch it again.".into();
    }
    if dia::is_running(&env.app) {
        return "Dia shows the changes now.".into();
    }
    "Dia uses them the next time it opens.".into()
}

fn on_off(on: bool) -> &'static str {
    if on {
        "on"
    } else {
        "off"
    }
}
