#!/usr/bin/env bash
# plugins-opencode/install.sh — 이 폴더의 OpenCode 플러그인들을 설치 (파일 복사 방식).
# OpenCode 는 marketplace 가 없습니다. 다음 위치의 *.ts 를 자동 발견합니다:
#   project: <프로젝트>/.opencode/plugin/*.ts              [고정]
#   global : ~/.config/opencode/plugin/*.ts                [UI 비활성 — 인자로만 강제 가능, 책임은 사용자에게]
#            (자가 설정형 플러그인이라 global 로 깔면 여는 모든 프로젝트가 수정됨)
#
# 사용 (동기화할 프로젝트 루트에서):
#   bash plugins-opencode/install.sh                              # 대화형: 체크박스 → 위치 확정(project 고정)
#   bash plugins-opencode/install.sh project                      # 위치만 지정 (현재 디렉토리 기준)
#   bash plugins-opencode/install.sh project memory-bridge-opencode  # 완전 비대화형
#   bash <(curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-opencode/install.sh)
# TTY 가 없으면(curl | bash 등) 전체 플러그인을 현재 프로젝트(project)에 설치합니다.
set -euo pipefail

RAW_BASE="https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"   # 파이프 실행(curl|bash)이면 BASH_SOURCE 가 비어 cwd 가 됨
PLUGINS_DIR="$SCRIPT_DIR"   # 이 스크립트는 plugins-opencode/ 안에 살고, 형제 폴더들이 곧 플러그인

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
  # [2/2] 설치 위치 — project 고정. global 은 제거하지 않고 "비활성"으로 보여줌:
  # 막혀 있다는 사실과 그 이유 자체가 이 플러그인의 설계 설명이기 때문.
  if [ -z "$scope" ]; then
    s_names=("project" "global")
    s_enabled=("1" "")
    s_descs=("현재 프로젝트만 — $PWD/.opencode/plugin/  ${GR}[고정]${R}" \
             "${D}이 머신의 모든 프로젝트 — ~/.config/opencode/plugin/  [비활성]${R}")
    s_subs=("" \
            "${D}자가 설정형 플러그인이라 global 로 깔면 여는 ${R}${RD}모든${R}${D} 프로젝트의 opencode.json·.gitignore 가 수정되어 막아두었습니다${R}")
    s_total=2
    s_cur=0
    s_notice=""
    s_lines=0

    draw_scope() {
      [ "$s_lines" -gt 0 ] && printf '\033[%dA\033[0J' "$s_lines"
      local n=0 i=0 mark ptr label
      say ""
      say "${B}[2/2] 설치 위치${R}  ${D}프로젝트 단위 동기화가 이 플러그인의 설계 — ${R}${B}project 고정${R}  ${D}enter 확정 · q 취소${R}"
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
          s_notice="'${s_names[$s_cur]}' 은(는) 비활성 옵션입니다 — project 로 확정하세요"
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
  # 비대화형 기본값
  [ -n "$scope" ] || scope="project"
  [ "${#selected[@]}" -gt 0 ] || selected=("${plugins[@]}")
fi

case "$scope" in
  project) DEST="$PWD/.opencode/plugin" ;;
  global)  DEST="$HOME/.config/opencode/plugin" ;;
  *) die "위치는 project|global 중 하나여야 합니다: $scope" ;;
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

