# .skills

Reusable [Agent Skills](https://agentskills.io) shared across agents and machines.

Skills use the portable core of the spec — `SKILL.md` with `name` and
`description`, plain Markdown body, supporting files under `scripts/` and
`references/` — so the same directory works in Hermes, Claude Code, Codex and
anything else that reads the format.

## Layout

```
skills/<skill-name>/
├── SKILL.md
├── scripts/
└── references/
```

One level, deliberately. Every consumer assumes it: a Hermes tap defaults to
`skills/` and flattens to `skills/<name>/` on install, discarding any category
directory; Claude Code scans a plugin's `skills/<name>/SKILL.md`; Codex scans
`~/.agents/skills/<name>/`. A category directory survives in none of them.

Grouping lives in the name instead — e.g. a `foo-read`/`foo-create` family
sorts together and stays unique once installed alongside skills from other
taps. That also satisfies the spec rule that `name` must equal the parent
directory name, which a nested `security/foo/create` would break by making the
skill globally named `create`.

## Skills

None right now — the `1pass-read`/`1pass-create`/`1pass-2fa` family that used
to live here is gone, replaced by Hermes' own built-in credential vault
(1Password as an optional read-through backend). See
[homelab-infrastructure's hermes README](https://github.com/pushkar-anand/homelab-infrastructure/blob/main/services/ai/hermes/README.md#credential-vault)
for that setup.

A convention worth keeping for whatever lands here next: if a skill family
splits along a read/write (or similarly privileged) boundary, name it that way
(`foo-read`, `foo-create`) so each installs independently — a profile that
should never write gets `foo-read` alone and has no script capable of it.
Default to never printing a credential outright; make a program consume it via
environment or stdin, and require an explicit flag (with a warning) for the one
case where the model has to type it into a form. If more than one skill in a
family needs the same helper code, give each its own copy of
`scripts/lib.sh` rather than a shared path outside `skills/<name>/` — see
Layout above — and run `tools/check-lib-sync.sh` to keep the copies identical.

## Using these with Hermes

Add the tap once, then install per agent profile:

```bash
hermes skills tap add pushkar-anand/.skills
hermes skills search <name>
hermes skills install <name>
```

Install per skill rather than per tap — that's the only way a read/write split
(see Skills above) means anything.

A single skill can also be installed without subscribing to the tap:

```bash
hermes skills install pushkar-anand/.skills/skills/<name>
```

Skills install under the profile's `HERMES_HOME/skills`, which lives in the
gateway. Where the terminal sandbox is a separate container, the `scripts/` in a
skill are executed there and not in the gateway — so the skills directory has to
be mounted into the sandbox at the same path, or every script reference resolves
to nothing while `SKILL.md` itself loads fine. Check with `ls` inside the sandbox
before trusting a freshly installed skill.

If shared skills are mounted rather than installed, mount them **read-only**:
Hermes agents can author skills through the `skill_manage` tool, and a writable
shared directory lets one agent edit a skill every other agent then loads.

## Using these elsewhere

- **Codex / Cursor / OpenCode** — clone to `~/.agents/skills`; it is already
  their user-level skills path.
- **Claude Code** — symlink individual skills into `~/.claude/skills/<name>`,
  or install them as plugins from a marketplace manifest.

## Adding a skill

1. `skills/<name>/SKILL.md`, with `name:` matching the directory. One level —
   see Layout above; a category directory survives in no consumer.
2. Keep `SKILL.md` under ~500 lines; push detail into `references/`.
3. Write the `description` for *retrieval* — say what it does and when to use
   it, with the words someone would actually use. It is the only part loaded
   until the skill fires.
4. `tools/validate.sh` before committing.
