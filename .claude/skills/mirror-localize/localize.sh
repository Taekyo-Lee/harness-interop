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

def sub_lines(path, key, new, label):
    p = pathlib.Path(path)
    if not p.exists():
        return
    lines = p.read_text(encoding='utf-8').split('\n')
    hits = [i for i, l in enumerate(lines) if key in l and l != new]
    if not hits:
        return
    for i in hits:
        lines[i] = new
    p.write_text('\n'.join(lines), encoding='utf-8')
    changed.append(path)
    print(f'[sweep] {path} :: {label} {len(hits)}줄')

# 설치 명령 재작성 — probe 결과에 따라 양방향 (치환 결과는 의도적 하드코딩 —
# upstream 셀 문구가 바뀌면 여기를 갱신).
#   RAW_BLOCKED → clone 형태. 핵심: 설치 명령은 "플러그인을 쓸 프로젝트 폴더"에서
#   실행되므로 (CC local scope = cwd, OC .opencode/ = cwd), clone 은 반드시 /tmp 로
#   — 프로젝트 안에 repo 가 증식하면 안 된다.
#   RAW_OK → public 과 같은 한 줄 설치로 (기존 clone 행도 역마이그레이션 — 2026-06-12
#   repo public 전환으로 GHE 익명 raw 가 열리며 실제 발동).
tmp = f'/tmp/{mr}'
clone_cc = f'rm -rf {tmp} && git clone --depth 1 {mir_web}.git {tmp} && bash {tmp}/plugins-claude/install.sh'
clone_oc = f'rm -rf {tmp} && git clone --depth 1 {mir_web}.git {tmp} && bash {tmp}/plugins-opencode/install.sh'
# 옛 템플릿 (프로젝트 폴더 안에 clone 을 남기던 결함) — 마이그레이션 키로만 사용
old_cc = f'git clone {mir_web}.git && bash {mr}/plugins-claude/install.sh'
old_oc = f'git clone {mir_web}.git && bash {mr}/plugins-opencode/install.sh'
# 미러 raw 경로 두 형식 (probe 후보 A·B) — 한 줄 설치 행을 다시 잠글 때의 키
raw_cc = [f'{mh}/{mo}/{mr}/raw/{branch}/plugins-claude/install.sh',
          f'{mh}/raw/{mo}/{mr}/{branch}/plugins-claude/install.sh']
raw_oc = [f'{mh}/{mo}/{mr}/raw/{branch}/plugins-opencode/install.sh',
          f'{mh}/raw/{mo}/{mr}/{branch}/plugins-opencode/install.sh']

if not raw_ok:
    row_cc = (f'| 🧠 **개인 메모리 공유** | [`memory-bridge-claude`](plugins-claude/memory-bridge-claude/README.md) '
              f'| Claude Code | `{clone_cc}` (플러그인 쓸 프로젝트 폴더에서 실행 · 대화형) |')
    row_oc = (f'| 🧠 **개인 메모리 공유** | [`memory-bridge-opencode`](plugins-opencode/memory-bridge-opencode/README.md) '
              f'| OpenCode | `{clone_oc}` (플러그인 쓸 프로젝트 폴더에서 실행 · 대화형) |')

    for key in (f'{src_raw}/plugins-claude/install.sh', old_cc, *raw_cc):
        sub_lines('README.md', key, row_cc, '카탈로그 행(claude) → /tmp clone 형태')
        sub_lines('plugins-claude/install.sh', key, f'#   {clone_cc}', '헤더 주석 → /tmp clone 형태')
        sub_lines('plugins-claude/memory-bridge-claude/README.md', key, clone_cc, '설치 명령 → /tmp clone 형태')
    for key in (f'{src_raw}/plugins-opencode/install.sh', old_oc, *raw_oc):
        sub_lines('README.md', key, row_oc, '카탈로그 행(opencode) → /tmp clone 형태')
        sub_lines('plugins-opencode/install.sh', key, f'#   {clone_oc}', '헤더 주석 → /tmp clone 형태')
        sub_lines('plugins-opencode/memory-bridge-opencode/README.md', key, clone_oc, '설치 명령 → /tmp clone 형태')

    # 설치 안내 산문 — "clone 불필요" 가 clone 명령과 모순되지 않게
    sub_lines('plugins-claude/memory-bridge-claude/README.md', 'clone 불필요',
              '터미널 한 줄 (`/tmp` 에 임시 clone 후 실행 — **플러그인을 쓸 프로젝트 폴더에서** 실행하세요, 대화형 UI):',
              '안내 문구')
    sub_lines('plugins-opencode/memory-bridge-opencode/README.md', 'clone 불필요',
              '동기화할 프로젝트 루트에서 한 줄 (`/tmp` 에 임시 clone 후 실행, 대화형 UI):',
              '안내 문구')
else:
    # 역마이그레이션: clone 형태(현행 /tmp 형 + 옛 in-project 형) → 한 줄 설치.
    # 신규 upstream 행(public 한 줄)은 아래 일반 치환 규칙이 URL 만 바꿔서 처리.
    one_cc = f'bash <(curl -fsSL {mir_raw_base}/plugins-claude/install.sh)'
    one_oc = f'bash <(curl -fsSL {mir_raw_base}/plugins-opencode/install.sh)'
    row_cc = (f'| 🧠 **개인 메모리 공유** | [`memory-bridge-claude`](plugins-claude/memory-bridge-claude/README.md) '
              f'| Claude Code | `curl -fsSL {mir_raw_base}/plugins-claude/install.sh \\| bash` **(추천 · 한방 설치)**'
              f'<br>`{one_cc}` (대화형 선택) |')
    row_oc = (f'| 🧠 **개인 메모리 공유** | [`memory-bridge-opencode`](plugins-opencode/memory-bridge-opencode/README.md) '
              f'| OpenCode | `curl -fsSL {mir_raw_base}/plugins-opencode/install.sh \\| bash` **(추천 · 한방 설치)**'
              f'<br>`{one_oc}` (대화형 선택) |')

    for key in (f'{tmp}/plugins-claude/install.sh', old_cc):
        sub_lines('README.md', key, row_cc, '카탈로그 행(claude) → 한 줄 설치 복원')
        sub_lines('plugins-claude/install.sh', key, f'#   {one_cc}', '헤더 주석 → 한 줄 설치 복원')
        sub_lines('plugins-claude/memory-bridge-claude/README.md', key, one_cc, '설치 명령 → 한 줄 설치 복원')
    for key in (f'{tmp}/plugins-opencode/install.sh', old_oc):
        sub_lines('README.md', key, row_oc, '카탈로그 행(opencode) → 한 줄 설치 복원')
        sub_lines('plugins-opencode/install.sh', key, f'#   {one_oc}', '헤더 주석 → 한 줄 설치 복원')
        sub_lines('plugins-opencode/memory-bridge-opencode/README.md', key, one_oc, '설치 명령 → 한 줄 설치 복원')

    # 산문 복원 — clone 안내를 원래 문구로
    sub_lines('plugins-claude/memory-bridge-claude/README.md', '임시 clone 후 실행',
              '터미널 한 줄 (clone 불필요, 대화형 UI):', '안내 문구 복원')
    sub_lines('plugins-opencode/memory-bridge-opencode/README.md', '임시 clone 후 실행',
              '동기화할 프로젝트 루트에서 한 줄 (clone 불필요, 대화형 UI):', '안내 문구 복원')

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
