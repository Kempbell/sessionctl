# How it works

`sessions` knows nothing a Claude Code session does not leave lying around. It reads a few pieces of per-session metadata that Claude Code writes, plus `/proc`, and it launches `claude` with ordinary command-line flags. None of these pieces is a documented interface, so this page lists every one it depends on. If a Claude Code update breaks discovery or relaunch, start here.

Below, `<config>` is a profile's `config_dir` (the account's `CLAUDE_CONFIG_DIR`) and `<uid>` is your numeric user id.

## What it reads

### Per-pid state files: `<config>/sessions/<pid>.json`

Claude Code writes one JSON file per running session process. The tool uses these fields: `sessionId`, `name`, `cwd`, `kind` (`interactive` or `bg`), `status`, `jobId`, `parkedJobId` and `procStart`.

A state file can outlive its process, and Linux reuses pids, so a file only counts when its `procStart` equals field 22 of `/proc/<pid>/stat` (the start time of the process now holding that pid). Otherwise it is ignored as stale.

### The socket directory: `/run/user/<uid>/cc-socks/<pid>.sock`

Each session process creates a socket named after its pid. The tool uses only the names (as candidate pids) and their modification times. A socket counts as owned by the live process only if it was modified after that process started (with one second of slack); an older one is left over from an earlier process with the same pid. Sockets are never opened, and never deleted.

### `/proc/<pid>`

For each candidate pid (from the socket names and the state file names):

- `/proc/<pid>/environ`: only `CLAUDE_CONFIG_DIR` is kept, to decide which profile the process belongs to. A process of another profile is skipped right there. For a process without a valid state file, `CLAUDE_CODE_SESSION_KIND` is kept as well. No other variable is extracted.
- `/proc/<pid>/cmdline`: whether it is `claude` (the program name is `claude`, or its path contains `/claude/versions/`), its `--resume`/`-r`, `--session-id`, `--fork-session` and `--name`/`-n` values, and its `--model` and `--permission-mode` for `register --pid`.
- `/proc/<pid>/stat` and the `btime` line of `/proc/stat`: when the process started.
- `/proc/<pid>/cwd`: the working directory, when the state file has none.
- `/proc/<pid>/fd/0`: the tty of an interactive session, printed by `attach`.

`doctor` also reads the command line of every process, to find warm spares.

A live session comes from its state file when one is valid. Otherwise it is built from the command line, but only when the process is `claude`, is not a warm spare, and owns its socket.

Warm spares: the Claude Code daemon keeps idle processes ready for the next bg session. Their command line holds `--bg-spare` without `--bg-pty-host`. They are not sessions; the table skips them and `doctor` counts them. A spare that has been claimed has a valid state file and is a real session.

Parked sessions: an interactive session whose conversation moved to a bg job keeps its old process. Its state file's `parkedJobId` names the live job. The table counts the job, not the parked process, and `doctor` lists the parked one.

### Job folders: `<config>/jobs/<first 8 of the session id>/state.json`

The launch record of a bg job. Used by `register --pid` and `register --session-id` to fill in `cwd`, `name`, whether it is bg (`template` is `bg`), and the `--model` and `--permission-mode` among its `respawnFlags`. The file only counts when its `sessionId` matches.

### Transcripts: existence only

`<config>/projects/<cwd with every non-alphanumeric character replaced by "-">/<session id>.jsonl`

`claude --resume <id>` finds a transcript only under the project folder of the directory it runs in. Before a relaunch the tool checks that this file exists. If it does not, it searches `<config>/projects/*/` for the file name to say where the transcript went (for example, under a worktree's project folder), and refuses that relaunch. `doctor` runs the same check for every entry. Transcript files are never opened.

## How a registry entry is matched to a live session

First by `last_session_id`, then by name: the entry's `name` and `name_flag` against the live session's name, compared as lowercase letters and digits only. More than one match shows as `LIVE <pid> (+N dup)`. When nothing matches, the entry is `MISSING`, or `STALE-SOCKET` when a socket for its `last_pid` remains but is not owned by a live process.

## What it launches

The environment for everything launched directly: the calling process's environment minus the variables a Claude session sets for itself (`CLAUDECODE`, `CLAUDE_PID`, `CLAUDE_JOB_DIR`, `CLAUDE_EFFORT`, `CLAUDE_BG_*`, `CLAUDE_BRIDGE_*`, `CLAUDE_CODE_SESSION_*`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_BRIDGE_*`, `CLAUDE_CODE_MESSAGING_*`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`, `CLAUDE_CODE_SSE_PORT`), plus the profile's `secrets_mount` sourced (5 second bound, FIFO only), plus `CLAUDE_CONFIG_DIR`. Without that cleanup, a launch from inside a session would carry that session's own variables into the new one. The `claude` binary is the one on that environment's `PATH`, else `~/.local/bin/claude`.

| command | what runs |
|---|---|
| `up`, bg entry | `claude --bg --resume <id>` in the entry's `cwd`, directly. No other flag: a bg session keeps its own saved launch options, and any extra flag makes claude start a copy under a new id. |
| `up`, interactive entry | a terminal tab (`[terminal] command`) running `cd <cwd> && <launcher> --resume <id> --name <name_flag or name> [--permission-mode PM] [--model M]` |
| `new --mode bg` | `claude --bg --name <Name> [--permission-mode PM] [--model M] "<charter text>"` in `--cwd`, directly. The first 8-hex-digit token in its output is taken as the job id; the tool then polls for up to 20 seconds for a new live session with that job id, session id prefix or name, and registers it. |
| `new --mode interactive` | a terminal tab running `cd <cwd> && <launcher> --name <Name> [...] "$(cat <charters>/<Name>.md)"` |
| `attach` | a terminal tab running `<launcher> attach <job id or first 8 of the session id>` |
| `send` | `timeout --kill-after=15 <timeout> claude -p <relay prompt> --model haiku --name relay-<sender> --permission-mode dontAsk --permission-prompts none --tools SendMessage,ListAgents --allowedTools SendMessage ListAgents --strict-mcp-config --no-session-persistence --output-format text --max-budget-usd <budget>` in `~`, directly |

A charter is passed as the positional prompt. A charter that starts with `-` gets a leading newline so it is not parsed as an option, and one over 100,000 bytes is refused.

`up` refuses an entry that is already live (that would start a copy), an entry whose `config_dir` is not the profile's, and an entry whose transcript is not where `--resume` will look.

## What it writes

- The profile's registry file: written to a `.tmp` file next to it and renamed into place, mode 0600.
- Charter copies in the profile's charters dir, mode 0600.
- The registry's directory and the charters dir, mode 0700, only if they do not exist yet.

Nothing else. It never writes into a Claude Code config dir or `/run/user/<uid>`.

## What it never does

- Read a transcript or any session contents. Transcripts are checked for existence only.
- Read any environment variable of another process beyond `CLAUDE_CONFIG_DIR` and `CLAUDE_CODE_SESSION_KIND`.
- Kill or signal a process. The one exception is the relay that `send` itself starts, which `timeout` ends if it overruns `--timeout`.
- Delete sockets, state files, job folders or transcripts. `doctor` only reports.
- Relaunch a session that is already live.
- Print a secret. Values from `secrets_mount` stay in the launch environment.
- Mix profiles. Each listing and each launch is limited to one profile's config dir.
