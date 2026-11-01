use anyhow::{bail, Result};

use crate::{child::OnInterrupt, dia::Diapatch, env::Env, lock, signals::Cancelled, ui::Ui};

const FINISHING: &str = "Finishing the install so Dia isn't left half-patched…";

/// `diatweaks update`: install the latest release, then patch Dia again even if nothing was new,
/// which also repairs an install.
pub fn run(env: &Env, ui: &Ui) -> Result<()> {
    let diapatch = Diapatch::find(env)?;
    if !env.app.exists() {
        bail!(
            "Dia isn't installed at {}. Get it from https://www.diabrowser.com first.",
            env.app.display()
        );
    }
    let _lock = lock::acquire(&env.support)?;
    if !ui.proceed("Update DiaTweaks? It installs the latest release, then reopens Dia.")? {
        return Err(Cancelled::nothing_changed().into());
    }

    let spinner = ui.spinner("Downloading the latest DiaTweaks");
    let done = spinner.check(diapatch.run(&["self-update"], OnInterrupt::Stop, &spinner))?;
    if !done.status.success() {
        return Err(spinner.fail(anyhow::anyhow!(
            "Couldn't update DiaTweaks. Check your internet connection, then try again.\n{}",
            done.tail(3)
        )));
    }
    let done = spinner.check(diapatch.run(
        &["apply", "--tweaks"],
        OnInterrupt::Finish(FINISHING),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(anyhow::anyhow!(
            "Couldn't install DiaTweaks:\n{}",
            done.tail(3)
        )));
    }
    spinner.stop(
        done.output
            .trim()
            .lines()
            .last()
            .unwrap_or("DiaTweaks is up to date"),
    );

    let spinner = ui.spinner("Patching Dia and reopening it");
    let done = spinner.check(diapatch.run(
        &["install", "--relaunch"],
        OnInterrupt::Finish(FINISHING),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(anyhow::anyhow!("Couldn't patch Dia:\n{}", done.tail(12))));
    }
    spinner.stop("Patched Dia");
    ui.done("DiaTweaks is up to date.");
    Ok(())
}
