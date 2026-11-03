use std::{fs, io, path::Path};

use anyhow::{anyhow, bail, Context, Result};
use serde::Deserialize;

use crate::prefs::Prefs;

/// patches.json, written by `make` from the dylib's own list of patches, in Settings order.
#[derive(Deserialize)]
pub struct Manifest {
    version: u32,
    pub patches: Vec<Patch>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Patch {
    pub key: String,
    pub title: String,
    pub detail: String,
    pub default_on: bool,
    /// Does nothing unless this patch is on.
    pub requires: Option<String>,
    /// Makes no difference while this patch is on.
    pub disabled_by: Option<String>,
}

impl Manifest {
    pub fn load(path: &Path) -> Result<Self> {
        let data = match fs::read(path) {
            Ok(data) => data,
            Err(err) if err.kind() == io::ErrorKind::NotFound => bail!(
                "DiaTweaks isn't installed: {} is missing. Run install.sh first.",
                path.display()
            ),
            Err(err) => {
                return Err(err).with_context(|| format!("Couldn't read {}", path.display()))
            }
        };
        let manifest: Self = serde_json::from_slice(&data).map_err(|err| {
            anyhow!(
                "{} is damaged ({err}). Run install.sh again.",
                path.display()
            )
        })?;
        if manifest.version != 1 {
            bail!(
                "{} is format {}, which this diatweaks can't read. Run install.sh again.",
                path.display(),
                manifest.version
            );
        }
        if manifest.patches.is_empty() {
            bail!("{} lists no tweaks. Run install.sh again.", path.display());
        }
        let links = manifest
            .patches
            .iter()
            .flat_map(|patch| [&patch.requires, &patch.disabled_by])
            .flatten();
        for key in links {
            if manifest.index(key).is_none() {
                bail!(
                    "{} names a tweak it doesn't list: {key}. Run install.sh again.",
                    path.display()
                );
            }
        }
        Ok(manifest)
    }

    pub fn index(&self, key: &str) -> Option<usize> {
        self.patches.iter().position(|patch| patch.key == key)
    }

    pub fn requirement(&self, index: usize) -> Option<usize> {
        self.patches[index]
            .requires
            .as_deref()
            .and_then(|key| self.index(key))
    }

    pub fn disabler(&self, index: usize) -> Option<usize> {
        self.patches[index]
            .disabled_by
            .as_deref()
            .and_then(|key| self.index(key))
    }

    pub fn hidden_by(&self, index: usize, state: &[bool]) -> Option<usize> {
        let disabler = self.disabler(index).filter(|&disabler| state[disabler])?;
        let option_on = (0..self.patches.len())
            .any(|option| state[option] && self.requirement(option) == Some(disabler));
        (!option_on).then_some(disabler)
    }

    pub fn title(&self, index: usize) -> &str {
        &self.patches[index].title
    }

    /// Whether each patch is on, in manifest order.
    pub fn state(&self, prefs: &Prefs) -> Vec<bool> {
        self.patches
            .iter()
            .map(|patch| prefs.get(&patch.key).unwrap_or(patch.default_on))
            .collect()
    }

    /// Finds tweaks by key or title, ignoring case, spaces and dashes. Every name has to match.
    pub fn resolve(&self, names: &[String]) -> Result<Vec<usize>> {
        let mut found = Vec::new();
        let mut unknown = Vec::new();
        for name in names {
            let wanted = normalize(name);
            let index = self.patches.iter().position(|patch| {
                normalize(&patch.key) == wanted || normalize(&patch.title) == wanted
            });
            match index {
                Some(index) if !found.contains(&index) => found.push(index),
                Some(_) => {}
                None => unknown.push(self.suggest(name, &wanted)),
            }
        }
        if !unknown.is_empty() {
            bail!("{}", unknown.join("\n"));
        }
        Ok(found)
    }

    fn suggest(&self, name: &str, wanted: &str) -> String {
        let close: Vec<&str> = self
            .patches
            .iter()
            .filter(|patch| is_close(wanted, &patch.key) || is_close(wanted, &patch.title))
            .map(|patch| patch.key.as_str())
            .collect();
        match close.as_slice() {
            [] => format!("There's no tweak called \"{name}\". Run `diatweaks list` to see them."),
            [one] => format!("There's no tweak called \"{name}\". Did you mean {one}?"),
            many => format!(
                "There's no tweak called \"{name}\". Did you mean one of {}?",
                many.join(", ")
            ),
        }
    }
}

fn normalize(name: &str) -> String {
    name.chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_lowercase())
        .collect()
}

fn is_close(wanted: &str, candidate: &str) -> bool {
    let candidate = normalize(candidate);
    (wanted.len() >= 3 && candidate.contains(wanted))
        || strsim::normalized_damerau_levenshtein(wanted, &candidate) >= 0.7
}
