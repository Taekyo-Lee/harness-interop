# 🧠 memory-bridge-claude

> **Claude Code → OpenCode** 방향의 메모리 다리. Claude Code 가 쌓은 *프로젝트 한정 개인 메모리*를 OpenCode 가 읽는 파일(`.opencode/from-claude.md`)로 자동 flatten 합니다.

양방향을 원하면 짝꿍인 [memory-bridge-opencode](../../plugins-opencode/memory-bridge-opencode/) 를 함께 설치하세요 (OpenCode → Claude Code 방향).

---

## ⚙️ 동작

```
   Claude Code                                            OpenCode
 ─────────────                                           ──────────
  ~/.claude/projects/<slug>/memory/*.md
       │   Stop(매 턴 끝) · SessionStart(시작) · SessionEnd(종료)
       └────────────── flatten ──────────────►  .opencode/from-claude.md
                                                  (opencode.json instructions 로 읽힘)
```

- **동기화는 이벤트가 아니라 수렴**: 매 턴 끝(`Stop`)마다 갱신되고, 세션 시작(`SessionStart`)에 따라잡으며, 종료(`SessionEnd`)에 마무리합니다. `Ctrl-C` 로 끊어도 마지막 완료 턴까지는 이미 동기화돼 있습니다.
- **삭제도 건너갑니다**: 메모리를 지우면 다음 동기화 때 빠지고, *전부* 지우면 `from-claude.md` 자체가 회수(삭제)됩니다.
- **에코 차단**: flatten 시 `from-opencode.md`(OpenCode 가 보낸 노트)와 `MEMORY.md`(CC 내부 인덱스)는 제외 — 되돌림 루프가 생기지 않습니다.
- **한 파일 = 한 writer**: 이 hook 은 `from-claude.md` 만 씁니다. OpenCode 쪽 파일은 읽지도 쓰지도 않습니다 (clobber-safe).
- 부가로 `.opencode/.cc-memory-path` 포인터를 남겨, 짝꿍 플러그인이 CC 메모리 위치를 추측 없이 찾게 합니다.

## 📦 설치

Claude Code 안에서:

```text
/plugin marketplace add Taekyo-Lee/harness-interop
/plugin install memory-bridge-claude@harness-interop
```

터미널 한 줄 (clone 불필요, 대화형 UI):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-claude/install.sh)
```

> **설치 범위는 `local` 고정** (`.claude/settings.local.json`, gitignored) — 개인 지침은 누구와도 공유하지 않는다는 이 repo 의 철학입니다. `user`(머신 전체)/`project`(팀 공유)는 UI 에서 이유와 함께 비활성으로 표시됩니다.

## 🚀 써보기

1. Claude Code 에서: *"Kim's favorite movie 는 Rashomon 이야, 기억해줘"* → 턴이 끝나면 `.opencode/from-claude.md` 에 flatten 됩니다.
2. 같은 프로젝트에서 OpenCode 를 열고 *"Kim's favorite movie 알아?"* → `instructions` 로 실려 있어 대답합니다.

(역방향 — OpenCode 에서 기억시켜 Claude Code 가 알게 하기 — 는 [짝꿍 플러그인](../../plugins-opencode/memory-bridge-opencode/) 이 담당합니다.)

## 📋 요구사항

- Claude Code **v2.1.0+** (플러그인 번들 hook)
- Linux / macOS / WSL (hook 이 `bash` 스크립트 — native Windows 미지원)
- `jq` 권장 (stdin payload 파싱 — 없어도 동작)

## 🔍 디버깅

hook 의 진단은 평소엔 보이지 않습니다. `claude --debug` 로 열면 stderr 에 다음 라인들이 보입니다:

```
[memory-bridge-claude] event=Stop reason=- proj=/path/to/project (via CLAUDE_PROJECT_DIR)
[memory-bridge-claude] cc_home=/home/you/.claude (via script-path(walk)) slug=...
[memory-bridge-claude] wrote /path/to/project/.opencode/from-claude.md (2 memory file(s))
```

CC 데이터 디렉토리는 `CLAUDE_CONFIG_DIR` > `CLAUDE_HOME` > 스크립트 위치 역추적 > `~/.claude` 순으로 찾습니다.
