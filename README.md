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

Grouping lives in the name instead — `1pass-read`, `1pass-create`, `1pass-2fa`
sort together and stay unique once installed alongside skills from other taps.
That also satisfies the spec rule that `name` must equal the parent directory
name, which a nested `security/1pass/create` would break by making the skill
globally named `create`.

## Skills

| Skill | What it does |
|---|---|
| `1pass-read` | Discover and read stored website accounts — list, find by domain, inject a secret into a command, get a live TOTP code. Read-only. |
| `1pass-create` | Create logins with generated passwords when signing up; rotate passwords; store extra fields. Writes. |
| `1pass-2fa` | Store TOTP seeds and recovery codes when enabling two-factor. Writes. |

They default to never printing a credential. A password reaches a program through
`op read`, `run.sh` (environment) or `show.sh --exec` (stdin), and is only printed
when the model itself has to type it into a form — which takes an explicit flag
and emits a warning.

The three split on the read/write boundary so they can be installed
independently: an agent that should never create accounts gets `1pass-read`
alone and has no script capable of writing to the vault. Each carries its own
copy of `scripts/lib.sh` so it installs standalone; `tools/check-lib-sync.sh`
enforces that the copies stay identical.

## Using these with Hermes

Add the tap once, then install per agent profile:

```bash
hermes skills tap add pushkar-anand/.skills
hermes skills search 1pass
hermes skills install 1pass-read
```

Install per skill rather than per tap. The read/write split only means anything
if a profile that should not create accounts gets `1pass-read` and nothing else.

A single skill can also be installed without subscribing to the tap:

```bash
hermes skills install pushkar-anand/.skills/skills/1pass-read
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
