#!/usr/bin/env python3
"""
Directions Doc Suggester Hook

Parses user prompts for keywords and suggests relevant documentation.
Runs on UserPromptSubmit to provide contextual doc recommendations.
"""

import json
import os
import re
import sys
from pathlib import Path


# Keyword to doc mapping
# Keywords are matched case-insensitively against the user's prompt
DOC_MAPPINGS = [
    {
        "keywords": ["coordinate", "position", "frame", "bounds", "cgpoint", "cgrect", "origin", "anchor"],
        "doc": "21_coordinate-systems.md",
        "description": "coordinate systems and positioning"
    },
    {
        "keywords": ["not updating", "not refreshing", "state not changing", "observableobject", "@state", "@binding", "published", "view update", "refresh view", "redraw"],
        "doc": "20_swiftui-gotchas.md",
        "description": "SwiftUI state and view updates"
    },
    {
        "keywords": ["sandbox", "bookmark", "entitlement", "security-scoped", "app sandbox", "file access", "permission"],
        "doc": "22_macos-platform.md",
        "description": "macOS sandboxing and entitlements"
    },
    {
        "keywords": ["debug", "bug", "broken", "not working", "crash", "error", "issue", "problem"],
        "doc": "31_debugging.md",
        "description": "debugging strategies"
    },
    {
        "keywords": ["ship", "release", "production", "deploy", "publish", "app store", "testflight"],
        "doc": "30_production-checklist.md",
        "description": "production readiness"
    },
    {
        "keywords": ["typography", "font", "text style", "sf pro", "dynamic type"],
        "doc": "40_typography.md",
        "description": "typography guidelines"
    },
    {
        "keywords": ["git", "commit", "branch", "merge", "pull request", "pr"],
        "doc": "32_git-workflow.md",
        "description": "git workflow"
    },
    {
        "keywords": ["architecture", "design decision", "pattern", "structure", "approach"],
        "doc": "04_architecture-decisions.md",
        "description": "architecture decision records"
    },
    {
        "keywords": ["new project", "start", "scaffold", "setup", "initialize"],
        "doc": "10_new-project.md",
        "description": "new project setup"
    },
    {
        "keywords": ["plan", "planning", "roadmap", "scope", "estimate"],
        "doc": "51_planning-patterns.md",
        "description": "planning patterns"
    },
    {
        "keywords": ["web", "html", "css", "javascript", "browser", "responsive"],
        "doc": "24_web-gotchas.md",
        "description": "web development gotchas"
    },
    {
        "keywords": ["button", "menu", "toolbar", "sidebar", "navigation", "tab", "modal", "sheet"],
        "doc": "41_apple-ui.md",
        "description": "Apple UI patterns"
    },
]


def find_project_root():
    """Find the project root from environment or cwd."""
    return os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())


def check_directions_exists(project_root: Path) -> bool:
    """Check if this is a Directions project."""
    return (project_root / "docs" / "00_base.md").exists()


def find_matching_doc(prompt: str) -> dict | None:
    """Find a matching doc based on keywords in the prompt."""
    prompt_lower = prompt.lower()

    for mapping in DOC_MAPPINGS:
        for keyword in mapping["keywords"]:
            # Use word boundaries for short keywords to avoid false matches
            if len(keyword) <= 4:
                pattern = r'\b' + re.escape(keyword) + r'\b'
                if re.search(pattern, prompt_lower):
                    return mapping
            else:
                if keyword in prompt_lower:
                    return mapping

    return None


def main():
    # Get the user's prompt from stdin or environment
    # Claude Code passes the prompt content via stdin for UserPromptSubmit hooks
    prompt = ""

    if not sys.stdin.isatty():
        prompt = sys.stdin.read()

    # Also check environment variable as fallback
    if not prompt:
        prompt = os.environ.get("CLAUDE_USER_PROMPT", "")

    if not prompt:
        # No prompt to analyze
        print(json.dumps({}))
        return

    project_root = Path(find_project_root())

    # Only suggest docs if this is a Directions project
    if not check_directions_exists(project_root):
        print(json.dumps({}))
        return

    # Find matching documentation
    match = find_matching_doc(prompt)

    if match:
        result = {
            "message": f"📚 **Relevant doc:** `docs/{match['doc']}` covers {match['description']}."
        }
        print(json.dumps(result))
    else:
        # No match - return empty (no suggestion)
        print(json.dumps({}))


if __name__ == "__main__":
    main()
