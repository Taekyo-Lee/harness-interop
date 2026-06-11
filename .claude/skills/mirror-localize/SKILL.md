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
raw.githubusercontent.com). Installs that *look* like they come from the
mirror would actually pull from the public repo — or simply fail on a closed
network. This skill rewrites all self-references to the mirror's own address,
**derived from `git remote get-url origin`, never hand-typed**, and proves
completion with a leftover gate.

Design properties:

- **Idempotent** — on an already-localized tree it is a no-op. This is why it
  can run after *every* merge: git merge only mediates conflicts, so brand-new
  upstream files/lines arrive un-localized, and this sweep catches them.
- **Self-correcting probe** — raw-URL reachability is tested against the real
  origin/branch, so the README install form (one-liner vs clone) adapts to the
  instance automatically. No human has to remember the instance's policy.

## Environment Guard — `A2G_LOCATION`

Same gate as `merge-upstream`. **Before anything else**:

```bash
grep -E '^A2G_LOCATION=' .env
```

- `COMPANY`, `CORP`, or `PRODUCTION` → proceed.
- Anything else, line missing, or no `.env` → **stop immediately** and tell
  the user: this machine likely holds the public source; localizing it would
  corrupt the public repo's self-references.

## Identity Resolution (never hand-type URLs)

```bash
git remote get-url origin                                  # → MIRROR
git remote get-url upstream 2>/dev/null \
  || grep -E '^REMOTE_REPO=' .env                          # → SOURCE
git branch --show-current                                  # → BRANCH
```

- **MIRROR**: strip a trailing `.git`; parse `HOST`, `OWNER`, `REPO`.
  Define `MIRROR_WEB = https://HOST/OWNER/REPO` (also what
  `claude plugin marketplace add` accepts as a git URL).
- **SOURCE**: parse the same way → `SRC_OWNER`, `SRC_REPO`. If neither an
  `upstream` remote nor `REMOTE_REPO` in `.env` exists, stop and ask the user
  for the public source URL.
- **Sanity**: if MIRROR and SOURCE name the same repo → stop ("this clone IS
  the source — nothing to localize").

## Raw Reachability Probe

Anonymous `curl` decides which install form the mirror's READMEs may offer.
Try in order; the first 200 wins (remember that URL shape as `RAW_OK`):

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -L --max-time 10 "https://HOST/OWNER/REPO/raw/BRANCH/README.md"
curl -sS -o /dev/null -w '%{http_code}\n' -L --max-time 10 "https://HOST/raw/OWNER/REPO/BRANCH/README.md"
curl -sS -o /dev/null -w '%{http_code}\n' -L --max-time 10 "https://raw.HOST/OWNER/REPO/BRANCH/README.md"
```

All non-200 → **RAW_BLOCKED**. (Typical for enterprise instances: anonymous
requests get masked 404s even on "Public" repos.) Install commands must then
use the clone form — a clone authenticates through the colleague's existing
git credentials, and it keeps the TTY, so the interactive installer UI works.

## Rewrite Sweep (idempotent)

A *self-reference* is any URL or shorthand naming `SRC_OWNER/SRC_REPO`.
Author profile links **without** the repo (e.g. `github.com/SRC_OWNER` alone)
are authorship, NOT self-references — leave them untouched.

Find every occurrence mechanically first — this grep, not the list below, is
the source of truth (newly merged upstream content shows up here too):

```bash
git grep -n "SRC_OWNER/SRC_REPO"
```

**Edit discipline** — READMEs are full of fragile characters (`<br>`, `<(`,
backticks, pipes): always `Read` the file first and build every edit's
old-string **verbatim from the Read output**, never from memory or your own
re-rendering of the file. Prefer replacing one whole line (or a small unique
fragment) over a multi-line cell. If an edit reports "string not found",
re-Read and retry with the exact bytes; after two failures on the same file,
stop patching and rewrite the whole file with the localized content.

Known surfaces and their rewrites:

1. **README install commands** (root catalog ⚡ cells + each plugin README):
   - `RAW_OK` → keep the one-liner forms, substituting the working raw URL
     shape.
   - `RAW_BLOCKED` → replace each install cell/section with the clone form
     (one command; it is interactive by itself, so no second variant needed):
     ```bash
     git clone MIRROR_WEB && bash REPO/plugins-claude/install.sh
     ```
     Also replace raw-download alternatives (e.g. the OpenCode README's
     direct `.ts` curl) with clone-based equivalents.
2. **plugins-claude/install.sh** — `MARKETPLACE_REPO="..."` → `MIRROR_WEB`
   (the CLI accepts a full git URL). Banner URL line and header-comment
   examples → `MIRROR_WEB`. Do NOT touch `MARKETPLACE_NAME` or the
   `@harness-interop` suffixes — the marketplace *name* comes from
   marketplace.json and is host-independent.
3. **plugins-opencode/install.sh** — `RAW_BASE` → the mirror's raw base
   (use the best probe candidate even under `RAW_BLOCKED`: a dead fallback
   must fail loudly *at the mirror*, not silently fetch foreign code from the
   public repo). Banner URL → `MIRROR_WEB`.
4. **README REPL instructions** —
   `/plugin marketplace add SRC_OWNER/SRC_REPO` →
   `/plugin marketplace add MIRROR_WEB`.
5. **plugin.json `repository` fields** → `MIRROR_WEB`.
6. **verify-release.sh raw-URL watch pattern** (§5c) → the mirror's raw URL
   prefix, so the release gate keeps watching the mirror's own links.
7. **Mirror notice** at the top of the root README — insert only if the
   marker is absent (idempotency guard):
   ```markdown
   > <!-- mirror-of: https://github.com/SRC_OWNER/SRC_REPO -->
   > 🔁 이 repo 는 [public 원본](https://github.com/SRC_OWNER/SRC_REPO)의
   > 사내 미러입니다. 변경·이슈는 원본에서; 갱신은 `/merge-upstream` →
   > `/mirror-localize` 로 이뤄집니다.
   ```

## Leftover Gate — must pass before committing

```bash
git grep -n "SRC_OWNER/SRC_REPO"
```

Every remaining hit must be one of:

- the mirror-notice block (`mirror-of:` marker and its blockquote), or
- a file under `.claude/skills/` (the workflow docs legitimately name the
  source).

Anything else means the sweep missed a spot — fix it and re-run the gate
until it is clean. **The gate is the definition of done.** A run with
unexplained leftovers has FAILED: do not commit, do not push, and never
report success "because the core files were done" — partial localization
(install docs silently pointing colleagues at the public repo) is precisely
the bug this skill exists to prevent.

## Commit (no push)

```bash
git add -A
git commit -m "Localize mirror self-references (source → origin)"
bash verify-release.sh HEAD     # require: ✓ RELEASE OK
```

If `verify-release.sh HEAD` fails, fix and commit again before anything is
pushed. Pushing itself is left to the caller: on first setup the user pushes;
on maintenance runs, `merge-upstream`'s post-merge flow pushes after this
skill completes.

## When this skill runs

- **First run**: right after the initial mirror push to the internal host.
- **Maintenance**: from `merge-upstream`'s post-merge actions (see that
  skill's `SKILL.local.md`) — after every merge, before every push.