# ── 사전설정 (memory-bridge-opencode · project 설치 전용) ──────────────────
# 플러그인의 self-config 와 같은 결과물을 설치 시점에 미리 만든다. OpenCode 는
# opencode.json 을 세션 시작 때 읽으므로, 로드 시점 self-config 만으로는 "등록한
# 그 세션"이 지침을 못 봐 첫 세션이 조용히 실패한다 (2026-06-12 실측). 멱등이며
# 플러그인 쪽이 안전망으로 같은 로직을 유지한다 — 항목을 바꾸면
# memory-bridge-opencode.ts 의 ensureSetup/ensurePersonalMd 도 함께 갱신할 것.
preconfigure_memory_bridge() {
  local proj="$PWD"

  # 1) opencode.json — instructions 에 두 파일 등록 (기존 설정 병합 보존)
  if command -v jq >/dev/null 2>&1; then
    local tmp="$proj/.opencode-json.tmp"
    { if [ -f "$proj/opencode.json" ]; then cat "$proj/opencode.json"; else echo '{}'; fi; } \
      | jq '.instructions = ((.instructions // []) + ([".opencode/personal.md", ".opencode/from-claude.md"] - (.instructions // [])))' \
      > "$tmp" && mv "$tmp" "$proj/opencode.json"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$proj/opencode.json" <<'PYEOF'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
try:
    cfg = json.loads(p.read_text(encoding="utf-8"))
except Exception:
    cfg = {}
ins = cfg.get("instructions") if isinstance(cfg.get("instructions"), list) else []
for e in [".opencode/personal.md", ".opencode/from-claude.md"]:
    if e not in ins:
        ins.append(e)
cfg["instructions"] = ins
p.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
PYEOF
  else
    return 1   # 병합 도구 없음 — 플러그인 self-config 가 받침 (첫 세션 안내만 남김)
  fi

  # 2) .gitignore — 상위 패턴(예: ".opencode/")에 이미 덮이는 항목은 건너뜀
  local gi="$proj/.gitignore" e d covered
  local add=()
  for e in ".opencode/personal.md" ".opencode/from-claude.md" ".opencode/.cc-memory-path" \
           ".opencode/plugin/memory-bridge-opencode.ts" ".opencode/memory-bridge.log"; do
    covered=""
    if [ -f "$gi" ]; then
      if grep -qxF "$e" "$gi"; then covered=1; fi
      d="$e"
      while [ -z "$covered" ] && [ "${d#*/}" != "$d" ]; do
        d="${d%/*}"
        if grep -qxF "$d/" "$gi"; then covered=1; fi
      done
    fi
    [ -n "$covered" ] || add+=("$e")
  done
  if [ "${#add[@]}" -gt 0 ]; then
    { if [ -f "$gi" ]; then sed -e '$a\' "$gi"; fi
      printf '%s\n' "${add[@]}"; } > "$gi.new" && mv "$gi.new" "$gi"
  fi

  # 3) personal.md — 메모리 안내 헤더 (플러그인의 PERSONAL_HEADER 와 동일 텍스트)
  mkdir -p "$proj/.opencode"
  local pm="$proj/.opencode/personal.md" head_ok=""
  if [ -f "$pm" ]; then
    case "$(head -c 4 "$pm")" in '<!--') head_ok=1 ;; esac
  fi
  if [ -z "$head_ok" ]; then
    { printf '%s\n' \
        '<!-- memory-bridge-opencode: this file is your project-scoped personal memory.' \
        '     When asked to remember something for this project, append it to THIS' \
        '     file (.opencode/personal.md) as a short plain bullet.' \
        '     Synced to Claude Code memory on each turn. -->' ''
      if [ -f "$pm" ]; then cat "$pm"; fi; } > "$pm.new" && mv "$pm.new" "$pm"
  fi
}

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

# memory-bridge-opencode 가 project 로 설치됐으면 사전설정까지 (첫 세션부터 동작하게)
mb_selected=""; preconfig=""
for p in "${selected[@]}"; do [ "$p" = "memory-bridge-opencode" ] && mb_selected=1; done
if [ "$scope" = "project" ] && [ -n "$mb_selected" ]; then
  if preconfigure_memory_bridge; then
    preconfig=1
    say "${GR}✓${R} 사전설정 완료 ${D}(opencode.json instructions · personal.md 헤더 · .gitignore)${R}"
  fi
fi

if [ "$scope" = "project" ]; then
  say "${GR}${B}✓ 완료${R} — ${selected[*]} ${D}($DEST)${R}"
  if [ -n "$preconfig" ]; then
    say "${D}첫 OpenCode 세션부터 바로 동작합니다 — \"○○ 기억해줘\" 로 시험해 보세요.${R}"
  elif [ -n "$mb_selected" ]; then
    say "${RD}!${R} jq/python3 이 없어 사전설정을 건너뛰었습니다 — 첫 OpenCode 세션은 자가설정 전용이고, ${B}메모리 동작은 둘째 세션부터${R}입니다."
  else
    say "${D}이 프로젝트에서 OpenCode 를 열면 플러그인이 자가 설정(opencode.json instructions + .gitignore)을 수행합니다.${R}"
  fi
else
  say "${GR}${B}✓ 완료${R} — ${selected[*]} ${D}($DEST)${R}"
  say "${D}이제 이 머신에서 여는 모든 프로젝트에 플러그인이 로드됩니다 (프로젝트별 자가 설정은 처음 열 때 수행 — 각 프로젝트의 첫 세션은 자가설정 전용, 메모리 동작은 둘째 세션부터).${R}"
fi
