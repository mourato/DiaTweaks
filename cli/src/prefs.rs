use std::ffi::{c_char, CString};

use anyhow::{bail, Result};
use core_foundation::{
    base::{CFType, TCFType},
    boolean::CFBoolean,
    number::CFNumber,
    string::CFString,
};
use core_foundation_sys::preferences::{
    CFPreferencesAppSynchronize, CFPreferencesCopyAppValue, CFPreferencesSetAppValue,
};

extern "C" {
    fn notify_post(name: *const c_char) -> u32;
}

/// The settings domain Dia's Patches pane uses: one bool per patch key.
pub struct Prefs {
    name: String,
    domain: CFString,
}

impl Prefs {
    pub fn new(domain: &str) -> Self {
        Self {
            name: domain.to_string(),
            domain: CFString::new(domain),
        }
    }

    /// `None` when unset, so the patch's default applies.
    pub fn get(&self, key: &str) -> Option<bool> {
        let key = CFString::new(key);
        let value = unsafe {
            CFPreferencesCopyAppValue(key.as_concrete_TypeRef(), self.domain.as_concrete_TypeRef())
        };
        if value.is_null() {
            return None;
        }
        let value = unsafe { CFType::wrap_under_create_rule(value) };
        if let Some(flag) = value.downcast::<CFBoolean>() {
            return Some(flag.into());
        }
        if let Some(number) = value.downcast::<CFNumber>() {
            return number.to_f64().map(|number| number != 0.0);
        }
        value
            .downcast::<CFString>()
            .map(|text| string_is_true(&text.to_string()))
    }

    pub fn set(&self, key: &str, on: bool) {
        let key = CFString::new(key);
        let value = CFBoolean::from(on);
        unsafe {
            CFPreferencesSetAppValue(
                key.as_concrete_TypeRef(),
                value.as_CFTypeRef(),
                self.domain.as_concrete_TypeRef(),
            );
        }
    }

    /// Writes the changes out and tells a running Dia to apply them.
    pub fn save(&self) -> Result<()> {
        if unsafe { CFPreferencesAppSynchronize(self.domain.as_concrete_TypeRef()) } == 0 {
            bail!("Couldn't save the settings in {}.", self.name);
        }
        let notification = CString::new(format!("{}.changed", self.name))?;
        let status = unsafe { notify_post(notification.as_ptr()) };
        if status != 0 {
            bail!("Saved, but couldn't tell Dia (notify_post returned {status}). Restart Dia to see the changes.");
        }
        Ok(())
    }
}

/// How NSString's boolValue, and so Dia, reads `defaults write com.diapatches key YES`.
fn string_is_true(text: &str) -> bool {
    let number = text
        .trim_start()
        .trim_start_matches(['+', '-'])
        .trim_start_matches('0');
    matches!(
        number.chars().next(),
        Some('Y' | 'y' | 'T' | 't' | '1'..='9')
    )
}
