# Update Directions

Pull latest Directions from GitHub and sync to ~/.claude/.

## Step 1: Find Directions repo

Check these locations in order:
1. `docs/` folder in current project (if it's a Directions repo)
2. The path in `~/.claude/CLAUDE.md` under "Local master:"

## Step 2: Pull latest

```bash
cd <directions-repo> && git pull origin main
```

If there are local changes, warn the user before pulling.

## Step 3: Sync to ~/.claude/

After pulling, copy updated files to the global Claude config:

```bash
cp commands/* ~/.claude/commands/
cp CLAUDE-GLOBAL-TEMPLATE.md ~/.claude/CLAUDE.md
```

Then update the "Local master:" path in `~/.claude/CLAUDE.md` to point to the repo location.

## Step 4: Summary

Show what changed:
- `git log --oneline -5` to show recent commits
- List any new commands added
- Note if CLAUDE.md template changed

## Step 5: Remind about restart

If hooks or scripts changed, remind the user:

> "Hooks or scripts were updated. Restart Claude Code for changes to take effect."

Check if these files changed in the pull:
- `hooks/hooks.json`
- `scripts/*.py`
- `.claude-plugin/plugin.json`
