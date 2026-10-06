"""
llm_client.py — Central helper for invoking hermes chat with model fallback.

Config precedence:
  1. Explicit caller arguments (model, provider)
  2. Target role environment variables (e.g. BLOG_COMPOSER_MODEL /
     BLOG_COMPOSER_PROVIDER or BLOG_WORKER_MODEL / BLOG_WORKER_PROVIDER)
  3. Legacy environment variables (BLOG_MODEL / BLOG_PROVIDER)
  4. Default: omit -m / --provider flags so Hermes uses its current active
     core model and provider.

If a specified model fails (non-zero returncode or timeout), automatically retries
without model/provider flags to fall back safely to the active Hermes default model.
"""
from __future__ import annotations

import os
import subprocess
import sys
from typing import Sequence


def get_model_and_provider(role: str = "composer") -> tuple[str | None, str | None]:
    """
    Resolve (model, provider) for a given role ('composer' or 'worker').
    Returns (None, None) if unset, which signals using the Hermes default model.
    """
    role_upper = role.upper()
    model = os.environ.get(f"BLOG_{role_upper}_MODEL")
    provider = os.environ.get(f"BLOG_{role_upper}_PROVIDER")

    if not model and role == "composer":
        model = os.environ.get("BLOG_MODEL")
    if not provider and role == "composer":
        provider = os.environ.get("BLOG_PROVIDER")

    if not model and role == "worker":
        model = "nvidia/nemotron-3.5-lightning:free"
    if not provider and role == "worker":
        provider = "openrouter"

    model = model.strip() if model and model.strip() else None
    provider = provider.strip() if provider and provider.strip() else None
    return model, provider


def run_hermes_chat(
    prompt: str,
    *,
    role: str = "composer",
    model: str | None = None,
    provider: str | None = None,
    timeout_sec: int = 90,
    extra_args: Sequence[str] | None = None,
) -> str:
    """
    Run `hermes chat -Q -q <prompt>`.
    First tries with configured model/provider.
    If that fails or produces no output, retries with Hermes default model/provider.
    """
    resolved_model, resolved_provider = get_model_and_provider(role)
    effective_model = model or resolved_model
    effective_provider = provider or resolved_provider

    def _execute(use_model: str | None, use_provider: str | None) -> str:
        cmd = ["hermes", "chat", "-Q"]
        if use_model:
            cmd.extend(["-m", use_model])
        if use_provider:
            cmd.extend(["--provider", use_provider])
        if extra_args:
            cmd.extend(extra_args)
        cmd.extend(["-q", prompt])

        res = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
        if res.returncode != 0:
            err_msg = res.stderr.strip() or f"exit code {res.returncode}"
            raise RuntimeError(f"hermes chat returned {err_msg}")
        return res.stdout.strip()

    if effective_model:
        try:
            out = _execute(effective_model, effective_provider)
            if out:
                return out
            print(
                f"[llm_client] Configured composer model '{effective_model}' returned empty output, "
                "attempting fallback to Hermes default...",
                file=sys.stderr,
            )
        except Exception as e:
            print(
                f"[llm_client] Configured composer model '{effective_model}' failed ({e}), "
                "falling back to Hermes default...",
                file=sys.stderr,
            )

    # Fallback: run hermes chat with default model
    return _execute(None, None)
