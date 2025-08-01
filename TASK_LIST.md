Goal
Enable a fully local, containerized execution of a Claude Code plan (triggered when you click “Yes, and auto-accept edits”) that:

Reuses your Claude Max/Pro subscription (so you aren’t charged per-token via API keys), and

Keeps all code changes on a local branch (i.e., nothing is pushed remotely unless you explicitly do so).

What it’s doing, step by step (conceptually)
Authenticate once via Claude App (Max/Pro)
You log into Claude Code on your Mac using your Max/Pro account. That session stores credentials (OAuth tokens) in the macOS Keychain under the proper service name (e.g., Claude Code-credentials or legacy Claude Code). This lets subsequent Claude CLI invocations draw from your subscription rather than falling back to pay-per-use API keys.

Extract or reuse those credentials for Docker
To give the container the same authenticated context, the instructions show two options:

Export the Keychain-stored token to ~/.claude/.credentials.json and mount that into the container, or

Mount the Keychain-derived credential directory (read-only) so the container can reuse the existing session (with USE_CLAUDE_CREDENTIALS=true), preserving your Max plan usage.

Intercept the moment the plan is accepted
A PreToolUse hook is configured so that when you click “Yes, and auto-accept edits” (which causes Claude to schedule its first tool call), the hook runs. That hook:

Reads the session ID from Claude’s hook payload,

Spawns a Docker container, mounting your workspace and the credential material,

Resumes the same Claude session inside the container (--resume <session_id>) in headless/non-interactive mode to execute the plan,

Blocks local execution by exiting with code 2 so nothing happens on your laptop.

Execute the plan inside the container using your Max credentials
Inside Docker, Claude runs with the full plan context, performs the edits, and creates a new local Git branch (e.g., feature/auto) and commits the changes. The --disallowedTools or policy in the prompt prevents it from pushing, so all commits remain local unless you explicitly push later.

Resulting state
You get a local feature branch with the implemented plan, committed, with no remote side effects and using your Max plan quota. The local environment stayed untouched beyond triggering the handoff; all real work happened in the isolated container.

Key benefits / why this matters
Subscription reuse: Avoids PAYG API billing by reusing the OAuth credential tied to your Max/Pro account.

Safe separation: Planning stays interactive and local until you explicitly accept; execution happens in an isolated container.

Controlled output: Edits and commits are made on a local branch; no automatic remote pushes unless you choose.

Deterministic handoff: PreToolUse is the reliable signal that the plan was accepted, so you don’t prematurely execute anything.

Important safety/operational notes
Mounting the credential file read-only may limit automatic token refresh; writable if you want long-lived refreshes.

Blocking the first tool call locally prevents accidental side effects on your workstation.

Keeping git pushes disabled inside the container preserves local-only workflow until you’re ready to share.

* lets your local Docker runner **reuse your Claude Max subscription** (so you are charged only against Max‑plan message limits, not per‑token API rates), and
* keeps **all commits on a local branch** unless *you* later push them.

---

## 1  Install & authenticate once on the host

| Task                                         | Command / Action                                                                                         | Reference                    |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ---------------------------- |
| Install CLI                                  | `npm install -g @anthropic-ai/claude-code`                                                               | ([Anthropic][1])             |
| Launch for first time                        | `claude` → select **“Claude App (Pro/Max)”** when prompted, then sign in with your Claude AI credentials | ([Anthropic Help Center][2]) |
| Confirm you’re on the subscription, not PAYG | Inside the REPL run `/status` – it should show *Plan = Max* and *Billing = Subscription* (no dollars)    | ([Anthropic][3])             |

**Where the token is stored**

* Linux / WSL / Docker‑friendly OSes: `~/.claude/.credentials.json`
* macOS: secure Keychain entry `com.anthropic.claude-code` (exportable with `security find-generic-password -s "Claude Code-credentials" -w > ~/.claude/.credentials.json`)
  ([GitHub][4])

> You only do this **once**; afterwards your container can reuse the same file.

NOTE: STEP 1 has already been performed. 

---

## 2  Build a local runner image that contains Claude Code

```dockerfile
# Dockerfile
FROM node:20-bullseye
RUN apt-get update \
 && apt-get install -y git jq python3 \
 && npm install -g @anthropic-ai/claude-code         # CLI inside container
WORKDIR /workspace
CMD ["bash"]
```

```bash
docker build -t claude-runner:latest .
```

(The official “development‑container” image is even more locked‑down and supports `--dangerously‑skip‑permissions` out of the box. Use it later for prod hardening.) ([Anthropic][1])

