# CLAUDE.md

This repository is a **reusable skill catalog** for Claude Code. Skills live under `skills/<category>/<skill-name>/` and are copied into consuming projects via `install.sh`.

When working on skills in this repo (authoring new ones, editing existing ones, refactoring), follow the conventions below.

## Repository layout

```
skills/
├── <category>/            # e.g. gradle, spring-boot, database, design, ui
│   └── <skill-name>/
│       ├── SKILL.md       # required — frontmatter + instructions
│       ├── references/    # optional — loaded on demand
│       ├── scripts/       # optional — executable helpers
│       └── assets/        # optional — templates, fixtures
README.md                  # catalog overview + per-skill usage docs
install.sh                 # copies selected skills into a project's .claude/skills/
```

**No per-skill READMEs.** Usage documentation for all skills lives in the root `README.md` under a per-skill section. Keep `SKILL.md` agent-focused (no invocation examples, no prompt-phrasing tips); `README.md` is the human-facing surface.

**Category purpose:** organization in this repo only. `install.sh` copies to a flat `.claude/skills/` in the consuming project, so **skill names must be unique across the entire catalog** regardless of category.

**Picking a category:**
- `gradle/` — build configuration (build.gradle.kts, plugins, dependencies, wrapper).
- `spring-boot/` — Spring Boot **runtime** patterns (layered architecture, DI, JPA, security, DTO conventions).
- `database/` — schema migrations, Docker DB setup, SQL style.
- `design/` — language-agnostic API/UX design (REST conventions, error formats, pagination semantics).
- `ui/` — frontend patterns (React, Ant Design, state management).

Create a new category only when no existing one fits. Prefer the narrower fit over inventing a new bucket.

**Skill directory name** must match the `name` field in frontmatter.

**Language:** English for all SKILL.md content.

## Specification

Skills follow the **agentskills.io** open format: https://agentskills.io/specification. This is also the format Claude Code uses natively, so skills work without adaptation.

Primary authoring reference: https://agentskills.io/skill-creation/optimizing-descriptions — how descriptions actually drive skill activation.

Claude Code extends the base spec with optional fields: `when_to_use`, `disable-model-invocation`, `argument-hint`, etc. Use only when needed; prefer the base spec.

## Frontmatter

**Required:**

| Field | Constraint |
|---|---|
| `name` | 1-64 chars, lowercase alphanumeric + hyphens. No leading/trailing/consecutive hyphens. Must match the parent directory name. |
| `description` | 1-1024 chars. Must describe **both** what the skill does **and** when to use it. |

**Optional (use sparingly):**
- `disable-model-invocation: true` — skill only runs on explicit `/skill-name` invocation. Use for procedural skills like checklists.
- `argument-hint: "[entity-name]"` — shown in slash-command UI when `disable-model-invocation: true`.

## Description — the only field that decides activation

Agents load only `name` + `description` at session start. The description alone decides whether the skill triggers. Get this right or the skill never runs.

### Rules

1. **Imperative phrasing.** Address the agent, not the reader: `Use this skill when...` — not `This skill does...`.
2. **User intent, not implementation.** Describe what the user is trying to achieve, not the skill's internal mechanics. Don't enumerate the skill's table of contents — that's what the body is for.
3. **Cover both.** `{capability — what it does}` + `Use this skill when {triggers — canonical use cases}`.
4. **Minimum sufficient for the canonical use case.** This catalog has one skill per domain, so keyword-dense triggers for disambiguation are unnecessary. Do NOT preemptively list near-miss symptoms (`"0 tests executed"`, `"even if they don't mention 'Gradle'"`). Add them only when you observe false-negatives in practice.
5. **Concise.** One or two sentences for capability, one sentence listing the main use cases. Aim for ~300-500 chars. Hard limit 1024.

### Template

```yaml
description: >
  {What the skill does — one sentence, with the domain noun and scope}.
  Use this skill when {canonical use cases — 3-5 categories, comma-separated}.
```

### Examples

Bad — too vague, no triggers:
```yaml
description: Configure Spring Boot Gradle builds.
```

Bad — enumerates the table of contents instead of describing use cases:
```yaml
description: >
  Set up a Spring Boot Gradle build — build.gradle.kts, libs.versions.toml,
  Java toolchain, Lombok + MapStruct annotation processor ordering, BOM
  import via platform(), minimum JUnit Platform test config.
```

Good — scope sentence + canonical use cases:
```yaml
description: >
  Set up or maintain the Gradle build of a single-module Spring Boot 3.5+
  application using Kotlin DSL. Use this skill when the user needs to
  configure, extend, or troubleshoot a Spring Boot Gradle build —
  bootstrapping a new project, adding or upgrading dependencies, upgrading
  Spring Boot or Gradle versions, or fixing build-time failures.
```

## Body

Loaded only after the description triggers activation. Write for an agent that needs to act correctly — not for human onboarding.

**Rules:**

- **≤500 lines.** If the skill grows beyond that, move detail into `references/*.md` (loaded on demand) and link from SKILL.md.
- **Imperative tone** throughout. "Use X, not Y" / "Always Z" — not "One might consider...".
- **Tables for reference data** (scopes, status-code mappings, version matrices). Tables compress well in context.
- **Mark non-negotiables explicitly.** A numbered "non-negotiable rules" block near the top of each skill — so the agent cannot miss them. State the rule as a directive, without rationale: the code snippets above the block already show the correct form.
- **Concrete code, not prose.** Show the exact snippet to copy; explain only non-obvious parts.
- **No redundant prose.** If a rule is in a table or code block, don't restate it in paragraph form.
- **Verification checklist** — only when the skill has success signals the agent wouldn't naturally observe (external system state, non-obvious side effects). Do not list "run the build and check if it's green" — that's implicit.

## When editing existing skills

- **Never rename a skill** without coordinating with consuming projects. The `name` field is the public contract — consuming projects install skills by name.
- **Descriptions can be rewritten** freely to improve triggering. Do it in a dedicated commit so reverting is easy.
- **Body edits** — prefer targeted edits over full rewrites to keep diffs reviewable.

## Commit messages

Repo style: `docs(skills): <summary>` or `chore(skills): <summary>` — follow it.
