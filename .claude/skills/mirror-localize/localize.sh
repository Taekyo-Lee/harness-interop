#!/usr/bin/env bash
# localize.sh — 미러 회사화의 모든 바이트 조작 (mirror-localize skill 의 실행부)
#
# 왜 스크립트인가: 회사 환경은 모델 경유 tool 파라미터의 `<토큰`을 `<<토큰토큰`으로
# 이중화한다 (2026-06-11 실측: <br>→<<brbr>, <(→<<((, <div→<<divdiv). 이 파일은
# git 으로 운반되므로 그 경로를 타지 않고, 모델이 칠 명령
# (`bash .claude/skills/mirror-localize/localize.sh`) 에는 `<` 가 없다.
#
# 하는 일(순서): A2G 게이트 → identity(origin=MIRROR, upstream/REMOTE_REPO=SOURCE)
# → raw 도달성 probe → 치환 sweep(멱등) → 미러 공지 → 잔재 게이트 → commit
# → verify-release.sh HEAD → push.      --no-push = push 생략 (테스트용).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

NO_PUSH=0
[ "${1:-}" = "--no-push" ] && NO_PUSH=1

# ── 게이트: COMPANY 전용 ─────────────────────────────────────────────
[ -f .env ] || { echo "[gate] ABORT: .env 없음 — A2G_LOCATION 게이트 불통과" >&2; exit 1; }
LOC="$(grep -E '^A2G_LOCATION=' .env | head -1 | cut -d= -f2- | tr -d ' \r"' | tr -d "'")"
case "$LOC" in
  COMPANY|CORP|PRODUCTION) echo "[gate] A2G_LOCATION=$LOC OK" ;;
  *) echo "[gate] ABORT: A2G_LOCATION='$LOC' — COMPANY 전용 (public source 의 자기참조 보호)" >&2; exit 1 ;;
esac

# ── identity (손타이핑 금지 — remote 에서 유도) ──────────────────────
ORIGIN="$(git remote get-url origin)"
SOURCE="$(git remote get-url upstream 2>/dev/null || true)"
[ -n "$SOURCE" ] || SOURCE="$(grep -E '^REMOTE_REPO=' .env | head -1 | cut -d= -f2- | tr -d ' \r"' | tr -d "'")"
[ -n "$SOURCE" ] || { echo "[identity] ABORT: upstream remote 도 .env 의 REMOTE_REPO 도 없음" >&2; exit 1; }
BRANCH="$(git branch --show-current)"; [ -n "$BRANCH" ] || BRANCH=main
echo "[identity] MIRROR=$ORIGIN"
echo "[identity] SOURCE=$SOURCE  BRANCH=$BRANCH"

python3 - "$ORIGIN" "$SOURCE" "$BRANCH" <<'PY'
import pathlib, re, subprocess, sys

origin, source, branch = sys.argv[1], sys.argv[2], sys.argv[3]

def parse(url):
    u = re.sub(r'\.git$', '', url.strip())
    m = re.match(r'^(?:https?://|ssh://git@|git@)([^/:]+)[:/](.+)$', u)
    if not m:
        sys.exit(f'[identity] FAIL: URL 해석 불가: {url}')
    host, path = m.groups()
    parts = [p for p in path.split('/') if p]
    if len(parts) < 2:
        sys.exit(f'[identity] FAIL: owner/repo 해석 불가: {url}')
    return host, parts[-2], parts[-1]

mh, mo, mr = parse(origin)
sh, so, sr = parse(source)
if (mh, mo, mr) == (sh, so, sr):
    sys.exit('[identity] FAIL: 이 clone 이 곧 source — 회사화 대상 아님')

mir_web   = f'https://{mh}/{mo}/{mr}'
src_web   = f'https://{sh}/{so}/{sr}'
src_short = f'{so}/{sr}'
src_raw   = (f'raw.githubusercontent.com/{so}/{sr}/{branch}'
             if sh == 'github.com' else f'{sh}/{so}/{sr}/raw/{branch}')

# ── probe: 미러 raw 가 익명으로 닿는가 (3형식 cascade) ──
def http(url):
    try:
        r = subprocess.run(['curl', '-sS', '-o', '/dev/null', '-w', '%{http_code}',
                            '-L', '--max-time', '10', url],
                           capture_output=True, text=True, timeout=20)
        return r.stdout.strip() or '000'
    except Exception:
        return '000'

cands = [f'https://{mh}/{mo}/{mr}/raw/{branch}',
         f'https://{mh}/raw/{mo}/{mr}/{branch}',
         f'https://raw.{mh}/{mo}/{mr}/{branch}']
mir_raw_base, raw_ok = cands[0], False
for c in cands:
    code = http(c + '/README.md')
    print(f'[probe] {code}  {c}/README.md')
    if code == '200':
        mir_raw_base, raw_ok = c, True
        break
print(f'[probe] 결론: {"RAW_OK — 한 줄 설치 유지" if raw_ok else "RAW_BLOCKED — clone 설치 형태로 전환"}')

changed = []

def sub_lines(path, key, new):
    p = pathlib.Path(path)
    if not p.exists():
        return
    lines = p.read_text(encoding='utf-8').split('\n')
    hits = [i for i, l in enumerate(lines) if key in l]
    if not hits:
        return
    for i in hits:
        lines[i] = new
    p.write_text('\n'.join(lines), encoding='utf-8')
    changed.append(path)
    print(f'[sweep] {path} :: 설치 줄 {len(hits)}개 → clone 형태')

