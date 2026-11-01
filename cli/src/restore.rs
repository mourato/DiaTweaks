use anyhow::{bail, Result};

use crate::{
    child::OnInterrupt,
    dia::{self, Diapatch},
    env::Env,
    lock,
    signals::Cancelled,
    ui::{self, Ui},
};

/// `diatweaks restore`: put the official Dia back, and with `purge` delete DiaTweaks' files too.
pub fn run(env: &Env, ui: &Ui, purge: bool) -> Result<()> {
    let diapatch = Diapatch::find(env)?;
    if !ui.interactive && !ui.yes {
        bail!("Restoring asks for confirmation. Run it in a terminal, or add --yes.");
    }
    let mut purge = purge;
    if !ui.yes {
        let restore = ui::prompt(
            cliclack::confirm(
                "Restore the original Dia? It goes back to updating itself, without tweaks.",
            )
            .initial_value(false)
            .interact(),
        )?;
        if !restore {
            return Err(Cancelled::nothing_changed().into());
        }
        if !purge {
            purge = ui::prompt(
                cliclack::confirm(
                    "Also delete DiaTweaks' files? You'd need install.sh to patch Dia again.",
                )
                .initial_value(false)
                .interact(),
            )?;
        }
        let what = match purge {
            true => "Dia quits, reopens as the original app, and DiaTweaks' files are deleted.",
            false => "Dia quits and reopens as the original app.",
        };
        let sure = ui::prompt(
            cliclack::confirm(format!("Are you sure? {what}"))
                .initial_value(false)
                .interact(),
        )?;
        if !sure {
            return Err(Cancelled::nothing_changed().into());
        }
    }
    let _lock = lock::acquire(&env.support)?;

    let spinner = ui.spinner("Restoring the original Dia");
    let was_running = dia::is_running(&env.app);
    if was_running {
        spinner.check(dia::quit(&env.app))?;
    }
    let mut args = vec!["uninstall"];
    if was_running {
        args.push("--relaunch");
    }
    if purge {
        args.push("--purge");
    }
    let done = spinner.check(diapatch.run(
        &args,
        OnInterrupt::Finish("Finishing so Dia isn't left half-restored…"),
        &spinner,
    ))?;
    if !done.status.success() {
        return Err(spinner.fail(anyhow::anyhow!("Couldn't restore Dia:\n{}", done.tail(5))));
    }
    let version = dia::version_of(&env.app).unwrap_or_default();
    spinner.stop(match was_running {
        true => format!("Restored the original Dia {version} and reopened it"),
        false => format!("Restored the original Dia {version}"),
    });
    ui.done(match purge {
        true => "DiaTweaks is removed. Your tweak settings stay in case you install it again.",
        false => "Dia is the original app again. Run `diatweaks update` to patch it again.",
    });
    Ok(())
}
