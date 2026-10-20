# Config format

The `sessions` CLI reads one TOML file. This page is the standard for it.

## Location

- Default: `~/.config/claude-sessions/config.toml`.
- `SESSIONS_CONFIG=<path>` reads another file instead (`~` and `$VAR` are expanded).
- If the file does not exist, every command except `init` and `--help` stops with a message that points at `sessions init`, here and `examples/config.toml`. There is no built-in fallback.

`sessions init` writes this file from what your machine has: a profile for each Claude Code config dir it finds, the launcher your shell rc defines for each one, and the terminal it detects. The profile for `~/.claude` is named `default` and gets `registry = "registry.toml"` and `charters = "charters"`; every other profile gets `registry-<name>.toml` and `charters-<name>`, relative to the config file's directory. It prints the file before writing it and never replaces an existing one unless you pass `--force`, which first renames the old one to `config.toml.<YYYYmmdd-HHMMSS>.bak`.

Keep the file private (`chmod 600`, which is how `init` writes it). It holds no secrets itself, but it names where they are.

## Example

```toml
default_profile = "personal"

[profiles.personal]
config_dir = "~/.claude-personal"
registry = "~/.config/claude-sessions/registry.toml"
charters = "~/.config/claude-sessions/charters"
launcher = "claude-personal"
secrets_mount = "~/.secrets/claude-personal.env"

[profiles.work]
config_dir = "~/.claude-work"
registry = "~/.config/claude-sessions/registry-work.toml"
charters = "~/.config/claude-sessions/charters-work"
launcher = "claude-work"

[terminal]
command = "ptyxis --tab -- zsh -ic '{cmd}; exec zsh'"
```

## Top level

| key | required | meaning |
|---|---|---|
| `default_profile` | no | The profile used when neither `--profile` nor `SESSIONS_PROFILE` names one. Must be one of the `[profiles.*]` tables. Absent: the first profile in the file. Hints in the output spell `sessions` for this profile and `sessions --profile <name>` for the others. |

## `[profiles.<name>]`

One table per Claude Code account, that is per `CLAUDE_CONFIG_DIR`. `<name>` is what `--profile` takes. At least one profile is required. All values are strings.

