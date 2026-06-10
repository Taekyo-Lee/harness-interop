#!/usr/bin/env bash
# install-cc-plugin.sh — plugins-claude/ 의 Claude Code 플러그인들을 터미널에서 설치.
# Claude Code REPL 의 다음 명령들과 동일합니다:
#   /plugin marketplace add Taekyo-Lee/harness-interop
#   /plugin install <플러그인>@harness-interop
#
# 사용:
#   ./install-cc-plugin.sh                              # 대화형: 플러그인 선택 → 설치 범위 선택
#   ./install-cc-plugin.sh user                         # 범위만 지정, 플러그인은 대화형 선택
#   ./install-cc-plugin.sh user memory-bridge-claude    # 완전 비대화형 (범위 + 플러그인들)
# TTY 가 없으면(curl | bash 등) 전체 플러그인을 user 범위로 설치합니다.
set -euo pipefail

MARKETPLACE_REPO="Taekyo-Lee/harness-interop"
MARKETPLACE_NAME="harness-interop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/plugins-claude"

command -v claude >/dev/null 2>&1 || {
  echo "error: 'claude' CLI 를 찾을 수 없습니다 — Claude Code 설치 후 다시 실행하세요." >&2
  exit 1
}

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
  # 1) 플러그인 선택 (인자로 받지 않았을 때)
  if [ "${#selected[@]}" -eq 0 ]; then
    echo "설치할 플러그인을 고르세요 (plugins-claude/):"
    i=1
    for name in "${plugins[@]}"; do
      desc=""
      pj="$PLUGINS_DIR/$name/.claude-plugin/plugin.json"
      if command -v jq >/dev/null 2>&1 && [ -f "$pj" ]; then
        desc="$(jq -r '.description // ""' "$pj" 2>/dev/null || true)"
      fi
      printf "  %d) %s%s\n" "$i" "$name" "${desc:+ — $desc}"
      i=$((i + 1))
    done
    read -r -p "번호 선택 (공백/쉼표 구분, a 또는 엔터 = 전부): " answer
    answer="${answer//,/ }"
    if [ -z "$answer" ] || [ "$answer" = "a" ] || [ "$answer" = "A" ]; then
      selected=("${plugins[@]}")
    else
      for tok in $answer; do
        case "$tok" in
          *[!0-9]*) echo "error: 잘못된 선택: $tok" >&2; exit 1 ;;
        esac
        idx=$((tok - 1))
        { [ "$idx" -ge 0 ] && [ "$idx" -lt "${#plugins[@]}" ]; } \
          || { echo "error: 범위 밖 번호: $tok" >&2; exit 1; }
        selected+=("${plugins[$idx]}")
      done
    fi
  fi
  # 2) 설치 범위 선택 (인자로 받지 않았을 때)
  if [ -z "$scope" ]; then
    echo ""
    echo "어디에 설치할까요?"
    echo "  1) user    — 이 머신 전체(~). 모든 프로젝트에서 동작  [기본]"
    echo "  2) project — 현재 프로젝트($PWD)에서, 팀과 공유 (.claude/settings.json — commit 대상)"
    echo "  3) local   — 현재 프로젝트($PWD)에서, 나만 (.claude/settings.local.json — gitignored)"
    read -r -p "선택 [1/2/3] (엔터 = 1): " choice
    case "${choice:-1}" in
      1) scope="user" ;;
      2) scope="project" ;;
      3) scope="local" ;;
      *) echo "error: 잘못된 선택입니다: $choice" >&2; exit 1 ;;
    esac
  fi
else
  # 비대화형 기본값
  [ -n "$scope" ] || scope="user"
  [ "${#selected[@]}" -gt 0 ] || selected=("${plugins[@]}")
fi

case "$scope" in
  user|project|local) ;;
  *) echo "error: scope 는 user|project|local 중 하나여야 합니다: $scope" >&2; exit 1 ;;
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

# ── marketplace 등록 — 이미 있으면 update 로 갱신 (머신 단위, scope 무관)
claude plugin marketplace add "$MARKETPLACE_REPO" 2>/dev/null \
  || claude plugin marketplace update "$MARKETPLACE_NAME"

# ── 선택된 플러그인 설치
for p in "${selected[@]}"; do
  claude plugin install "$p@$MARKETPLACE_NAME" --scope "$scope"
done

echo "done: ${selected[*]} 설치 완료 (scope: $scope)"
