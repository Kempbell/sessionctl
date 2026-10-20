# AGENTS.md

You are a coding agent (Claude Code, Codex, Cursor) working in a clone of sessionctl. `CLAUDE.md` is a symlink to this file.

## What this is

sessionctl is a registry plus a CLI, `sessions`, for the Claude Code sessions a person keeps running for days or weeks: which ones should exist, which are live, and relaunching the missing ones after a reboot. Each Claude Code account (each `CLAUDE_CONFIG_DIR`) is a profile, and profiles never mix.

## Setting it up for the user

1. Run `./install.sh --dry-run` in the clone. It links `sessions` and `sessionctl` into `~/.local/bin` and prints what `sessions init` would do, writing nothing else. Run from inside your session, it makes the account you run under the default profile.
2. Show the user the plan it printed: the Claude Code config dirs it found with each one's launcher, the config file it would write, any generated launchers, and the line it would add to their shell rc. Ask whether that is right.
3. On their yes, run `./install.sh --yes`. If a config already exists, init stops and says so; tell the user, and run it with `--force` (which keeps a `.bak` copy) only on their word. If they want something changed, such as a profile name or a launcher, edit the config after the install, as below.
4. Run `sessions` to print the table, then `sessions seed --dry-run` to show which running sessions it would register. Run `sessions seed` on their word, and `sessions --profile <name> seed` the same way for each other profile.
5. Report the table to the user. If launchers were generated, tell them to open a new shell so the launchers exist there.

## Rules

- Never write a secret value into the config. `secrets_mount` is the path of a FIFO that holds them, never the values themselves.
- Never kill, signal or message a session. The tool is read-only toward live sessions, and so are you while you set it up.
- Show the user a diff before you edit `config.toml`, and save it only on their yes.
- A relaunch is `sessions up <name>` or `sessions up --missing`, never a hand-typed `claude --resume` with extra flags: one extra flag on a bg resume starts a copy under a new id.

## Where the docs are

`README.md` covers usage and every command, `docs/CONFIG.md` is the config format, and `docs/HOW-IT-WORKS.md` lists every Claude Code internal the tool reads.

## Working on the code

The tool is one file, `bin/sessions`: Python 3.11 or newer, standard library only, no dependencies. Keep it one file. `docs/CONFIG.md` is the standard for the config file, so a change to what the config holds or how it is read changes that page in the same commit. `docs/HOW-IT-WORKS.md` lists every Claude Code internal the tool reads and everything it writes; keep it complete when you add one.

Test `init` without touching the user's real config, with a temp home holding fake config dirs:

```sh
H=$(mktemp -d)
mkdir -p "$H/.claude/projects" "$H/.claude-work/sessions"
HOME=$H SESSIONS_CONFIG=$H/cfg/config.toml bin/sessions init --dry-run
HOME=$H SESSIONS_CONFIG=$H/cfg/config.toml bin/sessions init --yes
HOME=$H SESSIONS_CONFIG=$H/cfg/config.toml bin/sessions doctor
```

The accounts of `claude` processes already running still show up, since init reads them from `/proc`. Never run `sessions init --yes` or `--force` against the real `~/.config/claude-sessions/config.toml` while you work on the code. `python3 -m py_compile bin/sessions` and `bin/sessions --help` are the quick checks.
