---
layout: default
title: "TGIF Musings — Archive"
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
