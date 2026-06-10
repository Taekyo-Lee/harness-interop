# harness-interop — 작업 맥락

이 repo 에서 일하는 Claude Code 세션을 위한 운영 노트. 블로그 repo (`taekyo-lee.github.io`) 에서 설계해 온 것을 **실제 배포물**로 옮겨 만드는 곳.

---

## 목적

Claude Code 와 OpenCode 를 함께 쓸 때, **project-scoped 개인 지침**을 두 harness 사이에서 *양방향 자동 동기화*하는 플러그인 묶음. 블로그 글 (claude-code-vs-opencode 시리즈, `personal-instructions-two-harnesses`) 의 §3 "한 걸음 더" 가 가리키는 결과물이고, 글에서 "plugin 형태로 만들어 올려놨어요. 사용법은 가이드를 참고하세요" 로 링크할 대상.

두 방향 (clobber-safe 4파일 레이아웃, 상세는 `_reference/hook-sync-research.md` §6):

| 방향 | 발화점 | 하는 일 |
|---|---|---|
| Claude Code → OpenCode | `SessionEnd` hook | memory 폴더를 flatten → `<project>/.opencode/from-claude.md` (단 `from-opencode.md` 제외 = 에코 차단) |
| OpenCode → Claude Code | `session.idle` plugin | `<project>/.opencode/personal.md` → `~/.claude/projects/<slug>/memory/from-opencode.md` 복사 |

핵심 함정 = **상호 덮어쓰기(clobber)**. 각 harness 는 *자기 출처에만 쓰고 상대 출처는 읽기만*, 건너온 내용은 별도 파일로 받고, 에코(되돌림) 차단. (이게 load-bearing.)

---

## 철칙 (반드시 지킬 것)

1. **동작 검증은 저자가 직접 한다.** Claude 는 *코드 + 복붙 가능한 step-by-step 가이드* (각 step 에 "관찰할 자리" 명시) 만 작성. `claude`/`opencode` 를 sandbox·tmp 에서 직접 돌려 그 출력을 fact 로 doc·코드에 반영하는 것 **금지**. 흐름은 단방향: *저자가 실행·관찰·보고* → *Claude 가 반영*.
2. **검증은 forks 로 한다.** 저자는 production 바이너리가 아니라 **`claude-code-fork`** / **`opencode-fork`** 로 테스트한다. 그래야 **Langfuse trace** 가 보이기 때문. 가이드를 쓸 때 Langfuse 셋업 단계는 생략 (이미 세팅됨), *trace 에서 봐야 할 자리* 만 안내.
   - OpenCode 소스 그라운딩 기준: `~/workspace/opencode-fork` HEAD `27e74d32b` (2026-06-04). `_reference/*` 의 file:line 인용은 이 commit 기준.
3. **Claude 자동 commit 금지.** `git add`/`commit`/`push` 는 저자가 수동으로.

---

## 결정된 것

- **배포 형태 = 설치형 플러그인** (복붙 레퍼런스 아님).
  - CC 쪽 = **Claude Code 플러그인** (`SessionEnd` hook + 셸 스크립트를 번들).
  - OC 쪽 = **`@opencode-ai/plugin`** 모듈.
- **이 repo 가 marketplace 역할** — 루트에 `.claude-plugin/marketplace.json` 을 두면 `/plugin marketplace add Taekyo-Lee/harness-interop` 로 설치 가능. (repo/마켓플레이스 이름 = `harness-interop`; 옛 이름 `multi-harness-plugins` 에서 변경. GitHub repo rename + 로컬 디렉토리는 저자가 별도 처리 — 로컬 dir 을 옮기면 CC memory slug 도 바뀜에 주의.)
- 검증된 CC 플러그인 / marketplace 스키마 → **`_reference/cc-plugin-schema.md`** (docs 로 확인 완료, 재조사 불필요).
- **빌드 순서: CC→OC 먼저, OC→CC 나중.** CC→OC 는 자기 프로젝트 안에만 쓰니 slug 매칭(G) 급소 의존이 없어 가장 안전. OC→CC 가 slug 동일성(G)을 탐.

