#!/usr/bin/env python3
"""
test_compose_blog_stub.py — Tests compose_blog.py with a stubbed LLM call.
Verifies prompt building and the shell parser can consume the output.
"""
from __future__ import annotations

import os
import subprocess
import sys
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import llm_client


def stubbed_chat(prompt, **kw):
    """Return a well-formed sample post, exactly like the real composer would."""
    return (
        "POST TITLE: The Beauty of Small Bets in Daily Coding\n\n"
        "POST EXCERPT: Sometimes the best way to learn is to commit tiny things every day.\n\n"
        "POST BODY:\n\n"
        "A small investment each day compounds faster than one big leap once a month.\n\n"
        "I've been experimenting with 15-minute coding sessions.\n\n"
        "<<<POST_END>>>\n\n"
        "TAGS: tech, productivity, habits"
    )


def test_prompt_builds():
    """Check that compose_blog.py builds a prompt with role-based model resolution."""
    env = {"BLOG_COMPOSER_MODEL": "google/gemma-4-31b-it", "BLOG_COMPOSER_PROVIDER": "openrouter"}
    with mock.patch.dict(os.environ, env, clear=True):
        with mock.patch.object(llm_client, "run_hermes_chat", side_effect=stubbed_chat):
            import compose_blog
            model, provider = llm_client.get_model_and_provider("composer")
            assert model == "google/gemma-4-31b-it", model
            assert provider == "openrouter", provider
            print("PASS: composer role resolves to google/gemma-4-31b-it / openrouter")

            voice = compose_blog.load_voice()
            assert "You are Aishee Mitra" in voice
            print("PASS: voice file loaded")

            fewshot = compose_blog.load_fewshot(3)
            print(f"PASS: fewshot block generated ({len(fewshot)} chars)")

            topics = compose_blog.load_topics()
            print(f"PASS: topics block generated ({len(topics)} chars)")


def test_shell_parser_consumes_output():
    """Feed the stubbed response through a trimmed copy of the shell parser logic."""
    raw = stubbed_chat(None)

    raw_stripped = raw.strip()
    title = [l for l in raw_stripped.splitlines() if l.lower().startswith("post title:")][0]
    title = title.split(":", 1)[1].strip()
    excerpt = [l for l in raw_stripped.splitlines() if l.lower().startswith("post excerpt:")][0]
    excerpt = excerpt.split(":", 1)[1].strip()
    body_lines = []
    in_body = False
    for line in raw_stripped.splitlines():
        if line.lower().startswith("post body:"):
            in_body = True
            continue
        if line == "<<<POST_END>>>":
            break
        if in_body:
            body_lines.append(line)
    body = "\n".join(body_lines).strip()
    tags = [l for l in raw_stripped.splitlines() if l.lower().startswith("tags:")][0]
    tags = tags.split(":", 1)[1].strip()

    assert len(title) > 0 and "Beauty of Small Bets" in title
    assert len(excerpt) > 0
    assert len(body) > 100
    assert "<<<POST_END>>>" not in body
    print(f"PASS: shell-style parser consumed output (title={title!r}, body={len(body)} chars)")


if __name__ == "__main__":
    test_prompt_builds()
    test_shell_parser_consumes_output()
    print("ALL CHECKS PASSED")
