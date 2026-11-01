use anyhow::{bail, Result};

use crate::{
    child::OnInterrupt,
    dia::{self, Diapatch},
    env::Env,
    lock,
    signals::{self, Cancelled},
    ui::Ui,
};

const FINISHING: &str = "Finishing so Dia isn't left half-installed…";

/// `diatweaks update-dia`: download and patch a newer Dia, then install it now or when Dia quits.
pub fn run(env: &Env, ui: &Ui) -> Result<()> {
    let diapatch = Diapatch::find(env)?;
    if !env.app.exists() {
        bail!(
            "Dia isn't installed at {}. Get it from https://www.diabrowser.com, then run install.sh.",
            env.app.display()
        );
    }
    let _lock = lock::acquire(&env.support)?;

    let spinner = ui.spinner("Checking for a newer Dia");
    let status = spinner.check(diapatch.status(&spinner))?;
    let ready = match status.staged {
        Some(staged) => {
            spinner.stop(format_args!("Dia {staged} is downloaded and ready"));
            staged
        }
        None => {
            let Some(official) = status.official else {
                return Err(spinner.fail(anyhow::anyhow!(
                    "DiaTweaks has no copy of the official Dia. Run install.sh to set it up again."
                )));
            };
            let Some(latest) = status.feed else {
                return Err(spinner.fail(anyhow::anyhow!(
                    "Couldn't reach Dia's update feed. Check your internet connection, then try again."
                )));
            };
            if !dia::is_newer(&latest, &official) {
                spinner.stop(format_args!("Dia {official} is up to date"));
                if !status.patched {
                    ui.warn(
                        "Dia isn't patched right now. Run `diatweaks update` to patch it again.",
                    );
                }
                ui.done("Nothing to update.");
                return Ok(());
            }
            spinner.stop(format_args!("Dia {latest} is out (you have {official})"));
            if !ui.proceed(format_args!("Download Dia {latest} and patch it?"))? {
                return Err(Cancelled::nothing_changed().into());
            }
            download(env, ui, &diapatch, &latest)?
        }
    };
    install(env, ui, &diapatch, &ready)
}

fn download(env: &Env, ui: &Ui, diapatch: &Diapatch, latest: &str) -> Result<String> {
    let spinner = ui.spinner(format_args!(
        "Downloading and patching Dia {latest}. This can take a few minutes"
    ));
    let done = spinner.check(diapatch.run(&["update"], OnInterrupt::StopDownloads, &spinner))?;
    let staged = dia::version_of(&env.staged());
    match (staged, signals::interrupted()) {
        (Some(staged), true) => Err(spinner.fail(
            Cancelled(format!(
                "Stopped after Dia {staged} was ready. It installs the next time you quit Dia."
            ))
            .into(),
        )),
        (None, true) => Err(spinner.fail(Cancelled::nothing_changed().into())),
        (Some(staged), false) => {
            spinner.stop(format_args!("Dia {staged} is ready"));
            Ok(staged)
        }
        (None, false) => {
            Err(spinner.fail(anyhow::anyhow!("Couldn't update Dia:\n{}", done.tail(5))))
        }
    }
}

fn install(env: &Env, ui: &Ui, diapatch: &Diapatch, ready: &str) -> Result<()> {
    if signals::interrupted() {
        bail!(Cancelled(format!(
            "Stopped before installing. Dia {ready} installs the next time you quit Dia, or run `diatweaks update-dia`."
        )));
    }
    if !dia::is_running(&env.app) {
        let spinner = ui.spinner(format_args!("Installing Dia {ready}"));
        let done =
            spinner.check(diapatch.run(&["apply"], OnInterrupt::Finish(FINISHING), &spinner))?;
        if !done.status.success() {
            return Err(spinner.fail(anyhow::anyhow!("Couldn't install Dia:\n{}", done.tail(5))));
        }
        spinner.stop(format_args!("Installed Dia {ready}"));
        ui.done(format_args!("Dia {ready} is installed."));
        return Ok(());
    }
    if !ui.choose("Relaunch Dia now to install it?", true)? {
        match dia::is_patched(&env.app) {
            true => ui.done(format_args!(
                "Dia {ready} installs the next time you quit Dia."
            )),
            false => ui.done(format_args!(
                "Quit Dia, then run `diatweaks update-dia` to install Dia {ready}."
            )),
        }
        return Ok(());
    }
    let spinner = ui.spinner(format_args!("Relaunching Dia to install {ready}"));
    spinner.check(dia::quit(&env.app))?;
    let done = spinner.check(diapatch.run(
        &["apply", "--relaunch"],
        OnInterrupt::Finish(FINISHING),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(anyhow::anyhow!("Couldn't install Dia:\n{}", done.tail(5))));
    }
    spinner.stop(format_args!("Installed Dia {ready} and reopened it"));
    ui.done(format_args!("Dia {ready} is installed."));
    Ok(())
}
