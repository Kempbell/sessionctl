#!/bin/sh
# install.sh: link `sessions` (and its second name `sessionctl`) into ~/.local/bin, then
# run `sessions init`, which writes the config from the Claude Code accounts this machine
# has. Arguments go to init: ./install.sh --dry-run prints the plan, --yes skips the questions.
# SESSIONCTL_BIN_DIR=<dir> links somewhere else.
set -eu

repo=$(cd "$(dirname "$0")" && pwd -P)
bin=${SESSIONCTL_BIN_DIR:-$HOME/.local/bin}

# Python 3.11 or newer (tomllib), checked before anything is linked.
if ! command -v python3 >/dev/null 2>&1; then
  echo "install.sh: python3 not found; sessions needs Python 3.11 or newer" >&2
  exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
  echo "install.sh: $(python3 --version 2>&1) is too old; sessions needs Python 3.11 or newer" >&2
  exit 1
fi

# Symlinks only: a real file of either name stops the install before anything is linked.
for name in sessions sessionctl; do
  if [ -e "$bin/$name" ] && [ ! -L "$bin/$name" ]; then
    echo "install.sh: $bin/$name exists and is not a symlink; move it aside and run again" >&2
    exit 1
  fi
done
mkdir -p "$bin"
for name in sessions sessionctl; do
  ln -sfn "$repo/bin/sessions" "$bin/$name"
  echo "linked $bin/$name -> $repo/bin/sessions"
done

case ":$PATH:" in
  *":$bin:"*) ;;
  *) echo "note: $bin is not on PATH; add it in your shell rc to run sessions by name" >&2 ;;
esac

exec "$bin/sessions" init "$@"
