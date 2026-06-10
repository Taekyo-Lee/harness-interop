# Project-local rules: merge-upstream (harness-interop)

Loaded by the generic `merge-upstream` skill. Rules here override or extend
the generic defaults for this repo only.

## Conflict resolution

For this project, there are no fixed file-specific resolution rules. 
When merge conflicts occur, apply the following principle:

**Do your best to resolve conflicts logically.**
1. Analyze the changes from both `HEAD` (local) and `upstream` (source).
2. Prioritize preserving local project-specific configurations while incorporating new features or fixes from upstream.
3. If a conflict is genuinely ambiguous or involves critical architectural changes, stop and ask the user for guidance.

## Post-merge actions

Standard `git push origin main` is sufficient for this project. No additional local runners or deployment scripts are required.
