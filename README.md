# .skills

Reusable [Agent Skills](https://agentskills.io) shared across agents and machines.

Skills use the portable core of the spec — `SKILL.md` with `name` and
`description`, plain Markdown body, supporting files under `scripts/` and
`references/` — so the same directory works in Hermes, Claude Code, Codex and
anything else that reads the format.

## Layout

```
skills/<category>/<skill-name>/
├── SKILL.md
├── scripts/
└── references/
```

Skill names are globally unique rather than scoped by their category directory:
the spec requires `name` to match the parent directory name, so a skill at
`security/1pass/create` would be named `create` and collide with every other
`create` in every other tap. `security/1pass-create` keeps the grouping and a
name that survives being installed next to anything else.

## Skills

| Skill | What it does |
|---|---|
| `security/1pass-read` | Discover and read stored website accounts — list, find by domain, inject a secret into a command, get a live TOTP code. Read-only. |
| `security/1pass-create` | Create logins with generated passwords when signing up; rotate passwords; store extra fields. Writes. |
| `security/1pass-2fa` | Store TOTP seeds and recovery codes when enabling two-factor. Writes. |

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

Add this repo as a tap, then install per agent profile:

```bash
hermes skills tap add pushkar-anand/.skills
hermes skills search 1pass
hermes skills install 1pass-read
```

Or mount the clone and point a profile at it in `~/.hermes/config.yaml`:

```yaml
skills:
  external_dirs:
    - ~/.agents/skills
```

Note that `config.yaml` outranks environment variables in Hermes, so this has to
go in `config.yaml` — a `SKILLS_*` env var in compose will not win.

Mount shared skills **read-only**. Hermes agents can author skills through the
`skill_manage` tool, and a writable shared directory means one agent can edit a
skill that every other agent then loads.

## Using these elsewhere

- **Codex / Cursor / OpenCode** — clone to `~/.agents/skills`; it is already
  their user-level skills path.
- **Claude Code** — symlink individual skills into `~/.claude/skills/<name>`,
  or install them as plugins from a marketplace manifest.

## Adding a skill

1. `skills/<category>/<name>/SKILL.md`, with `name:` matching the directory.
2. Keep `SKILL.md` under ~500 lines; push detail into `references/`.
3. Write the `description` for *retrieval* — say what it does and when to use
   it, with the words someone would actually use. It is the only part loaded
   until the skill fires.
4. `tools/validate.sh` before committing.
