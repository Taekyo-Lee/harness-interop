---
name: merge-upstream
description: >
  Merge the `upstream` remote's main branch into the local `main` branch of
  the current repo. Use this skill whenever the user wants to sync, merge,
  pull, or update from upstream, or mentions bringing in changes from a
  public/source repo, or says anything like "merge upstream", "sync from
  upstream", "pull upstream changes", or "update from public repo". Also
  trigger when the user mentions a downstream/mirror repo being out of date
  with its source, or wanting to reflect upstream updates. IMPORTANT: This
  skill only runs in the COMPANY environment (gated by `A2G_LOCATION` set to
  `COMPANY`, `CORP`, or `PRODUCTION` in `.env`). On HOME or DEVELOPMENT machines it must stop immediately and
  refuse to run.
---

# Merge Upstream Workflow

This skill syncs the local `main` branch with the `upstream` remote, handling
the recurring conflicts and project-specific post-merge actions through a
per-project override file (`SKILL.local.md`) loaded at runtime.

## Environment Guard — `A2G_LOCATION`

This skill is designed exclusively for the COMPANY environment. Running it
on HOME or DEVELOPMENT machines is incorrect — those environments push
directly to the source repo and never merge from upstream.

**Before doing anything else**, read the `.env` file in the project root and
check `A2G_LOCATION`:

```bash
grep -E '^A2G_LOCATION=' .env
```

The value is set in `.env`, not as a shell environment variable.

- If the value is `COMPANY`, `CORP`, or `PRODUCTION` → proceed.
- If the value is anything else (e.g., `HOME`, `DEVELOPMENT`), the line is
  missing, or `.env` does not exist → **stop immediately** and tell the user:

> This skill only runs in the COMPANY environment
> (`A2G_LOCATION=COMPANY` / `CORP` / `PRODUCTION` in `.env`). The current
> value is `<value-or-missing>`. If you're on a company machine, check
> `.env`. If you're on HOME or DEVELOPMENT, you don't need this skill —
> push directly to the source repo instead.

Do not proceed past this check unless the value matches.

## Load Project-Local Rules — MANDATORY FIRST STEP

**Before doing anything else in this skill** (including the remote checks
below), you MUST locate and read the per-project override file:

```
<project root>/.claude/skills/merge-upstream/SKILL.local.md
```

```bash
test -f .claude/skills/merge-upstream/SKILL.local.md && echo present || echo absent
```

- **If the file exists** → read its full contents NOW with the `Read` tool.
  Its rules are authoritative for this project. They override or extend the
  generic defaults in this file (conflict resolution, commit message format,
  post-merge actions like starting a self-hosted runner or retrying pushes).
  **If a local rule contradicts a generic default in this file, the local
  rule wins.** Do not proceed to "Remote Setup" until you have read it.

- **If the file does not exist** → continue with only the generic guidance
  in this file. No further action needed.

This step is non-optional. Skipping it on a project that has local rules
will silently produce wrong conflict resolutions and miss post-merge
actions. The rest of this skill assumes local rules — if any
— have already been loaded into context.

## Remote Setup

This skill assumes two remotes:

- **origin**: the company-side repo (where the merged result is pushed).
- **upstream**: the source repo (where new content is pulled from).

### Origin Check

```bash
git remote -v
```

There must be a remote named `origin`. If `origin` is missing, **stop** and
tell the user:

> No `origin` remote is configured in this repo. This skill needs `origin`
> to point at the company-side repo before it can run. Add it with
> `git remote add origin <url>` and try again.

### Upstream Check (with `.env` fallback)

```bash
git remote get-url upstream 2>/dev/null
```

- **If `upstream` exists** → continue.
- **If `upstream` is missing** → read `.env` for `REMOTE_REPO`:

  ```bash
  grep -E '^REMOTE_REPO=' .env
  ```

  - **If `REMOTE_REPO` is missing too** → **stop** and tell the user:

    > No `upstream` remote configured and no `REMOTE_REPO` in `.env`.
    > Either add the remote (`git remote add upstream <url>`) or set
    > `REMOTE_REPO=<url>` in `.env`, then try again.

  - **If `REMOTE_REPO` is set** → ask the user how they want to use it
    via the `AskUserQuestion` tool with these two options:

    1. **Add as a permanent remote** (recommended) — runs
       `git remote add upstream $REMOTE_REPO` so future merges work
       without re-asking.
    2. **One-time fetch only** — uses the URL directly for this merge via
       `git fetch <url>` and does not persist the remote.

    Apply the user's choice. If they pick (1), run
    `git remote add upstream "$REMOTE_REPO"` and verify with
    `git remote -v`. If they pick (2), substitute `"$REMOTE_REPO"` for
    `upstream` in the fetch step below; the rest of the skill is unchanged.