| key | required | meaning |
|---|---|---|
| `config_dir` | yes | The account's `CLAUDE_CONFIG_DIR`. Discovery only looks at processes whose `CLAUDE_CONFIG_DIR` resolves to this directory, and launches set it. |
| `registry` | yes | The profile's registry file (format below). Created on the first write. |
| `charters` | yes | Directory that `sessions new --charter` copies charters into, as `<Name>.md`. |
| `launcher` | yes | The shell function, alias or command that runs `claude` for this account. It is used in the commands an interactive tab runs and in every printed relaunch hint. See Launcher. |
| `secrets_mount` | no | Path of a FIFO holding `KEY=value` lines (for example a secrets manager's mounted env file) that the launcher sources before starting `claude`. bg launches and `send` source it the same way, bounded to 5 seconds so a locked secrets manager cannot hang them. Only a FIFO is read; a regular file at this path is ignored. `""` or absent: none. |

Two profiles should never share a `config_dir`, a registry or a charters dir.

## `[terminal]`

| key | required | meaning |
|---|---|---|
| `command` | no | Template for opening a terminal tab. It must contain `{cmd}`. Absent or `""`: the tool prints the command for you to paste instead of opening a tab. |

The template is split like a shell command line (`shlex.split`), then `{cmd}` is replaced inside whichever word holds it. The replacement is never split again, so quote the word when you add text around `{cmd}`. The first word is looked up on `PATH`; if it is not found, the tool prints the command to paste instead.

`{cmd}` becomes one of these:

- interactive relaunch: `cd <cwd> && <launcher> --resume <id> --name <name> [--permission-mode PM] [--model M]`
- interactive `new`: `cd <cwd> && <launcher> --name <Name> [...] "$(cat <charters>/<Name>.md)"`
- `attach`: `<launcher> attach <job id, or the first 8 characters of the session id>`

The shell in the template must be interactive (`zsh -ic`, `bash -ic`) so that a launcher defined in your shell rc exists. A trailing `; exec zsh` keeps the tab open after claude exits.

The invocation the tool used before the config file existed, and the value to keep for that behaviour:

```toml
command = "ptyxis --tab -- zsh -ic '{cmd}; exec zsh'"
```

which runs `ptyxis --tab -- zsh -ic '<cmd>; exec zsh'`. Inside a running tmux session, a window instead of a tab:

```toml
command = "tmux new-window zsh -ic '{cmd}; exec zsh'"
```

## Paths

Every path value (`config_dir`, `registry`, `charters`, `secrets_mount`):

- `~` expands to your home directory, and `$VAR` or `${VAR}` to the environment variable (an unset variable is left as written).
- A relative path is relative to the directory that holds the config file.

## Launcher

A launcher sets the account's config dir, sources its secrets if it has any, and passes every argument through to `claude`. In zsh or bash:

```sh
# config dir only
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'

# config dir plus a secrets FIFO, read with a 5 second bound
claude-personal() {
  (
    f="$HOME/.secrets/claude-personal.env"
    if [ -p "$f" ]; then
      set -a; . <(perl -e 'alarm 5; exec("cat", $ARGV[0])' "$f" 2>/dev/null); set +a
    fi
    CLAUDE_CONFIG_DIR="$HOME/.claude-personal" exec claude "$@"
  )
}
```

`sessions init` takes each profile's launcher from your shell rc: the function or alias whose body sets that `CLAUDE_CONFIG_DIR`, or plain `claude` when the rc exports it globally. `~/.claude` with no launcher of its own gets plain `claude`. For any other config dir with no launcher it generates a function, `claude-<profile>() { CLAUDE_CONFIG_DIR="$HOME/.claude-<x>" command claude "$@"; }`, in `launchers.sh` next to the config file (mode 0600), and offers to append the one line that sources that file to your shell rc (`~/.zshrc` or `~/.bashrc`, by `$SHELL`):

```sh
[ -f "$HOME/.config/claude-sessions/launchers.sh" ] && . "$HOME/.config/claude-sessions/launchers.sh"
```

A generated launcher sets only the config dir. If the account has secrets, write your own launcher as above and change `launcher` to its name.

The tool runs bg launches and `send` without the launcher: it starts `claude` directly with the environment the launcher would give it (the calling session's own variables removed, `secrets_mount` sourced, `CLAUDE_CONFIG_DIR` set). So `config_dir` and `secrets_mount` must match what the launcher does.

## Validation

The file is read on every run, and any of these stops the command with a message naming the file:

- the file is not valid TOML
- there is no `[profiles.<name>]` table
- a profile lacks `config_dir`, `registry`, `charters` or `launcher`, or a value is not a string
- `default_profile` names no profile
- `[terminal] command` is set but has no `{cmd}`

An unknown profile in `--profile` or `SESSIONS_PROFILE` is an error too. Unknown keys are ignored.

## Registry file

Each profile's registry is a TOML file of `[[session]]` tables. The tool writes it (`register`, `new`, `seed`, `unregister`, `sync`) atomically with mode 0600, in this field order, and only the header comment survives a rewrite. Editing it by hand is fine between runs.

| field | meaning |
|---|---|
| `name` | Registry name, matched case- and punctuation-insensitively. |
| `purpose` | One line on what the session is for. |
| `cwd` | Absolute working directory. The transcript is looked for under this directory's project folder. |
| `config_dir` | Must be the profile's `config_dir`; an entry from another profile is refused. |
| `mode` | `bg` or `interactive`. |
| `permission_mode` | Passed as `--permission-mode` on interactive relaunches. `new` records the value it was started with. `""` means none. |
| `model` | Passed as `--model` on interactive relaunches. `new` records the value it was started with. `""` means the account's default model. |
| `name_flag` | The `--name` the session runs under, if it differs from `name`. |
| `last_session_id` | The session uuid that `--resume` uses. `sync` keeps it current. |
| `last_pid` | Tool-managed; used to spot a stale socket. |
| `charter` | Path of the charter the session was started from. |
| `notes` | Free text, for example the in-session schedules to re-create after a resume. |

bg relaunches use only `last_session_id` and `cwd`: they pass `--bg --resume <id>` and nothing else (see the resume rule in the README). See `examples/registry.toml`.

Directories the tool creates (the registry's directory, the charters dir) are made with mode 0700. Existing directories are left as they are.
