#!/usr/bin/env bash
# install-oc-plugins.sh — plugins-opencode/ 의 OpenCode 플러그인들을 설치 (파일 복사 방식).
# OpenCode 는 marketplace 가 없습니다. 다음 위치의 *.ts 를 자동 발견합니다:
#   global : ~/.config/opencode/plugin/*.ts        (이 머신의 모든 프로젝트)  [기본]
#   project: <프로젝트>/.opencode/plugin/*.ts
#
# 사용:
#   ./install-oc-plugins.sh                                 # 대화형: 체크박스 → 라디오 선택
#   ./install-oc-plugins.sh global                          # 위치만 지정
#   ./install-oc-plugins.sh global memory-bridge-opencode   # 완전 비대화형
# TTY 가 없으면(curl | bash 등) 전체 플러그인을 global 로 설치합니다.
set -euo pipefail

RAW_BASE="https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/plugins-opencode"

# ── 색·커서 제어 (TTY + NO_COLOR 미설정일 때만; 로그/파이프에선 평문·재그리기 없음)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; D=$'\033[2m'; CY=$'\033[36m'; GR=$'\033[32m'; RD=$'\033[31m'; R=$'\033[0m'
  BN=$'\033[44m\033[97;1m'   # 배너: 파랑 배경 + 밝은 흰 글자
  can_redraw=1
else
  B=""; D=""; CY=""; GR=""; RD=""; R=""; BN=""
  can_redraw=""
fi
say()  { printf '%b\n' "$*"; }
die()  { say "${RD}✗ $*${R}" >&2; exit 1; }
show_cursor() { [ -n "$can_redraw" ] && printf '\033[?25h' || true; }
trap show_cursor EXIT

say ""
say "${BN}  harness-interop · OpenCode 플러그인 설치  ${R}"
say "${D}https://github.com/Taekyo-Lee/harness-interop${R}"

