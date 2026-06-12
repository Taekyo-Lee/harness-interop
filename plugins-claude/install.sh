#!/usr/bin/env bash
# plugins-claude/install.sh — 이 폴더의 Claude Code 플러그인들을 터미널에서 설치.
# Claude Code REPL 의 다음 명령들과 동일합니다:
#   /plugin marketplace add Taekyo-Lee/harness-interop
#   /plugin install <플러그인>@harness-interop
#
# 사용:
#   bash plugins-claude/install.sh                            # 대화형: 체크박스 → 위치 확정(local 고정)
#   bash plugins-claude/install.sh local                      # 범위만 지정, 플러그인은 대화형 선택
#   bash plugins-claude/install.sh local memory-bridge-claude # 완전 비대화형 (범위 + 플러그인들)
#   bash <(curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-claude/install.sh)
# TTY 가 없으면(curl | bash 등) 전체 플러그인을 local 범위로 설치합니다.
# (개인 지침은 누구와도 공유하지 않는 게 철학 — UI 에선 local 고정이며 user/project 는
#  비활성으로 표시됩니다. 정말 필요하면 인자로만 강제 가능: 책임은 사용자에게.)
set -euo pipefail

MARKETPLACE_REPO="Taekyo-Lee/harness-interop"
MARKETPLACE_NAME="harness-interop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"   # 파이프 실행(curl|bash)이면 BASH_SOURCE 가 비어 cwd 가 됨
PLUGINS_DIR="$SCRIPT_DIR"   # 이 스크립트는 plugins-claude/ 안에 살고, 형제 폴더들이 곧 플러그인

# ── 색·커서 제어 (TTY + NO_COLOR 미설정일 때만; 로그/파이프에선 평문·재그리기 없음)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; D=$'\033[2m'; CY=$'\033[36m'; GR=$'\033[32m'; RD=$'\033[31m'; R=$'\033[0m'
  BN=$'\033[44m\033[97;1m'   # 배너: 파랑 배경 + 밝은 흰 글자
  ST=$'\033[9m'              # 취소선 (비활성 옵션)
  can_redraw=1
else
  B=""; D=""; CY=""; GR=""; RD=""; R=""; BN=""; ST=""
  can_redraw=""
fi
say()  { printf '%b\n' "$*"; }
die()  { say "${RD}✗ $*${R}" >&2; exit 1; }
show_cursor() { [ -n "$can_redraw" ] && printf '\033[?25h' || true; }
trap show_cursor EXIT

command -v claude >/dev/null 2>&1 \
  || die "'claude' CLI 를 찾을 수 없습니다 — Claude Code 설치 후 다시 실행하세요."

say ""
say "${BN}  harness-interop · Claude Code 플러그인 설치  ${R}"
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