### 확장 컨벤션 (2026-06-10 확정 — 새 기능/플러그인 추가 시 이 규칙대로)

- **1 플러그인 = 1 self-contained 폴더, 폴더명 = 플러그인명.** 같은 플러그인의 기능 확장(hook 이벤트·MCP·skill 추가)은 그 폴더 *안*에 (hooks.json 한 파일에 이벤트 여러 개 가능, MCP 는 루트 `.mcp.json`, skills 는 `skills/`). *따로 켜고 끌 단위*가 되는 기능만 새 폴더 + marketplace entry. 새 harness bridge 도 동일한 명명 (예: Codex 용이면 `memory-bridge-codex/`). 플러그인 폴더는 harness 별 grouping 아래에 둔다: CC 용은 `plugins-claude/`, OC 용은 `plugins-opencode/` (2026-06-10 grouping; 새 harness 면 `plugins-<harness>/`).
- **플러그인 간 재사용 = `dependencies`, 사본 금지.** 다른 플러그인의 hook 동작이 필요하면 plugin.json `"dependencies": ["memory-bridge-claude"]` (자동 설치 + enable 연쇄 — `cc-plugin-schema.md` §6.5). 같은 hook 을 두 플러그인에 복사하면 2회 실행 + drift.
- **`resources/` = 컴포넌트 수집 공간, pool entry 는 보류.** `resources/{skills,hooks,scripts}` 는 장차 들어갈 컴포넌트의 개발·수집 공간 (저자 스캐폴드 — 지우지 말 것. 빈 폴더는 git 미추적이라 내용물이 생겨야 공개 repo 에 노출됨). marketplace 노출 — anthropics/skills 패턴의 pool entry (`source: "./resources"` + `strict:false` + entry 별 컴포넌트 열거, §6 기록) — 는 *skills 가 쌓여 번들이 필요해지는* 시점에 작성. hook 은 전역 부작용 컴포넌트라 pool 보다 self-contained + `dependencies` 우선.
- **릴리스 규율**: 설치 유저는 plugin.json `version` 문자열이 바뀔 때만 업데이트를 받음 → 릴리스마다 bump 필수. 버전 태그 = `{plugin-name}--v{version}` 컨벤션 (`claude plugin tag --push` 가 검증까지 해줌).
- **`temp-*/` = 실험용 dummy** (gitignored). 실험 끝나면 삭제.

### 디렉토리 레이아웃 (확정)

```
harness-interop/
├── .claude-plugin/marketplace.json   # 이 repo 를 marketplace 로 (CC 플러그인 entry 만)
├── plugins-claude/                   # Claude Code 용 플러그인 모음
│   └── memory-bridge-claude/         # CC→OC 플러그인 (self-contained)
│       ├── .claude-plugin/plugin.json
│       ├── hooks/hooks.json
│       └── scripts/memory-bridge.sh
├── plugins-opencode/                 # OpenCode 용 플러그인 모음
│   └── memory-bridge-opencode/       # OC→CC 플러그인 (배포용 사본 — .opencode/plugin/ 으로 복사해 설치)
│       └── plugin/memory-bridge-opencode.ts
├── resources/                        # 컴포넌트 수집 공간 — skills/·hooks/·scripts/ (marketplace 노출은 추후)
├── temp-*/                           # 실험용 dummy (gitignored)
├── README.md                         # 설치·사용 가이드
└── _reference/                       # 블로그에서 가져온 설계 노트 (내부용)
```

---

## 설계 레퍼런스 (`_reference/`)

블로그 repo 에서 복사해 온 설계 노트. (내부 source 인용 포함 — `.gitignore` 등록 완료, untrack 은 저자 실행 대기 ["현재 상태" 참고]. 내부 링크 `../index.mdx` 는 블로그 글을 가리키며 여기선 끊김 — 정상.)

