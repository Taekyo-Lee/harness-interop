---
name: mirror-localize
description: >
  Rewrite this repo's self-references (install-command URLs, MARKETPLACE_REPO,
  RAW_BASE, marketplace-add instructions, repository metadata, the
  verify-release raw-URL watch pattern) so they point at the mirror's own
  `origin` remote instead of the public source repo. Use right after
  mirroring this repo to a company/internal git host (e.g. GitHub
  Enterprise), and after every merge-upstream run, or whenever the user says
  "mirror localize", "localize the mirror", "회사화", "companyfy", or reports
  that install commands in a mirrored copy still point at the public repo.
  IMPORTANT: runs only in the COMPANY environment (`A2G_LOCATION` set to
  `COMPANY`, `CORP`, or `PRODUCTION` in `.env`); on HOME or DEVELOPMENT it
  must refuse — those machines hold the public source, whose self-references
  must stay public.
---

# Mirror Localize Workflow

After this repo is mirrored to an internal git host, every self-reference in
the tree still points at the public source (github.com /
raw.githubusercontent.com). This skill localizes them to the mirror's own
address — but **all byte-level work lives in the tracked script next to this
file**, not in model-composed edits. Running the skill means running exactly
one command:

```bash
bash .claude/skills/mirror-localize/localize.sh
```

## Why a script, not hand edits

The company transport corrupts `<`-bearing tool parameters
(`<br>` → `<<brbr>`, `<(` → `<<((`, `<div` → `<<divdiv` — observed
2026-06-11, identically on retry and even with old-strings built from a
fresh Read). READMEs are full of `<`, so Edit/Write payloads cannot be
trusted there — Edit fails loudly, Write can corrupt *silently*. The
script's bytes travel via git instead, and the one command above contains
no `<` at all. **Never patch the target files by hand, not even to "help"
after a failure** — hand edits are exactly what the corruption breaks.

## What the script does (in order)

1. **Gate**: requires `A2G_LOCATION` ∈ {COMPANY, CORP, PRODUCTION} in
   `.env`; otherwise aborts (HOME/DEVELOPMENT hold the public source).
2. **Identity**: MIRROR from `git remote get-url origin`; SOURCE from the
   `upstream` remote or `REMOTE_REPO` in `.env` — never hand-typed. Aborts
   if this clone IS the source.
3. **Probe**: tries 3 anonymous raw-URL shapes against the mirror; all
   non-200 → clone-form install commands (enterprise instances typically
   mask anonymous access as 404).
4. **Sweep** (idempotent): README catalog rows, install.sh header comments,
   `MARKETPLACE_REPO`, `RAW_BASE`, banner URLs, plugin.json `repository`,
   plugin README install lines, the verify-release raw-URL watch pattern.
   Replacement strings are deliberately hardcoded in the script.
5. **Mirror notice**: one `<`-free blockquote line prepended to the root
   README (`mirror-of:` marker = idempotency guard; it keeps pointing at
   the public source by design).
6. **Leftover gate**: `git grep` for the source `OWNER/REPO`. Allowed
   leftovers are ONLY the mirror notice, `.claude/skills/`, and
   `.env.example` (its `REMOTE_REPO=` line IS the upstream pointer —
   localizing it would point the mirror's upstream at itself). Anything
   else → exit 1, nothing committed.
7. **Commit → `bash verify-release.sh HEAD` → push**. (`--no-push` skips
   the final push, e.g. for tests.)

Because the sweep is idempotent, the script is safe to run after *every*
merge: git merge only mediates conflicts, so brand-new upstream files/lines
arrive un-localized, and the sweep catches them; an already-localized tree
is a no-op.

## Your job as the model

1. Run the one command above. Do not re-implement any of its steps.
2. Relay the tail of its output to the user: the probe conclusion, the
   leftover-gate result, the verify result, and the final `DONE` line.
3. If it exits non-zero, show the full output and stop. **The gate is the
   definition of done** — a run that ends with unexplained leftovers or a
   failed verify has FAILED, even if "most files were done".

## When this runs

- **First setup**: right after the initial mirror push + `.env` creation —
  invoke once; the script pushes at the end.
- **Maintenance**: `merge-upstream`'s post-merge actions invoke this skill
  after every merge, before its own push.
- If upstream reshapes the README install cells, update the literal
  templates inside `localize.sh` — they are hardcoded on purpose.