if [ -t 0 ] && [ -t 1 ]; then
  # [1/2] 플러그인 선택 — ↑↓ 이동, space 토글, a 모두, enter 확정, q/ESC 취소
  if [ "${#selected[@]}" -eq 0 ]; then
    descs=()
    for name in "${plugins[@]}"; do
      d_=""
      pj="$PLUGINS_DIR/$name/.claude-plugin/plugin.json"
      if command -v jq >/dev/null 2>&1 && [ -f "$pj" ]; then
        d_="$(jq -r '.description // ""' "$pj" 2>/dev/null || true)"
      fi
      descs+=("$d_")
    done
    checked=()
    for _ in "${plugins[@]}"; do checked+=("1"); done   # 기본: 전부 체크
    total="${#plugins[@]}"
    cur=0
    notice=""
    menu_lines=0

    draw_menu() {
      [ "$menu_lines" -gt 0 ] && printf '\033[%dA\033[0J' "$menu_lines"
      local n=0 i=0 box ptr label
      say ""
      say "${B}[1/2] 설치할 플러그인${R}  ${D}↑↓ 이동 · space 토글 · a 모두 선택/해제 · enter 확정 · q 취소${R}"
      n=2
      i=0
      for name in "${plugins[@]}"; do
        if [ -n "${checked[$i]}" ]; then box="${GR}[✓]${R}"; else box="${D}[ ]${R}"; fi
        if [ "$i" -eq "$cur" ]; then ptr="${CY}❯${R}"; label="${B}${CY}$name${R}"; else ptr=" "; label="$name"; fi
        say "  $ptr $box $label"
        n=$((n + 1))
        if [ -n "${descs[$i]}" ]; then
          say "          ${D}${descs[$i]}${R}"
          n=$((n + 1))
        fi
        i=$((i + 1))
      done
      if [ -n "$notice" ]; then
        say "  ${RD}$notice${R}"
        n=$((n + 1))
        notice=""
      fi
      menu_lines="$n"
    }

    toggle_all() {
      local all="1" i=0
      for _ in "${plugins[@]}"; do [ -z "${checked[$i]}" ] && all=""; i=$((i + 1)); done
      i=0
      for _ in "${plugins[@]}"; do
        if [ -n "$all" ]; then checked[$i]=""; else checked[$i]="1"; fi
        i=$((i + 1))
      done
    }

    [ -n "$can_redraw" ] && printf '\033[?25l'
    while :; do
      draw_menu
      IFS= read -rsn1 key || true
      case "$key" in
        "")
          selected=()
          i=0
          for name in "${plugins[@]}"; do
            [ -n "${checked[$i]}" ] && selected+=("$name")
            i=$((i + 1))
          done
          [ "${#selected[@]}" -gt 0 ] && break
          notice="하나 이상 체크해야 합니다 (space 로 체크)"
          ;;
        " ")
          if [ -n "${checked[$cur]}" ]; then checked[$cur]=""; else checked[$cur]="1"; fi
          ;;
        a|A) toggle_all ;;
        q|Q) die "취소했습니다." ;;
        k)   cur=$(( (cur - 1 + total) % total )) ;;
        j)   cur=$(( (cur + 1) % total )) ;;
        $'\033')
          rest=""
          IFS= read -rsn2 -t 1 rest || true
          case "$rest" in
            "[A") cur=$(( (cur - 1 + total) % total )) ;;
            "[B") cur=$(( (cur + 1) % total )) ;;
            "")   die "취소했습니다." ;;
          esac
          ;;
      esac
    done
    show_cursor
  fi
  # [2/2] 설치 범위 — local 고정. user/project 는 제거하지 않고 "비활성"으로 보여줌:
  # 개인 지침은 누구와도 공유하지 않는다는 철학을 화면 자체가 설명하도록.
  if [ -z "$scope" ]; then
    s_names=("user" "project" "local")
    s_enabled=("" "" "1")
    s_descs=("${D}이 머신 전체 — 모든 프로젝트에서 동작  [비활성]${R}" \
             "${D}이 프로젝트에서, 팀과 공유 — .claude/settings.json  [비활성]${R}" \
             "이 프로젝트에서, 나만 — ${D}.claude/settings.local.json (gitignored)${R}  ${GR}[고정]${R}")
    s_subs=("${D}프로젝트 단위 개인 지침이라는 설계와 어긋나 막아두었습니다${R}" \
            "${D}settings.json 은 commit 되어 팀과 공유됩니다 — 개인 지침은 공유하지 않는 게 철학${R}" \
            "")
    s_total=3
    s_cur=2
    s_notice=""
    s_lines=0

    draw_scope() {
      [ "$s_lines" -gt 0 ] && printf '\033[%dA\033[0J' "$s_lines"
      local n=0 i=0 mark ptr label
      say ""
      say "${B}[2/2] 설치 위치${R}  ${D}개인 지침은 공유하지 않습니다 — ${R}${B}local 고정${R}  ${D}(현재 프로젝트: $PWD) · enter 확정 · q 취소${R}"
      n=2
      i=0
      while [ "$i" -lt "$s_total" ]; do
        if [ "$i" -eq "$s_cur" ]; then ptr="${CY}❯${R}"; else ptr=" "; fi
        if [ -n "${s_enabled[$i]}" ]; then
          if [ "$i" -eq "$s_cur" ]; then mark="${GR}(●)${R}"; label="${B}${CY}${s_names[$i]}${R}"; else mark="( )"; label="${s_names[$i]}"; fi
        else
          mark="${D}(✕)${R}"; label="${D}${ST}${s_names[$i]}${R}"
        fi
        say "  $ptr $mark $label  ${s_descs[$i]}"
        n=$((n + 1))
        if [ -n "${s_subs[$i]}" ]; then
          say "          ${s_subs[$i]}"
          n=$((n + 1))
        fi
        i=$((i + 1))
      done
      if [ -n "$s_notice" ]; then
        say "  ${RD}$s_notice${R}"
        n=$((n + 1))
        s_notice=""
      fi
      s_lines="$n"
    }

    [ -n "$can_redraw" ] && printf '\033[?25l'
    while :; do
      draw_scope
      IFS= read -rsn1 key || true
      case "$key" in
        "")
          if [ -n "${s_enabled[$s_cur]}" ]; then scope="${s_names[$s_cur]}"; break; fi
          s_notice="'${s_names[$s_cur]}' 은(는) 비활성 옵션입니다 — local 로 확정하세요"
          ;;
        q|Q) die "취소했습니다." ;;
        k)   s_cur=$(( (s_cur - 1 + s_total) % s_total )) ;;
        j)   s_cur=$(( (s_cur + 1) % s_total )) ;;
        [1-9])
          idx=$(( key - 1 ))
          [ "$idx" -lt "$s_total" ] && s_cur="$idx"
          ;;
        $'\033')
          rest=""
          IFS= read -rsn2 -t 1 rest || true
          case "$rest" in
            "[A") s_cur=$(( (s_cur - 1 + s_total) % s_total )) ;;
            "[B") s_cur=$(( (s_cur + 1) % s_total )) ;;
            "")   die "취소했습니다." ;;
          esac
          ;;
      esac
    done
    show_cursor
  fi
