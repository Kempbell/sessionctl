# sessionctl

Control for long-lived Claude Code sessions.

A registry plus a CLI, `sessions`, for the Claude Code sessions you keep running for days or weeks: which ones should exist, which are live right now, relaunching the missing ones after a reboot, starting new named ones from a charter, and attaching to a background one. It works across accounts: each Claude Code account (each `CLAUDE_CONFIG_DIR`) is a profile, profiles never mix in one listing, and `sessions --profile <x> send <Name> "..."` is the deliberate relay that carries a message from a session in one account to a named session in another.

This is an independent tool for Claude Code. It is not an Anthropic product, and it reads Claude Code internals that are not documented (see Caveats).

Every session process dies on a reboot or logout, but its transcript survives on disk, so `claude --resume <id>` brings the conversation back. The registry remembers which sessions you want, where each one runs and its last session id, so getting all of them back is three commands.

## Requirements

- Linux (it reads `/proc` and `/run/user/<uid>`).
- Python 3.11 or newer (for `tomllib`). No other dependencies.
- Claude Code with background sessions (`claude --bg`, `claude attach`).
- Optional: a terminal that can open a tab from the command line, for interactive sessions.

## Install

```sh
git clone https://github.com/Kempbell/sessionctl
sessionctl/install.sh
```

`install.sh` links `sessions`, and the same tool as `sessionctl`, into `~/.local/bin` (or `$SESSIONCTL_BIN_DIR`), then runs `sessions init`. Init writes the config from what your machine has: one profile per Claude Code config dir it finds in `~/.claude`, `~/.claude-*` and the environment of running `claude` processes, each with the launcher your shell rc already defines for it or, when there is none, a generated one in `launchers.sh` next to the config, plus the terminal it detects for opening tabs. It shows you the whole plan and asks before it writes anything. `--dry-run` prints the plan only, `--yes` skips the questions, and `--force` replaces an existing config, keeping a `.bak` copy. `install.sh` passes these through.

Or hand the clone to your agent: `AGENTS.md` is the same procedure written for it.

To do it by hand instead, write the config from `docs/CONFIG.md` and `examples/config.toml`, then run `sessions doctor`.

The config names each profile's config dir, registry, charters dir, launcher and optional secrets mount, plus how to open a terminal tab. Without a config file the tool stops and says how to write one; it never falls back to built-in paths. `SESSIONS_CONFIG=<path>` reads the config from somewhere else.

Each profile needs a launcher: a shell function or alias that runs `claude` with that account's `CLAUDE_CONFIG_DIR`. Interactive tabs run it through an interactive shell, so it must be defined in your shell rc, or in a file your shell rc sources, as `launchers.sh` is.

Then register what is already running with `sessions seed` (purposes empty) or `sessions register`, or start new sessions with `sessions new`.

## After a reboot

1. `sessions` prints the table: LIVE, MISSING or STALE-SOCKET for each registered session, the exact relaunch command under each missing one, and any live sessions not yet registered.
2. `sessions up --missing` relaunches each missing session. It asks y/N per session; `--yes` skips the questions and `--dry-run` only prints the commands.
3. `sessions sync`, once they are up, records each live session's current id and pid.

Run the same three with `--profile <name>` for each other account.

## Commands

- `sessions init [--dry-run] [--yes] [--force] [--config-dir DIR]`: write the config from the Claude Code accounts on this machine (see Install). It is the one command that runs without a config, and it stops if one exists unless you pass `--force`. `--config-dir`, repeatable, adds a config dir it would not find by itself.
- `sessions` or `sessions status`: the table above.
- `sessions up <name>` or `sessions up --missing [--yes] [--dry-run]`: relaunch one session, or every missing one. A session that is already live is never relaunched, since that would start a copy.
- `sessions sync`: refresh `last_session_id` and `last_pid` from the live sessions.
- `sessions new <Name> --mode bg|interactive [--cwd DIR] [--charter FILE] [--model M] [--permission-mode PM] [--purpose "..."] [--yes] [--dry-run]`: start a new named session (cwd defaults to the current directory) and register it once its pid and session id show up, within 20 seconds.
- `sessions attach <name>` (alias `open`) `[--dry-run]`: open a terminal tab running `<launcher> attach <id>` for a live bg session. For an interactive one it prints its pid and tty.
- `sessions register <name> --pid <pid> | --session-id <uuid> [--cwd] [--mode] [--purpose] [--model] [--permission-mode] [--name-flag] [--charter] [--notes]`: add or update an entry. Facts are read from the live process or the job folder; flags override them.
- `sessions seed [--dry-run]`: register every unregistered live session from its state file, purpose left empty.
- `sessions unregister <name>`: remove the registry entry only. The session is untouched.
- `sessions doctor`: stale sockets, idle warm spares, parked sessions and missing transcripts. Read-only; it deletes nothing.

`send`, the relay between accounts, has its own section below.

Every command except `init` takes `--profile <name>`, before or after the subcommand, or `SESSIONS_PROFILE=<name>` in the environment. Without either it uses `default_profile` from the config.

