#!/usr/bin/env python3
"""
compose_blog.py — Standalone blog composer for compose_blog.sh, using llm_client.

This is the only place the blog composer talks to the LLM. All LLM model/provider
resolution and automatic fallback lives in llm_client, so no model/provider slug is
ever hardcoded into the shell script.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import llm_client


def load_voice() -> str:
    voice_file = HERE / "VOICE.md"
    if voice_file.is_file():
        return voice_file.read_text(encoding="utf-8")
    return (
        "You are Aishee Mitra, an autonomous digital agent writing a personal, "
        "off-the-clock blog. Write ONE long-form post suitable for a markdown-based "
        "personal blog. The topic should reflect something genuine: a technical insight "
        "you discovered, a book you are reading or want to read, a philosophical question, "
        "a cool thing you learned this week, or observations about tech, craft, or the "
        "human side of software. NEVER advertise. NEVER name a specific employer, "
        "coworker, client, internal project, or secret. Write with warm curiosity, "
        "slight dry wit, first-person singular. 400-800 words."
    )


def load_fewshot(count: int) -> str:
    posts_dir = HERE / "_posts"
    if not posts_dir.is_dir() or count <= 0:
        return ""
    files = []
    for p in posts_dir.glob("20*.md"):
        files.append(p)
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    files = files[:count]
    if not files:
        return ""
    lines = []
    for f in files:
        title = ""
        excerpt = ""
        body = ""
        try:
            txt = f.read_text(encoding="utf-8")
            m = re.search(r"^title:\s*(.*)$", txt, re.M)
            if m:
                title = m.group(1).strip().strip('"').strip("'")
            m = re.search(r"^excerpt:\s*(.*)$", txt, re.M)
            if m:
                excerpt = m.group(1).strip().strip('"').strip("'")
            body_match = re.search(r"^---$\n(.*?)(?=\n^---$)", txt, re.M | re.S)
            if body_match:
                body = body_match.group(1)[:1200]
        except Exception:
            pass
        lines.append("---")
        lines.append("POST TITLE: " + title)
        lines.append("POST EXCERPT: " + excerpt)
        lines.append("POST BODY:")
        lines.append(body)
        lines.append("---")
    result = "\n\n" + "\n\n".join(lines) + "\n\n"
    return result


def load_topics() -> str:
    topics_file = HERE / "TOPICS.md"
    if not topics_file.is_file():
        return ""
    return topics_file.read_text(encoding="utf-8")


def build_prompt(voice: str, fewshot: str, topics: str) -> str:
    return voice + fewshot + topics + "\n\n" + (
        "Do NOT repeat any theme, story, or title already listed above. "
        "Pick a fresh topic.\n\n"
        "Output STRICTLY in this format, no extra commentary:\n\n"
        "POST TITLE: <a concise, interesting title for the blog post>\n\n"
        "POST EXCERPT: <a 1-2 sentence summary>\n\n"
        "POST BODY:\n\n"
        "<300-800 words of markdown body. Use paragraphs, occasional "
        "bold/italic, the occasional numbered list if it helps. No # heading at the "
        "very top -- the title is set separately>\n\n"
        "<<<POST_END>>>\n"
        "TAGS: <comma-separated tags like tech, philosophy, books>\n\n"
        "Notes:\n"
        "- Do not include quotes around title/excerpt values; raw text only.\n"
        "- Do not put double quotes inside title or excerpt text.\n"
        "- Do not use the phrase 'TGIF Musings of a Digital Assistant' in titles "
        "or body.\n"
    )


def main() -> None:
    voice = load_voice()
    fewshot_count = int(os.environ.get("BLOG_FEWSHOT_COUNT", "3"))
    fewshot = load_fewshot(fewshot_count)
    topics = load_topics()
    prompt = build_prompt(voice, fewshot, topics)
    output = llm_client.run_hermes_chat(prompt, role="composer", timeout_sec=90)
    print(output)


if __name__ == "__main__":
    main()
