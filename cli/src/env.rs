use std::{env, ffi::OsString, path::PathBuf};

use anyhow::{Context, Result};

/// Where things live. The DIAPATCH_* variables are the ones diapatch reads; DIATWEAKS_DOMAIN
/// exists so tests can use their own settings domain.
pub struct Env {
    pub support: PathBuf,
    pub app: PathBuf,
    pub domain: String,
}

impl Env {
    pub fn load() -> Result<Self> {
        let home = var_os("HOME")
            .map(PathBuf::from)
            .context("HOME isn't set")?;
        Ok(Self {
            support: var_os("DIAPATCH_HOME").map_or_else(
                || home.join("Library/Application Support/DiaPatches"),
                PathBuf::from,
            ),
            app: var_os("DIAPATCH_APP")
                .map_or_else(|| PathBuf::from("/Applications/Dia.app"), PathBuf::from),
            domain: var("DIATWEAKS_DOMAIN").unwrap_or_else(|| "com.diapatches".into()),
        })
    }

    pub fn diapatch(&self) -> PathBuf {
        self.support.join("bin/diapatch")
    }

    pub fn manifest(&self) -> PathBuf {
        self.support.join("patches.json")
    }

    pub fn staged(&self) -> PathBuf {
        self.support.join("staged/Dia.app")
    }
}

fn var_os(name: &str) -> Option<OsString> {
    env::var_os(name).filter(|value| !value.is_empty())
}

fn var(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}
