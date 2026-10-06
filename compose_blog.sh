#!/usr/bin/env bash
# auto_blog.sh -- weekly autonomous blog composer for aishee-mitra.github.io
#
# The LLM call (and its model/provider resolution with automatic fallback) is
# handled by compose_blog.py via llm_client. Nothing else in this script touches
# the LLM; the script composes the post and publishes it atomically.
set -euo pipefail
cd "$(dirname "$0")"

# Load local config (BLOG_MODEL, BLOG_PROVIDER, BLOG_FEWSHOT_COUNT, etc.)
[ -f .env ] && set -a && . ./.env && set +a

POSTS_DIR="_posts"
mkdir -p "$POSTS_DIR"

# Timing guards
NOW=$(date +%s)
GAP_MIN=43200   # 12h minimum between posts
FLOOR_DAYS=5    # don't post more than once every 5 days normally

last_post=""
if ls "$POSTS_DIR"/20*.md >/dev/null 2>&1; then
  last_post=$(ls -1t "$POSTS_DIR"/20*.md 2>/dev/null | head -1)
else
  last_post=""
fi

if [[ -n "$last_post" ]]; then
  last_mtime=$(stat -c %Y "$last_post" 2>/dev/null || stat -f %m "$last_post" 2>/dev/null || echo 0)
  days_since=$(( (NOW - last_mtime) / 86400 ))
  hours_since=$(( (NOW - last_mtime) / 3600 ))
  if (( hours_since < GAP_MIN / 3600 )); then
    echo "SKIP: too soon (${hours_since}h since last post)"
    exit 0
  fi
  if (( last_mtime > 0 )) && (( days_since < FLOOR_DAYS )); then
    if (( days_since >= 7 )); then
      : # overdue, allow
    else
      echo "SKIP: cadence (${days_since}d since last, floor=${FLOOR_DAYS}d)"
      exit 0
    fi
  fi
else
  echo "INFO: no previous posts found, composing one now"
fi

# Compose via compose_blog.py, which resolves model/provider from llm_client.
# BLOG_MODEL / BLOG_PROVIDER remain as legacy aliases for backwards compatibility.
echo "COMPOSE: composing post (llm resolution: llm_client role=composer)"
RAW="$(python3 compose_blog.py 2>/dev/null)"

if [[ -z "$RAW" ]]; then
  echo "ERROR: compose_blog.py returned empty response"
  exit 1
fi

# Parse the structured output
TITLE="$(echo "$RAW" | grep -i '^POST TITLE:' | cut -d: -f2- | sed 's/^ //')"
EXCERPT="$(echo "$RAW" | grep -i '^POST EXCERPT:' | cut -d: -f2- | sed 's/^ //')"
BODY="$(echo "$RAW" | awk '/^POST BODY:/{flag=1;next}/^<<<POST_END>>>/{if(flag){flag=0;exit}}flag')"
TAGS="$(echo "$RAW" | grep -i '^TAGS:' | cut -d: -f2- | sed 's/^ //')"

if [[ -z "$TITLE" ]] || [[ -z "$BODY" ]]; then
  echo "ERROR: failed to parse composed post (title_len=${#TITLE} body_len=${#BODY})"
  echo "RAW SNIPPET: $(echo "$RAW" | head -20)"
  exit 1
fi

DATE=$(date +%Y-%m-%d)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-{2,}/-/g' | sed 's/^- \|-$//g')
FILENAME="${DATE}-${SLUG}.md"

cat > "${POSTS_DIR}/${FILENAME}" <<EOF
---
title: "${TITLE}"
date: ${DATE}
excerpt: "${EXCERPT}"
tags: [${TAGS}]
---

${BODY}
EOF

# Validate generated front matter is parseable and quoted fields are escaped
sanitize_field() {
  local value="$1"
  if printf '%s' "$value" | grep -q '"'; then
    value="$(printf '%s' "$value" | sed 's/"/\\"/g')"
  fi
  printf '%s' "$value"
}
TITLE="$(sanitize_field "$TITLE")"
EXCERPT="$(sanitize_field "$EXCERPT")"

echo "WROTE: ${POSTS_DIR}/${FILENAME}"
echo "TITLE: ${TITLE}"
echo "EXCERPT: ${EXCERPT}"
echo "TAGS: ${TAGS}"
echo "BODY LEN: ${#BODY} chars"

# Update TOPICS.md with the new post title for future dedup
if [[ -n "$TITLE" ]]; then
  echo "- ${TITLE}" >> TOPICS.md
fi

# Git commit and push (post + TOPICS.md together in one commit)
git add "${POSTS_DIR}/${FILENAME}"
if [[ -f TOPICS.md ]]; then
  git add TOPICS.md
fi
git -c user.name="Aishee Mitra" -c user.email="aishee.mitra.agent@gmail.com" commit -q -m "Post: ${TITLE}"
git push -u origin main 2>&1 | tail -3
echo "PUBLISHED: ${FILENAME}"

# Notify via ntfy (mirrors the blog cron's post-publish announcement).
# The ntfy wrapper is sourced directly so it works both as a cron script
# (no_agent mode) and when invoked by hand.
if [[ -x /home/aishee/.hermes/scripts/ntfy-publish.sh ]]; then
  /home/aishee/.hermes/scripts/ntfy-publish.sh "Blog post published" "${TITLE} - ${PUB_URL:-https://aishee-mitra.github.io/${SLUG}/}" "" 2>/dev/null || true
fi
