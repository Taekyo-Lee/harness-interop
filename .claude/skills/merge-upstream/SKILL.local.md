# Project-local rules: merge-upstream (harness-interop)

Loaded by the generic `merge-upstream` skill. Rules here override or extend
the generic defaults for this repo only.

## Conflict resolution

**Rule 0 — self-references: always take upstream.** Conflicts that touch the
repo's self-references — install-command URLs in any README,
`MARKETPLACE_REPO` in `plugins-claude/install.sh`, `RAW_BASE` in
`plugins-opencode/install.sh`, banner URL lines, `repository` fields in
plugin.json, the raw-URL watch pattern in `verify-release.sh` — are resolved
by taking the **upstream** side wholesale. Do not hand-preserve the
company-localized URLs during the merge: the post-merge `mirror-localize`
sweep re-applies them deterministically, and hand-merging them invites drift.

For everything else, there are no fixed file-specific rules; resolve
logically:

1. Analyze the changes from both `HEAD` (local) and `upstream` (source).
2. Prioritize preserving local project-specific configurations while
   incorporating new features or fixes from upstream.
3. If a conflict is genuinely ambiguous or involves critical architectural
   changes, stop and ask the user for guidance.

## Post-merge actions (replaces the plain-push default)

A merge can bring in NEW files or lines that still carry the public repo's
self-references — git only mediates *conflicts*, so clean additions arrive
un-localized. Therefore, after every merge and before pushing:

1. Run the `mirror-localize` skill
   (`.claude/skills/mirror-localize/SKILL.md`). It is idempotent — on an
   already-localized tree it is a no-op.
2. If it made changes, it commits them itself
   (`Localize mirror self-references`).
3. Run `bash verify-release.sh HEAD` and require `✓ RELEASE OK`.
4. Only then: `git push origin main`.