| 파일 | 내용 |
|---|---|
| `hook-sync-research.md` | **설계 spec + 소스 앵커 + 레퍼런스 구현 3종** (`sync-memory.sh` / `sync-to-claude.ts` / opencode.json). §6 = clobber-safe 4파일, §7 = 레퍼런스 코드, §8 = grounded vs 저자검증 표 |
| `00-progress-and-plan.md` | 한 장짜리 지도 — 무엇을 왜 했고 뭘 검증할지. §3 = 검증 항목(G, T7-a~e), §5 = 열린 결정/리스크 |
| `verification.md` | 저자 실행 테스트(T1~T6) — OpenCode 의 memory 부재·"출처" 근거. T7 은 여기에 추가 예정 |
| `section3-detailed-prose-archive.md` | 블로그 §3 산문 아카이브 (빌드 후 글 재작성 때 쓸 자료) |
| `cc-plugin-schema.md` | **검증된 Claude Code 플러그인/marketplace/hook 스키마** (이 작업용으로 새로 정리) |

### 블로그 글 = 개념 framing (왜 만드나)

이 작업의 *왜* 는 블로그 글에 있어요. 읽으면 두 harness 의 개인 지침 차이와 ANCHOR 1(각자 두고 내용만 동기화)이 잡혀 이해가 빨라집니다:

```
/home/jetlee/workspace/taekyo-lee.github.io/src/content/blog/claude-code-vs-opencode/personal-instructions-two-harnesses/index.mdx
```

읽을 곳: **§1·§2·"한 눈에 비교"·"Take-home"** (개념 framing, 안정적).

> ⚠ **§3 ("한 걸음 더") 는 빌드 spec 으로 쓰지 말 것.** 아직 *옛 버전* — 단방향 + clobber 버그가 있는 재작성 전 상태예요 (의도된 보류, `00-progress-and-plan.md` §5 참고). **빌드는 §3 가 아니라 `_reference/` 의 설계 노트**(`hook-sync-research.md` §6~§7)를 따른다. 이 플러그인들을 만들고 저자가 forks 로 검증한 *뒤에* §3 를 양방향으로 재작성합니다.

(이 파일을 absolute path 로 한 번 Read 하는 건 가벼워요 — 블로그 repo 의 CLAUDE.md·메모리는 안 딸려옴. 단 cwd 를 블로그 repo 로 옮기진 말 것, 그게 무거워지는 원인.)

---

## 급소 — OC→CC 의 slug 동일성 (G)

OC plugin 이 `directory` 에서 계산한 slug 가 CC 의 `CLAUDE_PROJECT_DIR` 기반 memory 폴더와 *정확히 같아야* OC→CC 가 도착함. 한 글자(끝 슬래시·symlink·worktree)만 어긋나도 **에러 없이 조용히 sync 실패**. OC 의 `directory` 는 `realpathSync` 로 symlink 를 해석하므로 (`_reference/hook-sync-research.md` §8), 경로에 symlink 구간이 있으면 위험.

**Plan B (추천 검토)**: OC plugin 이 slug 를 *추측* 하지 말고, CC `SessionEnd` hook 이 자기 memory 폴더의 절대경로를 pointer 파일(예: `<project>/.opencode/.cc-memory-path`)에 한 줄 남기고, OC plugin 은 그 파일을 *읽어서* 목적지를 정한다. → G 급소 자체를 제거. Step 2 에서 결정.

---

## 현재 상태 / 다음 할 일

