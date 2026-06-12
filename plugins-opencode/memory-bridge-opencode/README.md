# 🧠 memory-bridge-opencode

> **OpenCode → Claude Code** 방향의 메모리 다리. OpenCode 에서 남긴 개인 노트(`.opencode/personal.md`)를 Claude Code 의 프로젝트 메모리(`from-opencode.md`)로 매 턴 자동 복사하고, Claude Code 쪽 지식이 비어 있으면 부트스트랩까지 해 줍니다.

양방향을 원하면 짝꿍인 [memory-bridge-claude](../../plugins-claude/memory-bridge-claude/) 를 함께 설치하세요 (Claude Code → OpenCode 방향).

---

## ⚙️ 동작

OpenCode 가 이 플러그인을 로드할 때마다 **수렴 시퀀스**가 돕니다:

```
로드 시:   ① from-claude.md 가 없으면 CC 메모리에서 직접 부트스트랩 (있으면 절대 안 건드림)
          ② stray 메모 회수: GPT/o 계열의 시스템 프롬프트("beast")가
             .github/instructions/memory.instruction.md 에 적어둔 메모를 personal.md 로 이동
          ③ 밀린 동기화 따라잡기
매 턴 끝:  ②③ 반복 — personal.md → ~/.claude/projects/<slug>/memory/from-opencode.md 복사
                     + CC 의 MEMORY.md 인덱스 한 줄 갱신 (항상 한 줄, "+N more" 로 총량 표시)
```

- **종료 방식 무관**: `/exit`·`/quit`·`Ctrl-C` 어느 쪽이든 — 매 턴 동기화 + 다음 로드 catch-up 으로 수렴합니다.
- **삭제도 건너갑니다**: 노트가 전부 비워지면 `from-opencode.md` 를 삭제하고 MEMORY.md 인덱스 줄도 제거합니다 (처음부터 빈 신규 설치에는 아무것도 만들지 않음).
- **자가 설정**: 처음 로드 때 `opencode.json` instructions 등록, `.gitignore` 항목 추가, `personal.md` 안내 헤더 생성을 알아서 합니다 — 파일을 떨어뜨리는 것이 설치의 전부입니다.
- **Copilot 보호**: `.github/instructions/*.md` 중 frontmatter 에 `applyTo:` 가 있는 **진짜 VS Code Copilot 설정 파일은 절대 읽지도 지우지도 않습니다.**
- **한 파일 = 한 writer**: 이 플러그인은 `from-opencode.md` 만 쓰고, `from-claude.md` 는 (없을 때의 부트스트랩 1회를 제외하면) 주인인 CC hook 에게 맡깁니다 (clobber-safe).

> OpenCode 가 "기억해줘"를 `personal.md` 에 적는 이유: 플러그인이 그 파일 헤더에 "기억 요청이 오면 여기 적어라" 안내를 넣고 `opencode.json` 의 `instructions` 로 등록하기 때문입니다. 팀 공유 파일(`AGENTS.md`)이 아닌 gitignored `personal.md` 를 쓰는 것 — 개인 메모리가 팀 repo 로 새지 않게 하기 위함입니다.

## 📦 설치

동기화할 프로젝트 루트에서 한 줄 (clone 불필요, 대화형 UI):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-opencode/install.sh)
```

설치 스크립트는 파일 복사에 더해 **사전설정**(opencode.json `instructions` 등록 + `personal.md` 안내 헤더 + `.gitignore`)까지 마치므로 **첫 OpenCode 세션부터 바로 동작**합니다.

또는 파일 직접 다운로드:

```bash
mkdir -p .opencode/plugin
curl -fsSL \
  https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-opencode/memory-bridge-opencode/plugin/memory-bridge-opencode.ts \
  -o .opencode/plugin/memory-bridge-opencode.ts
```

> ⚠ **직접 다운로드(파일 복사만)로 설치한 경우**: 설정은 플러그인이 첫 로드 때 스스로 하지만, OpenCode 가 `opencode.json` 을 세션 시작 때 읽는 탓에 **그 첫 세션의 모델은 메모리 지침을 보지 못합니다** (화면에 안내 한 줄이 출력됨). **메모리 동작은 둘째 세션부터** — 설치 스크립트 경로엔 이 제약이 없습니다.

> **설치 위치는 현재 프로젝트 고정** (`.opencode/plugin/`). global(`~/.config/opencode/plugin/`) 은 자가 설정형 플러그인이 *여는 모든 프로젝트*를 수정하게 되어 UI 에서 이유와 함께 비활성으로 표시됩니다.

**업데이트** = 같은 명령 재실행 (덮어쓰기, "갱신됨" 표시). `.opencode/` 삭제는 불필요합니다.

> **참고 — 처음 열 때 `.opencode/node_modules` (~60MB) 가 생깁니다.** 이 플러그인의 의존성이 아닙니다 (단일 파일, 0 dependency). OpenCode 가 `.opencode/` 디렉토리가 있는 모든 프로젝트에 SDK 를 자동 설치하는 자체 동작으로, OpenCode 가 `.opencode/.gitignore` 로 스스로 가리므로 repo 는 오염되지 않습니다.

## 🚀 써보기

1. OpenCode 에서: *"Henry 별명은 IRON MAN, 기억해줘"* → 모델이 `personal.md` 에 적고, 턴이 끝나면 CC memory 로 복사됩니다.
2. Claude Code 를 열고 *"Henry 별명 알아?"* → `MEMORY.md` 인덱스에서 보고 대답합니다.

(역방향은 [짝꿍 플러그인](../../plugins-claude/memory-bridge-claude/) 이 담당합니다.)

## 📋 요구사항

- OpenCode (로컬 `.ts` 플러그인 자동 발견 지원 버전)
- Linux / macOS / WSL

## 🔍 디버깅

진단은 OpenCode 화면을 더럽히지 않고 `.opencode/memory-bridge.log` 에 쌓입니다 (로드마다 비워져 항상 현재 세션 분량). 실시간으로 보고 싶으면:

```bash
MEMORY_BRIDGE_DEBUG=1 opencode    # stderr 에코 추가
```

CC 메모리 위치는 `.opencode/.cc-memory-path` 포인터(짝꿍 hook 이 남김) > `CLAUDE_CONFIG_DIR` > `~/.claude` > `~/.claude-fork` 순으로 찾습니다 — 설치(데이터 디렉토리) 단위로 판정하므로, 비어 있는 production 을 두고 다른 환경의 옛 메모리가 끼어드는 일은 없습니다.
