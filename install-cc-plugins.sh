#!/usr/bin/env bash
# install-cc-plugins.sh — plugins-claude/ 의 Claude Code 플러그인들을 터미널에서 설치.
# Claude Code REPL 의 다음 명령들과 동일합니다:
#   /plugin marketplace add Taekyo-Lee/harness-interop
#   /plugin install <플러그인>@harness-interop
#
# 사용:
#   ./install-cc-plugins.sh                              # 대화형: 플러그인 선택 → 설치 범위 선택
#   ./install-cc-plugins.sh user                         # 범위만 지정, 플러그인은 대화형 선택
#   ./install-cc-plugins.sh user memory-bridge-claude    # 완전 비대화형 (범위 + 플러그인들)
# TTY 가 없으면(curl | bash 등) 전체 플러그인을 user 범위로 설치합니다.
set -euo pipefail

MARKETPLACE_REPO="Taekyo-Lee/harness-interop"
MARKETPLACE_NAME="harness-interop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/plugins-claude"

# ── 색 (TTY + NO_COLOR 미설정일 때만; 로그/파이프에선 평문)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; D=$'\033[2m'; CY=$'\033[36m'; GR=$'\033[32m'; RD=$'\033[31m'; R=$'\033[0m'
else
  B=""; D=""; CY=""; GR=""; RD=""; R=""
fi
say()  { printf '%b\n' "$*"; }
die()  { say "${RD}✗ $*${R}" >&2; exit 1; }

command -v claude >/dev/null 2>&1 \
  || die "'claude' CLI 를 찾을 수 없습니다 — Claude Code 설치 후 다시 실행하세요."

say ""
say "${B}${CY}harness-interop${R}${B} · Claude Code 플러그인 설치${R}"
say "${D}https://github.com/Taekyo-Lee/harness-interop${R}"

# ── 설치 가능한 플러그인 목록: plugins-claude/<이름>/ (폴더명 = 플러그인명 컨벤션)
plugins=()
if [ -d "$PLUGINS_DIR" ]; then
  for d in "$PLUGINS_DIR"/*/; do
    [ -f "$d/.claude-plugin/plugin.json" ] && plugins+=("$(basename "$d")")
  done
fi
# repo 밖 단독 실행(스크립트만 받은 경우) 대비 기본 목록
[ "${#plugins[@]}" -gt 0 ] || plugins=("memory-bridge-claude")

# ── 인자: $1 = scope, $2.. = 플러그인 이름 (모두 선택사항)
scope="${1:-}"
selected=()
[ "$#" -ge 2 ] && selected=("${@:2}")

if [ -t 0 ]; then
  # [1/2] 플러그인 선택 (인자로 받지 않았을 때)
  if [ "${#selected[@]}" -eq 0 ]; then
    say ""
    say "${B}[1/2] 설치할 플러그인${R}"
    i=1
    for name in "${plugins[@]}"; do
      desc=""
      pj="$PLUGINS_DIR/$name/.claude-plugin/plugin.json"
      if command -v jq >/dev/null 2>&1 && [ -f "$pj" ]; then
        desc="$(jq -r '.description // ""' "$pj" 2>/dev/null || true)"
      fi
      say "  ${CY}$i)${R} ${B}$name${R}"
      [ -n "$desc" ] && say "     ${D}$desc${R}"
      i=$((i + 1))
    done
    printf '%b' "  선택 ${D}(공백/쉼표 구분 · a 또는 엔터 = 전부)${R} ❯ "
    read -r answer
    answer="${answer//,/ }"
    if [ -z "$answer" ] || [ "$answer" = "a" ] || [ "$answer" = "A" ]; then
      selected=("${plugins[@]}")
    else
      for tok in $answer; do
        case "$tok" in
          *[!0-9]*) die "잘못된 선택: $tok" ;;
        esac
        idx=$((tok - 1))
        { [ "$idx" -ge 0 ] && [ "$idx" -lt "${#plugins[@]}" ]; } || die "범위 밖 번호: $tok"
        selected+=("${plugins[$idx]}")
      done
    fi
  fi
  # [2/2] 설치 범위 선택 (인자로 받지 않았을 때)
  if [ -z "$scope" ]; then
    say ""
    say "${B}[2/2] 설치 위치${R}  ${D}(현재 프로젝트: $PWD)${R}"
    say "  ${CY}1)${R} ${B}user${R}     이 머신 전체 — 모든 프로젝트에서 동작  ${D}[기본]${R}"
    say "  ${CY}2)${R} ${B}project${R}  이 프로젝트에서, 팀과 공유      ${D}.claude/settings.json (commit 대상)${R}"
    say "  ${CY}3)${R} ${B}local${R}    이 프로젝트에서, 나만           ${D}.claude/settings.local.json (gitignored)${R}"
    printf '%b' "  선택 ${D}(1/2/3 · 엔터 = 1)${R} ❯ "
    read -r choice
    case "${choice:-1}" in
      1) scope="user" ;;
      2) scope="project" ;;
      3) scope="local" ;;
      *) die "잘못된 선택입니다: $choice" ;;
    esac
  fi
else
  # 비대화형 기본값
  [ -n "$scope" ] || scope="user"
  [ "${#selected[@]}" -gt 0 ] || selected=("${plugins[@]}")
fi

case "$scope" in
  user|project|local) ;;
  *) die "scope 는 user|project|local 중 하나여야 합니다: $scope" ;;
esac

# 중복 제거 (macOS bash 3.2 호환 — mapfile 미사용)
deduped=()
for p in "${selected[@]}"; do
  dup=""
  for q in ${deduped[@]+"${deduped[@]}"}; do
    [ "$p" = "$q" ] && { dup=1; break; }
  done
  [ -n "$dup" ] || deduped+=("$p")
done
selected=("${deduped[@]}")

# ── 실행 (claude CLI 의 상세 출력은 캡처해 두고, 실패할 때만 보여줌)
say ""
say "${D}→ marketplace 준비 중 (harness-interop)…${R}"
if out_add="$(claude plugin marketplace add "$MARKETPLACE_REPO" 2>&1)"; then
  say "${GR}✓${R} marketplace 등록됨"
elif out_upd="$(claude plugin marketplace update "$MARKETPLACE_NAME" 2>&1)"; then
  say "${GR}✓${R} marketplace 갱신됨 ${D}(이미 등록되어 있음)${R}"
else
  say "${RD}✗${R} marketplace 준비 실패 — claude 출력:" >&2
  printf '%s\n' "$out_add" "${out_upd:-}" | sed 's/^/    /' >&2
  exit 1
fi

fail_n=0
for p in "${selected[@]}"; do
  say "${D}→ $p 설치 중…${R}"
  if out="$(claude plugin install "$p@$MARKETPLACE_NAME" --scope "$scope" 2>&1)"; then
    say "${GR}✓${R} ${B}$p${R} ${D}(scope: $scope)${R}"
  else
    say "${RD}✗${R} $p 설치 실패 — claude 출력:" >&2
    printf '%s\n' "$out" | sed 's/^/    /' >&2
    fail_n=$((fail_n + 1))
  fi
done

say ""
[ "$fail_n" -eq 0 ] || die "${fail_n}개 플러그인 설치 실패"
say "${GR}${B}✓ 완료${R} — ${selected[*]} ${D}(scope: $scope)${R}"
say "${D}다음 Claude Code 세션을 종료(SessionEnd)하면 <project>/.opencode/from-claude.md 가 생성됩니다.${R}"