- [x] 설계·검증 노트 `_reference/` 로 복사
- [x] CC 플러그인/marketplace 스키마 확인 → `cc-plugin-schema.md`
- [x] **Step 1 — CC→OC 플러그인 scaffold**: `plugins-claude/memory-bridge-claude/` (폴더명 = 플러그인명 컨벤션; 옛 이름 `claude-code/`, 2026-06-10 rename + grouping) 에 `plugin.json` + `hooks/hooks.json` + `scripts/memory-bridge.sh`. SessionEnd hook → `from-claude.md` 생성·갱신·삭제 모두 검증 완료 (2026-06-09). 플러그인명 `memory-bridge-claude`.
- [x] **Step 2 — OC→CC 플러그인**: `plugins-opencode/memory-bridge-opencode/plugin/memory-bridge-opencode.ts` (배포용 사본, tracked; 유저 프로젝트의 `.opencode/plugin/` 에 복사되면 자동 발견 — 그 런타임 사본이 gitignored. export `MemoryBridgeOpenCode`). 3기능: (1) opencode.json+.gitignore 자가 설치, (2) personal.md 헤더로 메모리 행동 지침, (3) session.idle 마다 personal.md → `from-opencode.md` 복사 + MEMORY.md 요약 갱신. Plan B 채택 (`.cc-memory-path` 포인터, fallback-probe 보조). `from-opencode.md` 생성·claude-fork 자동 로드 검증 완료 (2026-06-10).
- [ ] **Step 3 — marketplace.json + README**: marketplace.json 완성 (2026-06-10, docs 그라운딩 — §6 에 현재형 기록), README 초안 존재. ⬜ 저자 검증 남음: `claude plugin validate ./plugins-claude/memory-bridge-claude` → 로컬 `/plugin marketplace add <repo 절대경로>` → **marketplace 경유 설치**로 SessionEnd 발화 확인 (기존 검증은 직접 설치 경로였음) → push 후 `Taekyo-Lee/harness-interop` 경유 + README 의 raw URL 재확인.
- [ ] **production-target 보정 재검증** (2026-06-10 코드 수정): 두 플러그인의 CC 데이터 디렉토리 추정을 production 우선으로 변경 — `CLAUDE_CONFIG_DIR` > `CLAUDE_HOME` > walk-up(sh만) > probe `~/.claude` → `~/.claude-fork`. OC 쪽 "아무것도 없으면 `~/.claude-fork` 에 생성" 버그 수정 (이제 `~/.claude`). ⬜ fork 재검증 — pointer(`.cc-memory-path`) 경로가 우선이라 동작 유지 예상, trace 의 `cc_home from pointer` 라인으로 확인. ⬜ production claude 로 e2e 1회 — `~/.claude/projects/<slug>/memory/from-opencode.md` 도착 + `from-claude.md` 생성 확인.
- [ ] (선택) **temp-plugin 의존성 실험**: marketplace.json 에 임시 entry `{ "name": "temp-plugin-claude", "source": "./temp-plugin-claude" }` 추가 → 설치 출력 끝의 의존성 자동 설치 목록 + `claude plugin disable memory-bridge-claude` 거부 관찰 → entry 제거 + `temp-plugin-claude/` 삭제. (fork 가 v2.1.143 미만이면 enable 연쇄 없음 주의.)
- [ ] **publish 전 내부 노트 untrack** — `.gitignore` 에 `CLAUDE.md`·`_reference/` 등록됨 (2026-06-10). 위치는 그대로 둠: **CLAUDE.md 는 루트에 있어야 세션이 auto-load** (git 추적 여부와 무관하게 파일시스템에서 읽음). 남은 것(저자): `git rm --cached CLAUDE.md && git rm --cached -r _reference` → commit. ⚠ 둘 다 이미 origin 에 push 된 이력이 있어 **과거 commit 에는 그대로 남음** — private→public 전환이라면 history 정리(orphan-branch squash 또는 `git filter-repo`) 또는 새 repo 로 시작 필요. 또한 untracked 파일은 다른 PC 의 clone 에 안 따라가니 (HOME/COMPANY PC) 개인 노트는 별도 동기화.
- [ ] (블로그) 동작 확인 후 블로그 §3 를 양방향 artifact 로 재작성 + 링크 채우기. ← 블로그 repo 에서.

---

## 저자 / 공개 정보 (README·manifest 용)

- 표시 이름: **Jet** (1인칭 서명) / 브랜드 **Guru Cat**. 본명은 표시 텍스트에 안 씀 (GitHub URL `Taekyo-Lee` 노출은 허용).
- GitHub: https://github.com/Taekyo-Lee · repo: `Taekyo-Lee/harness-interop`
- Email (공개용): gurucat72@gmail.com
- 회사/기업명 구체 언급 회피.