## Step-by-Step Process

### 1. Pre-flight Check

Verify the working directory is clean:

```bash
git status
```

If there are uncommitted changes, stop and inform the user. Do not proceed
with a dirty working tree — the merge could destroy their work.

Also confirm we are on the `main` branch:

```bash
git branch --show-current
```

If not on `main`, stop and ask the user whether to switch.

### 2. Fetch and Update

Fetch the latest from upstream:

```bash
git fetch upstream
```

(If the user picked the one-time-fetch option earlier, use
`git fetch "$REMOTE_REPO" main:refs/remotes/upstream/main` instead.)

#### If `git fetch upstream` fails

A common cause is the upstream repo being **set to private temporarily**
on its host (e.g., github.com). Without credentials, an unauthenticated
fetch against a private repo returns an error that looks identical to a
credential problem.

Typical error signatures:

- `remote: Invalid username or token. Password authentication is not supported for Git operations.`
- `fatal: Authentication failed for 'https://github.com/...'`
- `remote: Repository not found.`

**Do not immediately suggest fixing credentials, VPN, or tokens.** First
ask the user to confirm the upstream repo's visibility:

> The fetch from upstream failed. The most likely reason is that the
> upstream repo is currently set to **private**. Could you flip it to
> **public** temporarily, then tell me when it's done so I can retry?
>
> (If it's already public, this is probably a credential or VPN issue —
> let me know and we can debug from there.)

Wait for the user to confirm before retrying. Only fall back to credential
/ VPN / token diagnostics after they confirm the repo is public.

#### Continue once fetch succeeds

If a local branch named `upstream` exists, refresh it. Otherwise skip:

```bash
git show-ref --verify --quiet refs/heads/upstream && \
  git checkout upstream && git pull upstream main && git checkout main
```

### 3. Merge

```bash
git merge upstream/main
```

(Or `git merge upstream` if a local `upstream` branch exists and was
updated above.)

### 4. Handle Conflicts

If the merge succeeds without conflicts, skip to Step 5.

If there are conflicts:

1. **First, apply any rules from `SKILL.local.md`** loaded earlier. Project
   conflict-resolution rules are authoritative for files they cover.

2. **For files not covered by local rules**, apply these generic
   heuristics. The principle: **if not tremendously risky, proceed without
   asking**. Most repos that use this skill are content/blog repos where
   the worst case is a broken preview, not data loss.

   - **Upstream changes to content, styles, components, or page
     structure** → take upstream. The source repo drives content
     evolution.
   - **Company-specific additions in HEAD** → preserve them. These are
     customizations that don't exist upstream and serve the company
     deployment.
   - **Both sides changed the same thing differently**:
     - If the difference is cosmetic (variable naming, comments, label
       wording), take upstream.
     - If it affects routing, deployment config, or company-specific
       behavior, take HEAD.

   Only stop and ask the user when the conflict is genuinely ambiguous
   or could break company-specific deployment logic.

### 5. Stage and Commit

After resolving all conflicts (or if there were none):

```bash
git add -A
git commit -m "Merge upstream into main"
```

If `SKILL.local.md` specifies a different commit message format, use that
instead.

### 6. Show Final Status

```bash
git status
git log --oneline -5
```

Present the results to the user.

### 7. Post-Merge — Push (and project-specific actions)

If `SKILL.local.md` defines post-merge steps (e.g., starting a self-hosted
runner, retry-push behavior, deployment-specific actions), follow them.
Otherwise, the default is a plain push:

```bash
git push origin main
```

After a successful push, inform the user that the merge is complete and
report any project-specific outcomes (e.g., "runner started in
background", "retry was needed") that the local rules required.

## Error Handling

- **Dirty working tree**: Stop and inform the user. Suggest committing or
  stashing first.
- **Merge abort needed**: If something goes wrong mid-merge,
  `git merge --abort` returns to the pre-merge state.
- **Unexpected conflicts**: Resolve using local rules first, then generic
  heuristics. Only ask the user for genuinely ambiguous or high-risk
  conflicts.
- **`git fetch upstream` fails**: See the "If `git fetch upstream` fails"
  section in Step 2. Most likely cause is the upstream repo being
  temporarily private — ask the user to flip it public before chasing
  credential or VPN issues.
