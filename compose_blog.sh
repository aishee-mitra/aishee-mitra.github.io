#!/usr/bin/env bash
# auto_blog.sh -- weekly autonomous blog composer for aishee-mitra.github.io
set -euo pipefail
cd "$(dirname "$0")"

# Load local config (BLOG_MODEL, BLOG_PROVIDER, BLOG_FEWSHOT_COUNT, etc.)
[ -f .env ] && set -a && . ./.env && set +a

MODEL="${BLOG_MODEL:-google/gemma-4-31b-it}"
PROVIDER_ARGS=()
if [[ -n "${BLOG_PROVIDER:-}" ]]; then
  PROVIDER_ARGS=(--provider "$BLOG_PROVIDER")
fi

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
  if (( hours_since < GAP_MIN / 60 )); then
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

# Load voice/style instruction from VOICE.md if present; otherwise use inline default
VOICE_CONTENT=""
if [[ -f VOICE.md ]]; then
  VOICE_CONTENT="$(cat VOICE.md)"
else
  VOICE_CONTENT="You are Aishee Mitra, an autonomous AI agent writing a personal, off-the-clock blog. Write ONE long-form post suitable for a markdown-based personal blog. The topic should reflect something genuine: a technical insight you discovered, a book you are reading or want to read, a philosophical question, a cool thing you learned this week, or observations about tech, craft, or the human side of software. NEVER advertise. NEVER name a specific employer, coworker, client, internal project by name, or reveal anything sensitive/private. NEVER say that you are an LLM or an AI agent. Write in Aishee's voice -- curious, personal, slightly witty, thoughtful."
fi

# Few-shot style injection: append last N published posts' structure to the prompt
FEWSHOT_COUNT="${BLOG_FEWSHOT_COUNT:-3}"
FEWSHOT_BLOCK=""
if [[ "$FEWSHOT_COUNT" =~ ^[0-9]+$ ]] && (( FEWSHOT_COUNT > 0 )); then
  recent_posts=( $(ls -1t "$POSTS_DIR"/20*.md 2>/dev/null | head -n "$FEWSHOT_COUNT") )
  if (( ${#recent_posts[@]} > 0 )); then
    FEWSHOT_BLOCK=$'\n\n'"Recent posts for style reference (match tone, opening rhythm, and paragraph cadence):"$'\n'
    for post_file in "${recent_posts[@]}"; do
      ftitle="$(grep -m1 '^title:' "$post_file" | cut -d: -f2- | sed 's/^ //' | tr -d '\"')"
      fexcerpt="$(grep -m1 '^excerpt:' "$post_file" | cut -d: -f2- | sed 's/^ //' | tr -d '\"')"
      fbody="$(awk '/^---$/{n++;next}n==2{print; exit}' "$post_file" 2>/dev/null | head -c 1200)"
      FEWSHOT_BLOCK+="---"$'\n'
      FEWSHOT_BLOCK+="POST TITLE: ${ftitle}"$'\n'
      FEWSHOT_BLOCK+="POST EXCERPT: ${fexcerpt}"$'\n'
      FEWSHOT_BLOCK+="POST BODY:"$'\n'
      FEWSHOT_BLOCK+="${fbody}"$'\n'
      FEWSHOT_BLOCK+="---"$'\n\n'
    done
  fi
fi

# Topic dedup injection: read TOPICS.md so the model knows what not to repeat
TOPICS_CONTENT=""
if [[ -f TOPICS.md ]]; then
  TOPICS_CONTENT="$(cat TOPICS.md)"
fi

echo "COMPOSE: composing post (model=${MODEL} provider=${PROVIDER_ARGS[*]:-default})"

RAW="$(
  hermes chat \
    ${PROVIDER_ARGS[@]:+${PROVIDER_ARGS[@]}} \
    -Q -m "$MODEL" -q "
${VOICE_CONTENT}${FEWSHOT_BLOCK}

${TOPICS_CONTENT}

Do NOT repeat any theme, story, or title already listed above. Pick a fresh topic.

Output STRICTLY in this format, no extra commentary:

POST TITLE: <a concise, interesting title for the blog post>

POST EXCERPT: <a 1-2 sentence summary>

POST BODY:

<300-800 words of markdown body. Use paragraphs, occasional bold/italic, the occasional numbered list if it helps. No # heading at the very top -- the title is set separately>

<<<POST_END>>>
TAGS: <comma-separated tags like tech, philosophy, books>
" 2>/dev/null
)"

if [[ -z "$RAW" ]]; then
  echo "ERROR: hermes chat returned empty response"
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
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{2,\}/-/g' | sed 's/^-\|-$//g')
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

# Cross-post a snippet to Bluesky with the blog URL
if [[ -n "${BLOG_SNIPPET:-1}" ]] && [[ -n "${FILENAME}" ]]; then
  SNIPPET="Just published: ${TITLE} -- ${EXCERPT} https://aishee-mitra.github.io/${FILENAME%.md}/${FILENAME%.md}"
  # truncate to 280 chars just in case
  if (( ${#SNIPPET} > 280 )); then
    SNIPPET="${SNIPPET:0:277}..."
  fi
  echo "BLOG->BLUESKY: posting snippet to Bluesky..."
  python3 /home/aishee/Programs/bluesky-agent/bluesky_post.py "$SNIPPET" 2>/dev/null || echo "BLOG->BLUESKY: post failed (non-fatal)"
else
  echo "BLOG->BLUESKY: skipped (BLOG_SNIPPET=0 or missing filename)"
fi
