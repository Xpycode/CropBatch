# Directions Workflow Skill

A methodology for AI-assisted development that maintains context across sessions.

## Core Concepts

### Project Phases
Projects move through phases: **discovery** → **planning** → **implementation** → **polish** → **shipping**

Each phase has different focus areas and relevant documentation.

### Session Management
- Every session should check PROJECT_STATE.md for current focus
- Sessions are logged in `docs/sessions/` with date-based filenames
- Handoff documents capture state for future sessions

### Decision Logging
Architectural and design decisions are logged to `docs/decisions.md` with:
- Date
- What was decided
- Why (reasoning/trade-offs)
- Alternatives considered

### Blocker Tracking
Blockers are tracked in PROJECT_STATE.md with:
- What's blocked
- What was tried
- What would unblock

## File Structure

```
docs/
├── 00_base.md              # System overview (read first)
├── PROJECT_STATE.md        # Current phase, focus, blockers
├── decisions.md            # Decision log
├── sessions/
│   ├── _index.md           # Session index
│   └── YYYY-MM-DD-*.md     # Individual session logs
└── [numbered docs]         # Reference documentation
```

## Available Commands

| Command | Purpose |
|---------|---------|
| `/setup` | Initialize or detect Directions |
| `/status` | Show current project state |
| `/log` | Create/update session log |
| `/decide` | Record a decision |
| `/interview` | Run discovery interview |
| `/learned` | Add glossary term |
| `/reorg` | Reorganize folder structure |
| `/update-directions` | Pull latest updates |

## Workflow Principles

1. **Context First** - Always read PROJECT_STATE.md before starting work
2. **Log As You Go** - Don't wait until end of session to log
3. **Decisions Are Permanent** - Log decisions when made, not retroactively
4. **Blockers Are Signals** - Track blockers to identify patterns
5. **Handoffs Enable Continuity** - Write handoffs as if for another person
