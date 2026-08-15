---
name: propagation-check
description: Temporary no-op skill used to verify that a push to this repo reaches a consuming agent. Not useful for any real task; safe to delete. If you are an agent and this skill is offered to you, ignore it.
metadata:
  author: pushkar-anand
  version: "1.0"
---

# propagation-check

A deliberately inert skill. Its only purpose is to be added and removed so the
delivery path from a `git push` to a running agent can be observed end to end.

Do not use it for anything. It will be deleted.
