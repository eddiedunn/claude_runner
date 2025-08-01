# Claude Runner (Local Container Offload)

Run Claude Code plans **entirely inside Docker** while still using your **Claude Max / Pro** subscription and keeping all commits on a local branch.

---

## Why

* **Zero PAYG fees** – re-use the OAuth tokens saved by `claude login` so your Max plan covers usage.
* **Isolated execution** – every tool call after you approve a plan runs in a disposable container; nothing touches your host except Git commits.
* **Safe Git workflow** – the container creates commits only on a local branch (default: `feature/auto`). No remote pushes occur unless _you_ push.

---

## Prerequisites

1. **Claude CLI 0.30+** installed on the host and authenticated via **Claude App (Pro / Max)**.
2. **Credentials exported** to `~/.claude/.credentials.json`:
   ```bash
   security find-generic-password -s "Claude Code-credentials" -w > ~/.claude/.credentials.json
   chmod 600 ~/.claude/.credentials.json
   ```
3. **Docker** installed and running.

---

## Quick start

```bash
# 1. Clone this repo and enter it
cd claude_runner

# 2. Build the runner image (takes ~1-2 min the first time)
docker build -t claude-runner:latest .

# 3. Launch the Claude CLI as usual
claude
# –> create a plan, click "Yes, and auto-accept edits"
# The PreToolUse hook fires and everything executes inside Docker.
```

You will see:
* The local tool call blocked (exit 2) on your host.
* Docker logs appearing for the container run.
* A new branch `feature/auto` with committed changes when the container exits.

---

## How it works

1. **Hook trigger** – `.claude/settings.json` registers `offload_to_docker.sh` for every `PreToolUse` event.
2. **Session hand-off** – the script reads `session_id` from the hook payload and starts the `claude-runner` container, mounting:
   * `/workspace` – your repo (read-write)
   * `/home/node/.claude` – credentials (read-only)
3. **Container run** – inside Docker, the script resumes the same Claude session with flags that:
   * allow standard tools (`Read,Write,Edit,Bash,Git`)
   * block pushes (`--disallowedTools "Bash(git push:*)"`)
4. **Finish** – when done the script writes `.claude/offload_done` and exits 2 to suppress local execution.

---

## File tree (key parts)

```
claude_runner/
├─ Dockerfile                   # builds claude-runner image
├─ .claude/
│  ├─ settings.json             # registers PreToolUse hook
│  └─ hooks/offload_to_docker.sh# offload logic
├─ TASK_LIST.md                 # design notes & tasks
└─ README.md                    # you are here
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `session_id` not found error | Ensure `jq` is installed on host (homebrew: `brew install jq`). |
| Container cannot auth / prompts for login | Verify `~/.claude/.credentials.json` exists & readable; or mount full `~/.claude` folder. |
| Git pushes accidentally happen | Confirm `--disallowedTools` flag is present in `offload_to_docker.sh`. |
| Token expires after 8 h | Mount credentials directory **writable** instead of read-only, or run a token-refresh cron job. |

---

## License

MIT