# RAW_BLOCKED 일 때만: 한 줄 설치 명령들을 clone 형태로 통째 교체
# (치환 결과는 의도적으로 하드코딩 — upstream 이 셀 문구를 바꾸면 여기를 갱신)
if not raw_ok:
    clone_cc = f'git clone {mir_web}.git && bash {mr}/plugins-claude/install.sh'
    clone_oc = f'git clone {mir_web}.git && bash {mr}/plugins-opencode/install.sh'
    sub_lines('README.md', f'{src_raw}/plugins-claude/install.sh',
              f'| 🧠 **개인 메모리 공유** | [`memory-bridge-claude`](plugins-claude/memory-bridge-claude/README.md) | Claude Code | `{clone_cc}` (대화형 설치) |')
    sub_lines('README.md', f'{src_raw}/plugins-opencode/install.sh',
              f'| 🧠 **개인 메모리 공유** | [`memory-bridge-opencode`](plugins-opencode/memory-bridge-opencode/README.md) | OpenCode | `{clone_oc}` (대화형 설치) |')
    sub_lines('plugins-claude/install.sh', f'{src_raw}/plugins-claude/install.sh', f'#   {clone_cc}')
    sub_lines('plugins-opencode/install.sh', f'{src_raw}/plugins-opencode/install.sh', f'#   {clone_oc}')
    sub_lines('plugins-claude/memory-bridge-claude/README.md', f'{src_raw}/plugins-claude/install.sh', clone_cc)
    sub_lines('plugins-opencode/memory-bridge-opencode/README.md', f'{src_raw}/plugins-opencode/install.sh', clone_oc)

# ── 부분문자열 치환 (전 tracked 파일, 멱등) ──
mir_raw_hostpath = re.sub(r'^https://', '', mir_raw_base)
rules = [
    (src_raw.replace('.', r'\.') + '/',                                  # verify-release watch 패턴(이스케이프형)
     mir_raw_hostpath.replace('.', r'\.') + '/'),
    ('https://' + src_raw, mir_raw_base),                                # RAW_BASE·직다운로드·(RAW_OK 시) 한줄설치
    (f'marketplace add {src_short}', f'marketplace add {mir_web}'),      # REPL 안내 (shorthand 는 미러에 없음)
    (f'MARKETPLACE_REPO="{src_short}"', f'MARKETPLACE_REPO="{mir_web}"'),
    (src_web, mir_web),                                                  # 배너·plugin.json repository 등 전체 URL
]

def excluded(f):
    return f.startswith('.claude/skills/') or f.startswith('temp-') or f == '.env.example'

files = subprocess.run(['git', 'ls-files'], capture_output=True, text=True,
                       check=True).stdout.splitlines()
for f in files:
    if excluded(f):
        continue
    p = pathlib.Path(f)
    try:
        t = p.read_text(encoding='utf-8')
    except (UnicodeDecodeError, FileNotFoundError):
        continue
    out = []
    for line in t.split('\n'):
        if 'mirror-of:' not in line:        # 미러 공지는 의도적으로 원본을 가리킴 — 치환 보호
            for a, b in rules:
                line = line.replace(a, b)
        out.append(line)
    t2 = '\n'.join(out)
    if t2 != t:
        p.write_text(t2, encoding='utf-8')
        changed.append(f)
        print(f'[sweep] {f} :: 자기참조 치환')

# ── 미러 공지 (멱등: mirror-of: 마커; `<` 없는 단행 blockquote) ──
readme = pathlib.Path('README.md')
t = readme.read_text(encoding='utf-8')
if 'mirror-of:' not in t:
    notice = (f'> 🔁 **사내 미러** (mirror-of: {src_web}) — 변경·이슈는 public 원본에서; '
              f'갱신은 `/merge-upstream` → `/mirror-localize`.\n\n')
    readme.write_text(notice + t, encoding='utf-8')
    changed.append('README.md')
    print('[notice] README.md 맨 위에 미러 공지 삽입')
else:
    print('[notice] 이미 있음 — 건너뜀')

# ── 잔재 게이트 = 완료의 정의 ──
r = subprocess.run(['git', 'grep', '-n', src_short], capture_output=True, text=True)
hits = [h for h in r.stdout.split('\n') if h]
left = [h for h in hits
        if not (h.startswith('.claude/skills/') or h.startswith('.env.example:')
                or 'mirror-of:' in h)]
for h in hits:
    print(f'[leftover-gate] {h}')
if left:
    print('[leftover-gate] FAIL — 예상 밖 잔재. 커밋하지 않음:', file=sys.stderr)
    for h in left:
        print(f'  {h}', file=sys.stderr)
    sys.exit(1)
print('[leftover-gate] PASS (허용 잔재: mirror-of 공지 · .claude/skills/ · .env.example 의 REMOTE_REPO=원본 포인터)')
if changed:
    print(f'[sweep] 변경 파일 {len(set(changed))}개')
else:
    print('[sweep] 변경 없음 — 이미 회사화된 트리 (멱등 no-op)')
PY

# ── commit → verify → push ──────────────────────────────────────────
git add -u
if git diff --cached --quiet; then
  echo '[git] 커밋할 변경 없음'
else
  git commit -m 'Localize mirror self-references (source -> origin)'
fi
bash verify-release.sh HEAD
if [ "$NO_PUSH" = "1" ]; then
  echo '[git] --no-push: push 생략 (테스트 모드)'
else
  git push origin main
fi
echo '=== mirror-localize: DONE ==='
