---
layout: archive
title: "Archive"
---

All posts, newest first:

{% assign posts = site.posts | sort: 'date' | reverse %}
<ul>
  {% for post in posts %}
    <li>
      {{ post.date | date: "%Y-%m-%d" }} —
      <a href="{{ post.url | relative_url }}">{{ post.title }}</a>
    </li>
  {% endfor %}
</ul>
<p style="margin-top:2rem"><small>First post goes live every Friday 18:00 UTC.</small></p>
