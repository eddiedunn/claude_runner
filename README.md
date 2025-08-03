# Claude Runner - Docker Container with Persistent Authentication

Run Claude Code in Docker containers using your Claude Max/Pro subscription with persistent authentication.

## Key Features

- 🔐 **One-time authentication**: Login once, use forever
- 🎯 **Official Anthropic image**: Based on official Node.js 20 image
- 💰 **Subscription reuse**: Uses your Claude Max/Pro subscription (no API charges)
- 🐳 **Isolated execution**: All code runs in containers, keeping your host clean
- 🚀 **Hook integration**: Automatically offload execution to containers
- 🎨 **FZF-powered installer**: Interactive project directory selection

## How It Works

Claude CLI stores credentials differently:
- **On macOS host**: Uses Keychain (not accessible from containers)
- **In containers**: Uses file-based storage at `/home/node/.claude.json`

Once authenticated inside a container, these files can be saved and mounted into unlimited future containers.

## Installation

### Option 1: Interactive Installation (Recommended)

```bash
# Download and run installer - it will use FZF to let you choose a project directory
curl -sSL https://raw.githubusercontent.com/eddiedunn/claude_runner/main/install-claude-runner.sh | bash
```

### Option 2: Manual Installation

```bash
# Clone directly to a specific location
git clone https://github.com/eddiedunn/claude_runner.git /path/to/your/project/claude-runner
cd /path/to/your/project/claude-runner
```

## Quick Start

### First Time Setup (One-time only)

1. **Build the official image**:
   ```bash
   docker build -f Dockerfile.official -t claude-runner-official:latest .
   ```

2. **Authenticate and save credentials**:
   ```bash
   # Start a temporary container for authentication
   docker run -it --name temp-auth claude-runner-official:latest bash
   
   # Inside container:
   claude
   /login
   # Complete the OAuth flow in your browser
   # Exit container (Ctrl+D or exit)
   ```

3. **Save authentication for reuse**:
   ```bash
   ./scripts/save_container_auth.sh temp-auth
   docker rm temp-auth  # Clean up
   ```

### Daily Usage

```bash
# Start container with saved authentication (already logged in!)
./scripts/start_persistent_runner.sh

# Enter the container - Claude is ready to use
docker exec -it claude-runner bash
```

### Using with Projects

```bash
# Mount your project into the container
docker run -it --rm \
  -v ~/.claude-docker/claude.json:/home/node/.claude.json:ro \
  -v ~/.claude-docker/container-claude-dir:/home/node/.claude:ro \
  -v "$(pwd):/workspace" \
  -w /workspace \
  claude-runner-official:latest bash
```

## Advanced: Hook-Based Execution

Automatically offload Claude Code execution to containers when you click "Yes, and auto-accept edits".

### Setup Hook System

1. **Configure hook** in your project's `.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PreToolUse": [{
         "matcher": "*",
         "hooks": [{
           "type": "command",
           "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/offload_to_docker.sh"
         }]
       }]
     }
   }
   ```

2. **Copy hook script** to your project:
   ```bash
   mkdir -p .claude/hooks
   cp /path/to/claude-runner/.claude/hooks/offload_to_docker.sh .claude/hooks/
   chmod +x .claude/hooks/offload_to_docker.sh
   ```

### How Hooks Work

1. You interact with Claude normally in the UI
2. When you accept a plan, the hook intercepts execution
3. Work is automatically offloaded to a container
4. All changes happen in the container, not on your host
5. Results are saved to a local git branch

## Project Structure

```
claude_runner/
├── Dockerfile.official              # Based on Anthropic's official image
├── install-claude-runner.sh         # FZF-powered installer
├── scripts/
│   ├── save_container_auth.sh      # Extracts auth from container
│   ├── start_persistent_runner.sh  # Starts container with saved auth
│   └── build_claude_cli_from_source.sh # Build CLI from source (optional)
├── .claude/
│   ├── hooks/
│   │   └── offload_to_docker.sh    # Hook for automatic offloading
│   ├── settings.json               # Hook configuration
│   └── settings.local.json         # Local overrides (gitignored)
└── tests/                          # Comprehensive test suite
```

## Authentication Files

After first authentication, files are saved to:
```
~/.claude-docker/
├── claude.json              # User config & OAuth tokens
└── container-claude-dir/    # Claude data directory
```

These files enable persistent authentication across all containers.

## Troubleshooting

### Authentication Issues
- **Not logged in?** Ensure you completed `/login` inside the container
- **Files missing?** Check: `ls -la ~/.claude-docker/`
- **Container not running?** Verify: `docker ps`

### Re-authentication
```bash
# Start fresh container
docker run -it --name reauth claude-runner-official:latest bash
# Inside: claude, then /login
# Save new auth
./scripts/save_container_auth.sh reauth
docker rm reauth
```

### Hook Issues
- **Hook not firing?** Check `.claude/settings.json` syntax
- **Permission denied?** Ensure hook is executable: `chmod +x .claude/hooks/offload_to_docker.sh`
- **Container not found?** Verify image exists: `docker images | grep claude-runner`

## Benefits

- ✅ **Subscription reuse**: Uses your Claude Max/Pro subscription, no API charges
- ✅ **Safe execution**: All code changes happen in isolated containers
- ✅ **One-time setup**: Authenticate once, use across all projects
- ✅ **Git branch safety**: Changes stay on local branches until you push
- ✅ **Clean host**: Your development machine stays untouched

## Requirements

- Docker Desktop or Docker Engine
- Claude Max or Pro subscription
- macOS, Linux, or WSL2
- (Optional) FZF for interactive installer

## Contributing

Contributions welcome! Please test changes using the included test suite:

```bash
cd tests
./run_all_tests.sh
```

## License

MIT - See LICENSE file for details