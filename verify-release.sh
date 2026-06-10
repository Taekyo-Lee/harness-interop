#!/usr/bin/env bash
# verify-release.sh — 배포물(원격 트리)이 배포 계약을 지키는지 검증. 전부 read-only.
# 위치: repo 루트 고정 — 특정 harness 그룹이 아니라 repo *전체* 계약의 관문.
#
# 설계: 검사 목록은 가능한 한 **트리에서 유도**합니다 — 플러그인이 늘어도 이 스크립트는
# 그대로. (CC 플러그인 = marketplace.json 의 source 루프, OC 플러그인 = plugins-opencode/
# 스캔, 그리고 모든 *.sh / *.json / README 에 일반 규칙 적용.)
# 수동 목록은 둘뿐: ① repo 뼈대 파일 ② 과거 사고의 재발 방지(금지 경로).
#
# 언제: 웹 반영 + git pull 직후마다. 배포(공유·공지) 전 필수 관문.
# 사용: bash verify-release.sh            # origin/main 검증 (기본)
#       bash verify-release.sh HEAD      # 로컬 commit 검증
set -euo pipefail

REF="${1:-origin/main}"
git fetch -q origin 2>/dev/null || true
tree="$(git ls-tree -r "$REF" --name-only)"

fail=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1" >&2; fail=1; }
has() { printf '%s\n' "$tree" | grep -qx "$1"; }

echo "[$REF] 1. repo 뼈대 (고정 목록)"
for p in \
  .claude-plugin/marketplace.json \
  plugins-claude/install.sh \
  plugins-opencode/install.sh \
  verify-release.sh \
  README.md
do
  if has "$p"; then ok "$p"; else bad "누락: $p"; fi
done

echo "[$REF] 2. CC 플러그인 계약 (marketplace.json 에서 유도)"
if command -v jq >/dev/null 2>&1; then
  cc_sources="$(git show "$REF:.claude-plugin/marketplace.json" 2>/dev/null | jq -r '.plugins[].source' 2>/dev/null | sed 's|^\./||' || true)"
  [ -n "$cc_sources" ] || bad "marketplace.json 에서 source 를 읽지 못함"
  for s in $cc_sources; do
    # 필수 구성: manifest + 자체 README
    for f in ".claude-plugin/plugin.json" "README.md"; do
      if has "$s/$f"; then ok "$s/$f"; else bad "누락: $s/$f"; fi
    done
    # manifest 에 version 이 있는가 (없으면 설치자가 업데이트를 못 받음)
    v="$(git show "$REF:$s/.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
    if [ -n "$v" ]; then ok "$s: version $v"; else bad "$s: plugin.json 에 version 없음"; fi
  done
else
  echo "  ! jq 없음 — CC 계약 검사 생략" >&2
fi

echo "[$REF] 3. OC 플러그인 계약 (plugins-opencode/ 스캔에서 유도)"
oc_names="$(printf '%s\n' "$tree" | sed -n 's|^plugins-opencode/\([^/]*\)/.*|\1|p' | sort -u)"
for n in $oc_names; do
  # plugin/ 층 아래 ts 가 있어야 함 (평탄화 사고의 일반 감지)
  if printf '%s\n' "$tree" | grep -q "^plugins-opencode/$n/plugin/.*\.ts$"; then
    ok "plugins-opencode/$n/plugin/*.ts"
  else
    bad "누락(평탄화?): plugins-opencode/$n/plugin/*.ts"
  fi
  # <플러그인>/ 직속 .ts 금지 (plugin/ 층을 잃은 평탄화)
  if printf '%s\n' "$tree" | grep -q "^plugins-opencode/$n/[^/]*\.ts$"; then
    bad "평탄화: plugins-opencode/$n/ 직속에 .ts 존재"
  else
    ok "plugins-opencode/$n: 평탄화 없음"
  fi
  if has "plugins-opencode/$n/README.md"; then ok "plugins-opencode/$n/README.md"; else bad "누락: plugins-opencode/$n/README.md"; fi
done

echo "[$REF] 4. 금지 경로 (과거 사고 재발 방지 + 비공개 유출)"
forbidden_exact='
plugins-claude/memory-bridge-claude/scriptsmemory-bridge.sh
CLAUDE.md
AGENTS.md
install-cc-plugins.sh
install-oc-plugins.sh
'
for p in $forbidden_exact; do
  if has "$p"; then bad "존재하면 안 됨: $p"; else ok "없음: $p"; fi
done
if printf '%s\n' "$tree" | grep -q '^_reference/'; then bad "존재하면 안 됨: _reference/*"; else ok "없음: _reference/*"; fi

echo "[$REF] 5. 일반 규칙 (트리 전체에서 유도)"
# 5a. 모든 *.json 이 유효한 JSON 인가
if command -v jq >/dev/null 2>&1; then
  for j in $(printf '%s\n' "$tree" | grep '\.json$'); do
    if git show "$REF:$j" 2>/dev/null | jq -e . >/dev/null 2>&1; then ok "json: $j"; else bad "JSON 불량: $j"; fi
  done
fi
# 5b. 모든 *.sh 가 bash 문법을 통과하는가
for s in $(printf '%s\n' "$tree" | grep '\.sh$'); do
  if git show "$REF:$s" 2>/dev/null | bash -n 2>/dev/null; then ok "bash -n: $s"; else bad "셸 문법: $s"; fi
done
# 5c. 모든 README 의 raw URL 이 트리에 실존하는가 (404 예방)
urls=""
for rmd in $(printf '%s\n' "$tree" | grep -E '(^|/)README\.md$'); do
  urls="$urls $(git show "$REF:$rmd" 2>/dev/null \
    | grep -o 'raw\.githubusercontent\.com/Taekyo-Lee/harness-interop/main/[^ )"`]*' \
    | sed 's|.*/main/||' | sed 's|[\\]*$||' || true)"   # URL 없는 README 는 정상 (grep exit 1 무시)
done
urls="$(printf '%s\n' $urls | sed '/^$/d' | sort -u || true)"
for u in $urls; do
  if has "$u"; then ok "raw URL 실존: $u"; else bad "raw URL 404 예정: $u"; fi
done

echo "[$REF] 6. 제품별 추가 계약"
# memory-bridge-claude: 동기화 hook 3종 (수렴 설계의 핵심 — 회귀 방지)
if has "plugins-claude/memory-bridge-claude/hooks/hooks.json"; then
  if git show "$REF:plugins-claude/memory-bridge-claude/hooks/hooks.json" 2>/dev/null \
     | jq -e '.hooks | has("Stop") and has("SessionStart") and has("SessionEnd")' >/dev/null 2>&1; then
    ok "memory-bridge-claude: Stop+SessionStart+SessionEnd"
  else
    bad "memory-bridge-claude: hooks 이벤트 구성 회귀"
  fi
else
  bad "누락: plugins-claude/memory-bridge-claude/hooks/hooks.json"
fi

echo ""
if [ "$fail" -eq 0 ]; then
  echo "✓ RELEASE OK — 배포 계약 전부 충족 ($REF)"
else
  echo "✗ FAIL — 위 ✗ 항목을 웹에서 수정 후 pull → 재실행" >&2
  exit 1
fi