else
  # 비대화형 기본값 (철학 기본: local)
  [ -n "$scope" ] || scope="local"
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
out_add=""; out_upd=""; out_add2=""
if out_add="$(claude plugin marketplace add "$MARKETPLACE_REPO" 2>&1)"; then
  say "${GR}✓${R} marketplace 등록됨"
else
  # add 실패 = ① 이미 등록되어 있음 ② CLI 가 이 형태를 직접 못 받음 (전체 URL 은
  # github.com 밖 — 예: 사내 git 호스트 — 에서 미지원). ② 대비: clone 으로 받아
  # 로컬 경로로 add. 캐시 위치를 고정해 두면 재실행 때 marketplace 갱신 출처도 됨.
  cache=""
  if printf '%s' "$MARKETPLACE_REPO" | grep -q '://' && command -v git >/dev/null 2>&1; then
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/harness-interop-marketplace"
    rm -rf "$cache"
    git clone -q --depth 1 "$MARKETPLACE_REPO" "$cache" 2>/dev/null || cache=""
  fi
  if out_upd="$(claude plugin marketplace update "$MARKETPLACE_NAME" 2>&1)"; then
    say "${GR}✓${R} marketplace 갱신됨 ${D}(이미 등록되어 있음)${R}"
  elif [ -n "$cache" ] && out_add2="$(claude plugin marketplace add "$cache" 2>&1)"; then
    say "${GR}✓${R} marketplace 등록됨 ${D}(clone 경유: $cache)${R}"
  else
    say "${RD}✗${R} marketplace 준비 실패 — claude 출력:" >&2
    printf '%s\n' "$out_add" "$out_upd" "$out_add2" | sed '/^$/d; s/^/    /' >&2
    exit 1
  fi
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