---

## 3  Mount both the **repo** *and* the **credentials** when the hook fires

### `.claude/hooks/offload_to_docker.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
read -r payload
SESSION_ID=$(jq -r '.session_id' <<<"$payload")
WORKSPACE="$CLAUDE_PROJECT_DIR"

docker run --rm \
  -e USE_CLAUDE_CREDENTIALS=true \          # tell image to look for creds file
  -v "$HOME/.claude:/home/node/.claude:ro" \# mount your saved token
  -v "$WORKSPACE":/workspace \
  claude-runner:latest bash -lc '
     cd /workspace &&
     claude -p --resume "$SESSION_ID" \
       --dangerously-skip-permissions \
       --allowedTools "Read,Write,Edit,Bash,Git" \
       --disallowedTools "Bash(git push:*)" \   # blocks remote pushes
       --max-turns 50 \
       "Proceed with the approved plan, create a **local** branch called feature/auto, commit all changes, DO NOT push."
  '

touch "$WORKSPACE/.claude/offload_done"
exit 2   # block the local tool call
```

*Mounting the credentials directory plus `USE_CLAUDE_CREDENTIALS=true` is enough for the CLI in the container to authenticate against your Max plan.* ([GitHub][4])
The `--disallowedTools` flag ensures even if Claude tries `git push`, the call is denied at the CLI level. ([Anthropic][5])

---

## 4  Wire the hook

```jsonc
// .claude/settings.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/offload_to_docker.sh" }
        ]
      }
    ]
  }
}
```

Exactly one local tool call triggers → hook launches Docker → exits 2 so nothing runs on your laptop. The rest happens in the container. ([Anthropic][6], [Anthropic][6])

---

## 5  Workflow you’ll see

1. **Iterate in Plan Mode**. Keep answering *“No, keep planning”* until happy.
2. Hit **“Yes, and auto‑accept edits.”**
3. `PreToolUse` fires → off‑load script starts container.
4. Container resumes the same session (`--resume $SESSION_ID`), executes the plan, **creates a local branch and commits**.
5. Container stops. Your repo now has `feature/auto` with commits; nothing was pushed.

If later you decide to share the work, just `git push origin feature/auto` from your workstation.

---

## 6  Cost & limit realities

* Using **Max** or **Pro** credentials through `claude login` means **no per‑token billing**; usage is deducted from your subscription pool. Anthropic recently added weekly caps for Claude Code (to curb 24/7 runners) so extremely large automated sessions may still be rate‑limited. ([Tom's Guide][7])
* If you ever log back in with a **Console API key** the CLI flips to PAYG rates (see pricing table). Check `/status` before big runs. ([Anthropic][6])

---

### Summary

*Save credentials once → mount into Docker → block `git push` → enjoy local‑only automation inside a safe container while drawing down **Max‑plan messages** instead of dollars.*

[1]: https://docs.anthropic.com/en/docs/claude-code/setup "Set up Claude Code - Anthropic"
[2]: https://support.anthropic.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan "Using Claude Code with your Pro or Max plan | Anthropic Help Center"
[3]: https://docs.anthropic.com/en/docs/claude-code/slash-commands?utm_source=chatgpt.com "Slash commands - Anthropic"
[4]: https://github.com/koogle/claudebox "GitHub - koogle/claudebox: Run claude code in a container"
[5]: https://docs.anthropic.com/en/docs/claude-code/cli-reference "CLI reference - Anthropic"
[6]: https://docs.anthropic.com/en/docs/about-claude/pricing "Pricing - Anthropic"
[7]: https://www.tomsguide.com/ai/anthropic-is-putting-a-limit-on-a-claude-ai-feature-because-people-are-using-it-24-7?utm_source=chatgpt.com "Anthropic is putting a limit on a Claude AI feature because people are using it '24/7'"
[8]: https://docs.anthropic.com/en/docs/claude-code/hooks "Hooks reference - Anthropic"
[9]: https://docs.anthropic.com/en/docs/claude-code/devcontainer "Development containers - Anthropic"

### Why your `security find-generic-password` call fails

On macOS the **Claude Code CLI** stores its OAuth tokens in Keychain *but the
service label is not* `"claude-code"`:

| CLI version  | Keychain service label    | Typical command to dump it                                                     |
| ------------ | ------------------------- | ------------------------------------------------------------------------------ |
|  ≥ v 1.0.4   | `Claude Code‑credentials` | `security find-generic-password -s "Claude Code-credentials" -w` ([GitHub][1]) |
|  0.3 – 1.0.3 | `Claude Code`             | `security find-generic-password -s "Claude Code" -w` ([GitHub][2])             |

If you logged in with **Claude App (Pro / Max)** rather than an API key, one of
those two entries **will** be present because the CLI explicitly writes Pro/Max
tokens to the macOS Keychain ([Anthropic][3]).

---

### Quick checks

1. **Verify how you authenticated**

   ```bash
   claude status        # or type /status inside the REPL
   ```

   *If it says* `Auth method: Anthropic API key` then you are **not** using your
   Max plan; no Keychain item is created.
   Repeat `claude login` and choose **Claude App (Pro/Max)** instead.

2. **Locate the credential item**

   ```bash
   # Show any Claude items for the current user
   security find-generic-password -a "$USER" | grep -i "Claude"

   # Dump the token (will be JSON) – try new then legacy label:
   security find-generic-password -s "Claude Code-credentials" -w \ 
     || security find-generic-password -s "Claude Code" -w
   ```

   The `-w` flag prints only the secret; omit it if you want the full record
   (handy to see creation dates, etc.).

3. **Still nothing?**
   Open **Keychain Access › login keychain › search “Claude”** to make sure a
   GUI‑level item doesn’t exist under a different account name (occasionally the
   account field is your e‑mail address, not `$USER`).

---

### Exporting the token for Docker or CI

If you need the credential outside macOS (e.g., inside a container) you have
two options.

| Option                                                            | Steps      | When to use |
| ----------------------------------------------------------------- | ---------- | ----------- |
| **Mount Keychain JSON**                                           | \`\`\`bash |             |
| mkdir -p \~/.claude                                               |            |             |
| security find-generic-password -s "Claude Code-credentials" -w \\ |            |             |

> \~/.claude/.credentials.json
> chmod 600 \~/.claude/.credentials.json

````Mount that folder read‑only:  
```bash
docker run -v "$HOME/.claude:/home/node/.claude:ro" \
           -e USE_CLAUDE_CREDENTIALS=true   …```|Fast; keeps OAuth flow alive; token auto‑refresh still works because refresh tokens are in the JSON.|
|**Switch to API key**|Create an Anthropic Console key and set  
`export ANTHROPIC_API_KEY=sk‑...` inside the container.|If you prefer stateless images or don’t mind PAYG billing.|

`claudebox`, `claude‑sandbox`, and other community images already honour
`USE_CLAUDE_CREDENTIALS=true` and look for the file in `/home/node/.claude/`
(or `$HOME/.claude/`) :contentReference[oaicite:3]{index=3}.

---

### Tips & gotchas

* **Token refresh** – the JSON blob contains both `accessToken` *and*
  `refreshToken`. As long as the file is writable the CLI will rotate the token
  automatically; if you mount it `ro`, refresh will fail after ~8 h. Tools like
  *claude‑token‑refresh* can rotate the file for you :contentReference[oaicite:4]{index=4}.
* **Avoid duplicate logins** – if both *Keychain* and `ANTHROPIC_API_KEY` are
  set, the CLI prefers the env‑var and you will get PAYG pricing instead of
  Max plan (see bug #1511) :contentReference[oaicite:5]{index=5}.
* **Cleaning up** – to force a fresh OAuth flow:  
  `claude logout && security delete-generic-password -s "Claude Code-credentials"`  
  then run `claude login` again.

---

#### Summary

* On macOS look for **`"Claude Code‑credentials"`** (new) or **`"Claude Code"`**
  (old) in the Keychain—not “claude‑code”.
* Use `security find-generic-password -s "<label>" -w` to extract the JSON
  credential and, if needed, save it to `~/.claude/.credentials.json` so Docker
  containers (or remote runners) can reuse your **Claude Max** subscription
  without triggering pay‑per‑token API charges.
::contentReference[oaicite:6]{index=6}
````

[1]: https://github.com/anthropics/claude-code/issues/1154?utm_source=chatgpt.com "[BUG] When running Claude Code from an Automator service on ... - GitHub"
[2]: https://github.com/anthropics/claude-code/issues/1311 "Invalid Claude Code API Key Configuration on MacOS Claude Code-credentials vs Claude Code · Issue #1311 · anthropics/claude-code · GitHub"
[3]: https://docs.anthropic.com/en/docs/claude-code/iam?utm_source=chatgpt.com "Identity and Access Management - Anthropic"
