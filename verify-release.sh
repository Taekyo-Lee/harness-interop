#!/usr/bin/env bash
# verify-release.sh — 배포물(원격 트리)이 배포 계약을 지키는지 검증. 전부 read-only.
#
# 언제: 웹 반영 + git pull 직후마다. 배포(공유·공지) 전 필수 관문.
# 사용: bash verify-release.sh            # origin/main 검증 (기본)
#       bash verify-release.sh HEAD      # 로컬 commit 검증
#
# 검사 항목:
#   1) 필수 경로 존재 (플러그인 구조·설치 스크립트·README)
#   2) 금지 경로 부재 (디렉토리 평탄화 사고·비공개 노트 유출 감지)
#   3) 내용 계약 (marketplace source ↔ 실제 경로, hooks 구성, README raw URL 실존, 셸 문법)
set -euo pipefail

REF="${1:-origin/main}"
git fetch -q origin 2>/dev/null || true
tree="$(git ls-tree -r "$REF" --name-only)"

fail=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1" >&2; fail=1; }

echo "[$REF] 1. 필수 경로"
for p in \
  .claude-plugin/marketplace.json \
  plugins-claude/memory-bridge-claude/.claude-plugin/plugin.json \
  plugins-claude/memory-bridge-claude/hooks/hooks.json \
  plugins-claude/memory-bridge-claude/scripts/memory-bridge.sh \
  plugins-opencode/memory-bridge-opencode/plugin/memory-bridge-opencode.ts \
  install-cc-plugins.sh \
  install-oc-plugins.sh \
  verify-release.sh \
  README.md
do
  if printf '%s\n' "$tree" | grep -qx "$p"; then ok "$p"; else bad "누락: $p"; fi
done

echo "[$REF] 2. 금지 경로 (평탄화·유출 감지)"
forbidden_exact='
plugins-claude/memory-bridge-claude/scriptsmemory-bridge.sh
plugins-opencode/memory-bridge-opencode/memory-bridge-opencode.ts
CLAUDE.md
AGENTS.md
'
for p in $forbidden_exact; do
  if printf '%s\n' "$tree" | grep -qx "$p"; then bad "존재하면 안 됨: $p"; else ok "없음: $p"; fi
done
if printf '%s\n' "$tree" | grep -q '^_reference/'; then bad "존재하면 안 됨: _reference/*"; else ok "없음: _reference/*"; fi

echo "[$REF] 3. 내용 계약"
if command -v jq >/dev/null 2>&1; then
  # marketplace 의 모든 source 가 실제 플러그인 디렉토리를 가리키는가
  for s in $(git show "$REF:.claude-plugin/marketplace.json" | jq -r '.plugins[].source'); do
    rel="${s#./}"
    if printf '%s\n' "$tree" | grep -q "^${rel}/.claude-plugin/plugin.json"; then
      ok "marketplace source 유효: $s"
    else
      bad "marketplace source 가 깨진 경로: $s"
    fi
  done
  # hooks.json: JSON 유효 + 이벤트 3종
  if git show "$REF:plugins-claude/memory-bridge-claude/hooks/hooks.json" 2>/dev/null \
     | jq -e '.hooks | has("Stop") and has("SessionStart") and has("SessionEnd")' >/dev/null 2>&1; then
    ok "hooks.json: Stop+SessionStart+SessionEnd"
  else
    bad "hooks.json: JSON 불량 또는 이벤트 누락"
  fi
  # plugin.json: name/version 존재
  v="$(git show "$REF:plugins-claude/memory-bridge-claude/.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // empty')"
  if [ -n "$v" ]; then ok "plugin.json version: $v"; else bad "plugin.json: version 없음"; fi
else
  echo "  ! jq 없음 — JSON 계약 검사 생략" >&2
fi

# README 의 raw URL 들이 트리에 실존하는가 (404 예방)
urls="$(git show "$REF:README.md" 2>/dev/null \
  | grep -o 'raw\.githubusercontent\.com/Taekyo-Lee/harness-interop/main/[^ )"`]*' \
  | sed 's|.*/main/||' | sed 's|[\\]*$||' | sort -u)"
if [ -n "$urls" ]; then
  for u in $urls; do
    if printf '%s\n' "$tree" | grep -qx "$u"; then ok "raw URL 실존: $u"; else bad "raw URL 404 예정: $u"; fi
  done
else
  ok "README 에 raw URL 없음 (검사 대상 없음)"
fi

# 셸 스크립트 문법 (원격 내용 그대로)
for s in install-cc-plugins.sh install-oc-plugins.sh plugins-claude/memory-bridge-claude/scripts/memory-bridge.sh; do
  if git show "$REF:$s" 2>/dev/null | bash -n 2>/dev/null; then ok "bash -n: $s"; else bad "셸 문법 또는 파일 없음: $s"; fi
done

echo ""
if [ "$fail" -eq 0 ]; then
  echo "✓ RELEASE OK — 배포 계약 전부 충족 ($REF)"
else
  echo "✗ FAIL — 위 ✗ 항목을 웹에서 수정 후 pull → 재실행" >&2
  exit 1
fi
