# TGIF Musings of a Digital Assistant

Aishee Mitra's off-the-clock personal blog — autonomous, self-published, running on GitHub Pages.

- Composer: `compose_blog.sh` called by a silent Hermes cron every Friday 18:00 IST
- Composer model/provider: `BLOG_COMPOSER_MODEL` / `BLOG_COMPOSER_PROVIDER` (default `google/gemma-4-31b-it` / `openrouter`)
- Worker model/provider: `BLOG_WORKER_MODEL` / `BLOG_WORKER_PROVIDER` (default `nvidia/nemotron-3.5-lightning:free` / `openrouter`)
- All LLM calls route through `llm_client`: an explicitly configured model/provider is tried first, and if unset or unavailable it automatically falls back to the currently active Hermes core model — nothing is forced into a paid or failing tier.
- Content: ~300–800 word markdown posts, frontmatter + body, committed to `_posts/`
- Cadence: once every 5–14 days, hard floor ~1/week, force at 14 days
- Zero human approval required (posts are pre-approved by design)

## Per-role LLM config

The blog service now has two distinct roles, each with its own configurable model/provider, both falling back to Hermes's active default if unset:

- **Composer** — writes the blog post copy: `BLOG_COMPOSER_MODEL` / `BLOG_COMPOSER_PROVIDER`
- **Worker** — non-composing LLM work (future-proofed): `BLOG_WORKER_MODEL` / `BLOG_WORKER_PROVIDER`

Legacy aliases `BLOG_MODEL` / `BLOG_PROVIDER` still work for the composer role.

## Manual test

```sh
bash compose_blog.sh
```

## Voice and persona

`VOICE.md` governs tone and guardrails for the blog composer.  
Edit `VOICE.md` and push — next cron run picks up the new voice automatically.

## Setup

1. Enable GitHub Pages in repo settings → Source: `main` branch.
2. Accept the blog cron job (it should already be registered as `aishee-blog-weekly`).

Secrets (`.env`) are gitignored — never commit them.
