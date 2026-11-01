use std::{
    fs::{File, OpenOptions},
    io,
    os::fd::AsRawFd,
    path::Path,
};

use anyhow::{bail, Context, Result};

/// One changing run at a time. The kernel drops the lock when the process ends, however it ends.
pub struct Lock {
    _file: File,
}

pub fn acquire(support: &Path) -> Result<Lock> {
    let path = support.join(".diatweaks.lock");
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(&path)
        .with_context(|| format!("Couldn't open {}", path.display()))?;
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        let err = io::Error::last_os_error();
        if err.kind() == io::ErrorKind::WouldBlock {
            bail!("Another diatweaks is running. Wait for it to finish, then try again.");
        }
        return Err(err).with_context(|| format!("Couldn't lock {}", path.display()));
    }
    Ok(Lock { _file: file })
}
