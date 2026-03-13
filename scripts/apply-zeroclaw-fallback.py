#!/usr/bin/env python3
"""
Apply ZeroClaw provider fallback for Z.AI 429/500 responses.

When Z.AI returns rate limit (429) or server error (500), ZeroClaw falls back to
Anthropic Claude or OpenAI GPT-4. Native config support - no proxy needed.

Required env vars for fallback (at least one):
  ANTHROPIC_API_KEY  - Anthropic API key (preferred)
  OPENAI_API_KEY     - OpenAI API key (alternative)

Usage:
  python3 scripts/apply-zeroclaw-fallback.py
  ZEROCLAW_CONFIG=~/.zeroclaw/config.toml python3 scripts/apply-zeroclaw-fallback.py

Idempotent: safe to run multiple times.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


DEFAULT_CONFIG = Path.home() / ".zeroclaw" / "config.toml"
MODEL_FALLBACKS = {
    "glm-5": ["anthropic/claude-3-5-sonnet-20241022"],
    "glm-4.7": ["anthropic/claude-3-5-sonnet-20241022"],
    "glm-4": ["anthropic/claude-3-5-sonnet-20241022"],
}


def get_config_path() -> Path:
    """Resolve config path from env or default."""
    path = os.environ.get("ZEROCLAW_CONFIG")
    if path:
        return Path(path).expanduser()
    return DEFAULT_CONFIG


def has_fallback_configured(content: str) -> bool:
    """Check if fallback is already applied."""
    # fallback_providers not empty
    if re.search(r'fallback_providers\s*=\s*\[\s*"[^"]+"', content):
        return True
    return False


def has_model_fallbacks(content: str) -> bool:
    """Check if model_fallbacks section exists."""
    return "[reliability.model_fallbacks]" in content


def apply_fallback_providers(content: str) -> str:
    """Replace empty fallback_providers with anthropic."""
    pattern = r'(fallback_providers\s*=\s*)\[\s*\]'
    replacement = r'\1["anthropic"]'
    return re.sub(pattern, replacement, content, count=1)


def build_model_fallbacks_block() -> str:
    """Build TOML block for [reliability.model_fallbacks]."""
    lines = ["[reliability.model_fallbacks]"]
    for model, fallbacks in MODEL_FALLBACKS.items():
        fallback_str = ", ".join(f'"{f}"' for f in fallbacks)
        lines.append(f'"{model}" = [{fallback_str}]')
    return "\n".join(lines) + "\n"


def apply_model_fallbacks(content: str) -> str:
    """Add [reliability.model_fallbacks] section if not present."""
    if has_model_fallbacks(content):
        return content
    block = "\n" + build_model_fallbacks_block()
    return content.replace("\n[cron]", block + "\n[cron]")


def main() -> int:
    config_path = get_config_path()
    if not config_path.exists():
        print(f"Error: Config not found: {config_path}", file=sys.stderr)
        print("Set ZEROCLAW_CONFIG or ensure ~/.zeroclaw/config.toml exists.", file=sys.stderr)
        return 1

    content = config_path.read_text()

    # Idempotent: skip if already configured
    if has_fallback_configured(content) and has_model_fallbacks(content):
        print(f"Fallback already configured in {config_path}. Nothing to do.")
        return 0

    # Apply fallback_providers (empty -> ["anthropic"])
    content = apply_fallback_providers(content)
    if not has_fallback_configured(content):
        content = re.sub(
            r'fallback_providers\s*=\s*\[\s*\]',
            'fallback_providers = ["anthropic"]',
            content,
            count=1,
        )

    # Apply model_fallbacks if not present
    content = apply_model_fallbacks(content)

    config_path.write_text(content)
    print(f"Updated {config_path}")
    print("  - fallback_providers = [\"anthropic\"]")
    print("  - model_fallbacks: glm-5, glm-4.7, glm-4 -> anthropic/claude-3-5-sonnet")
    print("")
    print("Required: Set ANTHROPIC_API_KEY for fallback to work.")
    print("Optional: Set OPENAI_API_KEY to add OpenAI as secondary fallback.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
