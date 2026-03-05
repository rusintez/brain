# brain

A local AI assistant that runs entirely on your Mac. No API keys, no cloud, no subscription.

```bash
brain "What files are in my Downloads?"
brain "Organize these screenshots by content"
brain "Find all TODOs in this project"
```

## Why Local?

| | Cloud AI | brain |
|---|----------|-------|
| Privacy | Data sent to servers | 100% on-device |
| Cost | $20-100/month | Free forever |
| Speed | 500-2000ms latency | ~200ms |
| Offline | Requires internet | Works anywhere |

Your files, prompts, and results never leave your machine.

## Install

### Homebrew (recommended)

```bash
brew tap rusintez/tap
brew install brain
```

### From Source

```bash
git clone https://github.com/rusintez/brain.git
cd brain
./install.sh
```

### Manual Build

```bash
# Build (xcodebuild required for Metal shaders)
xcodebuild build -scheme brain -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .derived

# Install binary + Metal bundle
mkdir -p ~/.local/bin ~/.local/lib/brain
cp .derived/Build/Products/Release/brain ~/.local/lib/brain/
cp -r .derived/Build/Products/Release/mlx-swift_Cmlx.bundle ~/.local/lib/brain/

# Create wrapper script
cat > ~/.local/bin/brain << 'EOF'
#!/bin/bash
exec ~/.local/lib/brain/brain "$@"
EOF
chmod +x ~/.local/bin/brain

# Add to PATH (add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"
```

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon (M1/M2/M3/M4)
- ~2GB RAM

## Usage

```bash
brain "your task"                 # Default model (fast)
brain -m 1.7b "harder task"       # Larger model
brain -m r1 "think step by step"  # Reasoning model
brain -v "debug something"        # Verbose output
brain -y "delete old files"       # Skip confirmations
brain -i file.txt "summarize"     # With file input
```

## Models

Models download automatically on first use (~500MB-2GB each):

| Flag | Model | RAM | Speed | Best for |
|------|-------|-----|-------|----------|
| `-m 0.6b` | Qwen3-0.6B | ~400MB | ~200ms | Quick tasks (default) |
| `-m 1.7b` | Qwen3-1.7B | ~1GB | ~1s | General use |
| `-m 4b` | Qwen3-4B | ~2.5GB | ~3s | Complex tasks |
| `-m r1` | DeepSeek-R1 | ~1GB | ~2s | Reasoning |

## Tools

Built-in:
- `read` / `write` - File I/O
- `bash` - Shell commands

Extensible via skills (`~/.config/brain/skills/*.json`):

```json
{
  "name": "files",
  "tools": {
    "ls": {
      "description": "List directory",
      "command": "ls -la {path}",
      "args": ["path"]
    }
  }
}
```

## Safety

Destructive operations require confirmation:

```
⚠️  RM: ~/file.txt
Proceed? [y/N]
```

Use `-y` to skip for automation.

## Automation

```bash
# Cron job
0 9 * * * brain -y "Archive downloads older than 7 days"

# Git hook
brain "Write commit message" -i <(git diff --staged)

# Pipe
cat error.log | brain "Explain this error"
```

## License

MIT
