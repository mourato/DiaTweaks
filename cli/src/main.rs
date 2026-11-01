mod child;
mod dia;
mod env;
mod lock;
mod manifest;
mod menu;
mod prefs;
mod restore;
mod signals;
mod status;
mod tweaks;
mod ui;
mod update;
mod update_dia;

use std::{io, process::ExitCode};

use anyhow::{bail, Result};
use clap::{CommandFactory, Parser, Subcommand};

use crate::{env::Env, signals::Cancelled, ui::Ui};

/// Turn Dia tweaks on and off, and keep Dia and DiaTweaks up to date.
///
/// Run it without a command in a terminal for a menu.
#[derive(Parser)]
#[command(name = "diatweaks", version = concat!(env!("CARGO_PKG_VERSION"), " (", env!("DIATWEAKS_COMMIT"), ")"))]
struct Cli {
    /// Answer yes to every question
    #[arg(short, long, global = true)]
    yes: bool,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// List the tweaks and whether each is on
    List,
    /// Turn tweaks on, by key or title
    Enable {
        #[arg(required = true, value_name = "TWEAK")]
        tweaks: Vec<String>,
    },
    /// Turn tweaks off, by key or title
    Disable {
        #[arg(required = true, value_name = "TWEAK")]
        tweaks: Vec<String>,
    },
    /// Show Dia's versions, safe mode and which tweaks are on
    Status,
    /// Install the latest DiaTweaks release, then patch Dia again
    Update,
    /// Download and patch a newer Dia
    UpdateDia,
    /// Put the original Dia back
    Restore {
        /// Also delete DiaTweaks' files
        #[arg(long)]
        purge: bool,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    // The menu always asks: --yes is for scripted commands.
    let ui = Ui::new(cli.yes && cli.command.is_some());
    if cli.command.is_none() && !ui.interactive {
        let _ = Cli::command().write_help(&mut io::stderr());
        return ExitCode::from(2);
    }
    if !matches!(cli.command, Some(Command::List | Command::Status) | None) && ui.interactive {
        ui.intro();
    }
    match run(cli.command, &ui) {
        Ok(()) if signals::interrupted() => ExitCode::from(130),
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => match err.downcast_ref::<Cancelled>() {
            Some(cancelled) => {
                ui.cancelled(cancelled);
                ExitCode::from(130)
            }
            None => {
                ui.failed(&err);
                ExitCode::FAILURE
            }
        },
    }
}

fn run(command: Option<Command>, ui: &Ui) -> Result<()> {
    if unsafe { libc::geteuid() } == 0 {
        bail!("Don't run diatweaks with sudo or as root. It manages your own Dia and settings.");
    }
    signals::install()?;
    let env = Env::load()?;
    let Some(command) = command else {
        return menu::run(&env, ui);
    };
    match command {
        Command::List => tweaks::list(&env),
        Command::Enable { tweaks } => tweaks::set(&env, ui, &tweaks, true),
        Command::Disable { tweaks } => tweaks::set(&env, ui, &tweaks, false),
        Command::Status => status::print(&env, ui),
        Command::Update => update::run(&env, ui),
        Command::UpdateDia => update_dia::run(&env, ui),
        Command::Restore { purge } => restore::run(&env, ui, purge),
    }
}