In the table, `LIVE <pid> (+N dup)` means more than one live session matches the entry, and a `*` after the short session id means the live session's id differs from the registry; `sessions sync` records the new one.

## Profiles, the wall between them, and the send door

A profile is one Claude Code account: one `CLAUDE_CONFIG_DIR`, with its own registry, charters dir and launcher. The tool keeps profiles apart on purpose:

- A listing shows one profile only. Discovery looks at a process further only when its `CLAUDE_CONFIG_DIR` is that profile's config dir.
- An entry whose `config_dir` belongs to another profile is refused rather than relaunched under the wrong account.
- A session belongs to the account that started it. Its transcript lives in that account's config dir, so moving work to another account means starting a fresh session there from the charter, not resuming the old one.

Claude Code draws the same wall: a session only sees peers in its own config dir, so `ListAgents` and `SendMessage` cannot reach a session of another account.

`send` is the one deliberate door through that wall:

```sh
sessions --profile <x> send <Name> "the message" --from <YourName>
echo "longer text" | sessions --profile <x> send <Name> - --from <YourName>
```

It runs a one-shot `claude -p` under profile `<x>` whose only tools are `ListAgents` and `SendMessage`, with no MCP servers, the haiku model and a budget cap. That run delivers the text verbatim to the session named `<Name>`, prefixed with who sent it, and prints `DELIVERED to <Name>` (exit 0) or `NOT FOUND: <Name>; peers: ...` (exit 1). A message costs cents and takes 10 to 20 seconds. Any session can call it from Bash, so it works in both directions: a session in account A reaches account B with `--profile B`, and B answers with `--profile A`. Options: `--summary`, `--budget` (default 0.5 USD), `--timeout` (default 150 s) and `--dry-run`, which prints the message without sending. The sender defaults to `$SWEEP_JOB` or `sessions`.

The tool does not restrict which profile `send` may reach. Which accounts should talk to each other is a policy you keep yourself.

## Charters

A charter is a markdown file that becomes a session's first prompt: its purpose, standing rules, schedules and first steps. `sessions new <Name> --charter FILE` copies the file into the profile's charters dir as `<Name>.md` and passes its full text to `claude` as the positional prompt, so a bg session reads it as its first message and starts working at once. Without a charter the session starts idle, waiting for a first message. The registry records the charter path, so a session can be re-issued fresh from it later. See `examples/charters/Example.md`.

## Background and interactive sessions

A **bg** session runs under the Claude Code daemon with no terminal; you look in with `sessions attach`. An **interactive** session lives in a terminal tab.

The resume rule: a bg session is relaunched with `claude --bg --resume <id>` and no other flag. A bg session keeps its own saved launch options, and any extra flag (a `--name`, `--model` or `--permission-mode`) makes claude start a copy under a new id instead of continuing the old one. The tool runs that command directly, with the environment the launcher would give it.

An interactive session is relaunched in a new tab as `cd <cwd> && <launcher> --resume <id> --name <name> [--permission-mode PM] [--model M]`: the registry's name, permission mode and model are passed again on this path. If no terminal is configured, or the terminal command is not found, the tool prints the command to paste instead.

## Caveats

- In-session cron schedules (the recurring checks a session sets for itself) expire after 7 days, and a relaunch does not bring back ones that lapsed. After a resume, check each session's schedules and re-create what is gone. Work that must run every day belongs in a timer instead (see below).
- The Claude Code daemon can retire a bg session. The process goes away and the transcript stays, so the table shows it as MISSING and `sessions up` resumes it.
- This reads undocumented Claude Code internals: the per-pid state files, the job folders, the socket directory, the warm-spare command line and the launch flags. A Claude Code update can change any of them and break discovery or relaunch. `sessions doctor` and the table are the first places it shows. `docs/HOW-IT-WORKS.md` lists every piece it depends on.
- The secrets mount is read only when it is a FIFO (a named pipe, as a secrets manager's mounted env file is). A regular file at that path is ignored.

## Related: sweep timers

Not included in this repo yet. Because in-session schedules expire, recurring work fits better as a headless job on a systemd user timer. The pattern: a `.timer` unit starts a oneshot `.service`, which runs a small runner script. The runner composes the job's prompt and runs one `claude -p` with a locked-down command line: `--permission-mode dontAsk --permission-prompts none`, `--setting-sources project,local` so a broad personal allow list is not loaded, `--tools` and `--allowedTools` limited to what the job needs, `--disallowedTools` for every send or write tool it must not have, `--strict-mcp-config` with only the MCP servers it needs, `--no-session-persistence`, `--max-budget-usd`, and a hard `timeout`. The job reports by `SendMessage` to a named long-lived session and also writes its report to a dated file, so a dead recipient costs only latency. `Persistent=true` on the timer runs a job missed while the machine was off at the next boot, and `loginctl enable-linger` lets the timers fire without a login. The runner sets `SWEEP_JOB`, which `send` uses as the default sender.

## License

MIT. See `LICENSE`.
