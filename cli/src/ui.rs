use std::{
    cell::Cell,
    fmt::Display,
    io::{self, IsTerminal, Write},
};

use anyhow::{Error, Result};
use cliclack::{Theme, ThemeState};

use crate::signals::{self, Cancelled};

/// Talks through cliclack in a terminal, and in plain lines for scripts. Output errors are ignored:
/// a closed pipe or terminal must not abort a step halfway.
pub struct Ui {
    pub interactive: bool,
    pub yes: bool,
    framed: Cell<bool>,
    in_menu: Cell<bool>,
}

impl Ui {
    pub fn new(yes: bool) -> Self {
        Self {
            interactive: io::stdin().is_terminal() && io::stderr().is_terminal(),
            yes,
            framed: Cell::new(false),
            in_menu: Cell::new(false),
        }
    }

    pub fn intro(&self) {
        self.framed.set(true);
        cliclack::set_theme(Frame);
        let _ = cliclack::intro(console::style(" DiaTweaks ").reverse());
    }

    pub fn enter_menu(&self, in_menu: bool) {
        self.in_menu.set(in_menu);
    }

    pub fn info(&self, message: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::log::info(message)),
            false => say(message),
        }
    }

    pub fn remark(&self, message: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::log::remark(message)),
            false => say(message),
        }
    }

    pub fn success(&self, message: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::log::success(message)),
            false => say(message),
        }
    }

    pub fn warn(&self, message: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::log::warning(message)),
            false => complain(format_args!("warning: {message}")),
        }
    }

    pub fn error(&self, err: &Error) {
        match self.framed.get() {
            true => drop(cliclack::log::error(format!("{err:#}"))),
            false => complain(format_args!("diatweaks: {err:#}")),
        }
    }

    pub fn note(&self, title: impl Display, body: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::note(title, body)),
            false => say(body),
        }
    }

    /// The last line of a finished command; inside the menu the session goes on.
    pub fn done(&self, message: impl Display) {
        match (self.framed.get(), self.in_menu.get()) {
            (true, true) => drop(cliclack::log::success(message)),
            (true, false) => drop(cliclack::outro(message)),
            (false, _) => say(message),
        }
    }

    pub fn cancelled(&self, cancelled: &Cancelled) {
        match self.framed.get() {
            true => drop(cliclack::outro_cancel(cancelled)),
            false => complain(cancelled),
        }
    }

    pub fn failed(&self, err: &Error) {
        match self.framed.get() {
            true => drop(cliclack::outro_cancel(format!("{err:#}"))),
            false => complain(format_args!("diatweaks: {err:#}")),
        }
    }

    pub fn spinner(&self, label: impl Display) -> Spinner {
        let label = label.to_string();
        let bar = self.framed.get().then(|| {
            let bar = cliclack::spinner();
            bar.start(&label);
            bar
        });
        Spinner { bar, label }
    }

    /// Asks before doing what the command is for. Scripts asked for it by running the command.
    pub fn proceed(&self, question: impl Display) -> Result<bool> {
        if self.yes || !self.interactive {
            return Ok(true);
        }
        prompt(cliclack::confirm(question).initial_value(true).interact())
    }

    /// Asks about something extra. Without a terminal the answer is no, unless --yes.
    pub fn choose(&self, question: impl Display, default: bool) -> Result<bool> {
        if self.yes {
            return Ok(true);
        }
        if !self.interactive {
            return Ok(false);
        }
        prompt(
            cliclack::confirm(question)
                .initial_value(default)
                .interact(),
        )
    }
}

/// cliclack closes a cancelled prompt with "└  Operation cancelled.", which would end the frame
/// before the menu goes on or diatweaks says what cancelling left behind.
struct Frame;

impl Theme for Frame {
    fn format_footer_with_message(&self, state: &ThemeState, message: &str) -> String {
        let line = match state {
            ThemeState::Active => format!("└  {message}"),
            ThemeState::Cancel | ThemeState::Submit => "│".into(),
            ThemeState::Error(err) => format!("└  {err}"),
        };
        format!("{}\n", self.bar_color(state).apply_to(line))
    }
}

/// A cancelled prompt, Esc and Ctrl-C alike, becomes `Cancelled`; so does any prompt a signal
/// interrupted, such as one whose terminal closed.
pub fn prompt<T>(result: io::Result<T>) -> Result<T> {
    let cancelled = match &result {
        Ok(_) => false,
        Err(err) => matches!(
            err.kind(),
            io::ErrorKind::Interrupted | io::ErrorKind::UnexpectedEof
        ),
    };
    if cancelled || signals::interrupted() {
        return Err(Cancelled::nothing_changed().into());
    }
    Ok(result?)
}

pub fn say(message: impl Display) {
    let _ = writeln!(io::stdout().lock(), "{message}");
}

fn complain(message: impl Display) {
    let _ = writeln!(io::stderr().lock(), "{message}");
}

/// A step in progress. Without a terminal it stays quiet until the step is done.
pub struct Spinner {
    bar: Option<cliclack::ProgressBar>,
    label: String,
}

impl Spinner {
    pub fn set_message(&self, message: impl Display) {
        if let Some(bar) = &self.bar {
            bar.set_message(message);
        }
    }

    pub fn stop(&self, message: impl Display) {
        match &self.bar {
            Some(bar) => bar.stop(message),
            None => say(message),
        }
    }

    /// Marks the step as failed or cancelled; the caller reports why.
    pub fn check<T>(&self, result: Result<T>) -> Result<T> {
        result.map_err(|err| self.fail(err))
    }

    pub fn fail(&self, err: Error) -> Error {
        if let Some(bar) = &self.bar {
            match err.is::<Cancelled>() {
                true => bar.cancel(&self.label),
                false => bar.error(&self.label),
            }
        }
        err
    }
}
