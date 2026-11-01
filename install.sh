#!/bin/sh
# Builds DiaTweaks and installs it. --yes never asks anything.
set -eu
cd "$(dirname "$0")"
case "${1-}" in
    --yes) yes=1 ;;
    '') yes= ;;
    *) echo "usage: ./install.sh [--yes]" >&2; exit 2 ;;
esac
support="${DIAPATCH_HOME:-$HOME/Library/Application Support/DiaPatches}"
incoming="$support/.incoming"
trap 'rm -rf "$incoming"' EXIT
trap 'exit 130' INT TERM

make -s

cli=
if [ -f cli/Cargo.toml ]; then
    # Where rustup puts cargo, which isn't on PATH until a new shell starts.
    PATH="$PATH:${CARGO_HOME:-$HOME/.cargo}/bin"
    if ! command -v cargo >/dev/null && [ -z "$yes" ] && [ -t 0 ]; then
        printf 'The diatweaks command needs Rust. Install it with rustup? [y/N] '
        read -r answer || answer=
        case $answer in [yY]*) curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal ;; esac
    fi
    if ! command -v cargo >/dev/null; then
        echo "Skipping the diatweaks command: it needs Rust (https://rustup.rs)."
    elif cargo build --release --manifest-path cli/Cargo.toml; then
        cli="${CARGO_TARGET_DIR:-cli/target}/release/diatweaks"
    else
        echo "Skipping the diatweaks command: it didn't build."
    fi
fi

rm -rf "$incoming"
mkdir -p "$incoming" "$support/bin"
cp build/diapatch build/DiaPatches.dylib build/patches.json ${cli:+"$cli"} "$incoming/"
# Each rename is atomic, and Ctrl-C waits until all are done, so the installed files always come from one build.
trap 'interrupted=1' INT TERM
(
    trap '' INT TERM
    mv -f "$incoming/diapatch" ${cli:+"$incoming/diatweaks"} "$support/bin/"
    mv -f "$incoming/DiaPatches.dylib" "$incoming/patches.json" "$support/"
)
[ -z "${interrupted-}" ] || exit 130
trap 'exit 130' INT TERM

if [ -n "$cli" ]; then
    if [ -n "${DIATWEAKS_LINK_DIR-}" ]; then dir=$DIATWEAKS_LINK_DIR
    elif [ -w /opt/homebrew/bin ]; then dir=/opt/homebrew/bin
    elif [ -w /usr/local/bin ]; then dir=/usr/local/bin
    else dir="$HOME/.local/bin"
    fi
    link="$dir/diatweaks"
    case $(readlink "$link") in
        "$support"/*) ;;
        *) if [ -L "$link" ] || [ -e "$link" ]; then echo "Left $link alone: it isn't DiaTweaks'."; link=; fi ;;
    esac
    if [ -n "$link" ]; then
        mkdir -p "$dir"
        ln -sfh "$support/bin/diatweaks" "$link"
        case ":$PATH:" in *":$dir:"*) ;; *) echo "Add $dir to your PATH to run diatweaks." ;; esac
    fi
fi

"$support/bin/diapatch" install --relaunch