# ── 설치 가능한 플러그인 목록: plugins-opencode/<이름>/plugin/*.ts
plugins=()
if [ -d "$PLUGINS_DIR" ]; then
  for dir in "$PLUGINS_DIR"/*/; do
    name="$(basename "$dir")"
    for ts in "$dir"plugin/*.ts; do
      [ -f "$ts" ] && { plugins+=("$name"); break; }
    done
  done
fi
# repo 밖 단독 실행(스크립트만 받은 경우) 대비 기본 목록 — curl 로 받아옴
[ "${#plugins[@]}" -gt 0 ] || plugins=("memory-bridge-opencode")

# ── 인자: $1 = 위치(global|project), $2.. = 플러그인 이름 (모두 선택사항)
scope="${1:-}"
selected=()
[ "$#" -ge 2 ] && selected=("${@:2}")

if [ -t 0 ] && [ -t 1 ]; then
  # [1/2] 플러그인 선택 — ↑↓ 이동, space 토글, a 모두, enter 확정, q/ESC 취소
  if [ "${#selected[@]}" -eq 0 ]; then
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
  # [2/2] 설치 위치 — 라디오 버튼: ↑↓ 이동(커서 = 선택), enter 확정
  if [ -z "$scope" ]; then
    s_names=("global" "project")
    s_descs=("이 머신의 모든 프로젝트 — ~/.config/opencode/plugin/  ${D}[기본]${R}" \
             "현재 프로젝트만 — $PWD/.opencode/plugin/")
    s_subs=("${D}여는 모든 프로젝트에서 플러그인이 동작합니다 (opencode.json 자가 설정 포함)${R}" \
            "")
    s_total=2
    s_cur=0
    s_lines=0

    draw_scope() {
      [ "$s_lines" -gt 0 ] && printf '\033[%dA\033[0J' "$s_lines"
      local n=0 i=0 mark ptr label
      say ""
      say "${B}[2/2] 설치 위치${R}  ${D}↑↓ 이동 · enter 확정 · q 취소${R}"
      n=2
      i=0
      while [ "$i" -lt "$s_total" ]; do
        if [ "$i" -eq "$s_cur" ]; then mark="${GR}(●)${R}"; ptr="${CY}❯${R}"; label="${B}${CY}${s_names[$i]}${R}"; else mark="${D}( )${R}"; ptr=" "; label="${s_names[$i]}"; fi
        say "  $ptr $mark $label  ${s_descs[$i]}"
        n=$((n + 1))
        if [ -n "${s_subs[$i]}" ]; then
          say "          ${s_subs[$i]}"
          n=$((n + 1))
        fi
        i=$((i + 1))
      done
      s_lines="$n"
    }

    [ -n "$can_redraw" ] && printf '\033[?25l'
    while :; do
      draw_scope
      IFS= read -rsn1 key || true
      case "$key" in
        "")  scope="${s_names[$s_cur]}"; break ;;
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
  # 비대화형 기본값
  [ -n "$scope" ] || scope="global"
  [ "${#selected[@]}" -gt 0 ] || selected=("${plugins[@]}")
fi

case "$scope" in
  global)  DEST="$HOME/.config/opencode/plugin" ;;
  project) DEST="$PWD/.opencode/plugin" ;;
  *) die "위치는 global|project 중 하나여야 합니다: $scope" ;;
esac

# 중복 제거 (macOS bash 3.2 호환)
deduped=()
for p in "${selected[@]}"; do
  dup=""
  for q in ${deduped[@]+"${deduped[@]}"}; do
    [ "$p" = "$q" ] && { dup=1; break; }
  done
  [ -n "$dup" ] || deduped+=("$p")
done
selected=("${deduped[@]}")

# ── 설치 = 파일 복사 (repo 사본 우선, 없으면 GitHub raw 에서 다운로드)
say ""
mkdir -p "$DEST"
fail_n=0
for name in "${selected[@]}"; do
  say "${D}→ $name 설치 중…${R}"
  src_dir="$PLUGINS_DIR/$name/plugin"
  installed=""
  # 1) repo 사본 우선 (clone 받아 실행한 경우 — push 없이도 현재 트리 기준으로 설치)
  if [ -d "$src_dir" ]; then
    for ts in "$src_dir"/*.ts; do
      [ -f "$ts" ] || continue
      base="$(basename "$ts")"
      verb="설치됨"; [ -f "$DEST/$base" ] && verb="갱신됨"
      cp "$ts" "$DEST/$base"
      say "${GR}✓${R} ${B}$name${R}/$base $verb ${D}→ $DEST/${R}"
      installed=1
    done
  fi
  # 2) repo 사본이 없거나 비어 있으면 GitHub raw 다운로드 (임시파일 경유 — 실패해도 기존 파일 보존)
  if [ -z "$installed" ]; then
    url="$RAW_BASE/plugins-opencode/$name/plugin/$name.ts"
    tmp="$DEST/.$name.ts.download"
    verb="설치됨"; [ -f "$DEST/$name.ts" ] && verb="갱신됨"
    if curl -fsSL "$url" -o "$tmp" 2>/dev/null; then
      mv "$tmp" "$DEST/$name.ts"
      say "${GR}✓${R} ${B}$name${R}.ts $verb ${D}(GitHub raw) → $DEST/${R}"
      installed=1
    else
      rm -f "$tmp"
    fi
  fi
  if [ -z "$installed" ]; then
    say "${RD}✗${R} $name — repo 에 plugin/*.ts 가 없고, GitHub raw 다운로드도 실패 ${D}($url)${R}" >&2
    fail_n=$((fail_n + 1))
  fi
done

say ""
[ "$fail_n" -eq 0 ] || die "${fail_n}개 플러그인 설치 실패"
if [ "$scope" = "project" ]; then
  say "${GR}${B}✓ 완료${R} — ${selected[*]} ${D}($DEST)${R}"
  say "${D}이 프로젝트에서 OpenCode 를 열면 플러그인이 자가 설정(opencode.json instructions + .gitignore)을 수행합니다.${R}"
else
  say "${GR}${B}✓ 완료${R} — ${selected[*]} ${D}($DEST)${R}"
  say "${D}이제 이 머신에서 여는 모든 프로젝트에 플러그인이 로드됩니다 (프로젝트별 자가 설정은 처음 열 때 수행).${R}"
fi
