# multi-harness-plugins — 작업 맥락

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
- **이 repo 가 marketplace 역할** — 루트에 `.claude-plugin/marketplace.json` 을 두면 `/plugin marketplace add Taekyo-Lee/multi-harness-plugins` 로 설치 가능.
- 검증된 CC 플러그인 / marketplace 스키마 → **`_reference/cc-plugin-schema.md`** (docs 로 확인 완료, 재조사 불필요).
- **빌드 순서: CC→OC 먼저, OC→CC 나중.** CC→OC 는 자기 프로젝트 안에만 쓰니 slug 매칭(G) 급소 의존이 없어 가장 안전. OC→CC 가 slug 동일성(G)을 탐.

### 제안 디렉토리 레이아웃 (확정 아님 — Step 1 에서 확정)

```
multi-harness-plugins/
├── .claude-plugin/marketplace.json   # 이 repo 를 marketplace 로
├── claude-code/                      # CC→OC 플러그인
│   ├── .claude-plugin/plugin.json
│   ├── hooks/hooks.json
│   └── scripts/memory-bridge.sh
├── opencode/                         # OC→CC 플러그인 (배포 방식 Step 2 에서 결정)
│   └── ...
├── README.md                         # 설치·사용 가이드
└── _reference/                       # 블로그에서 가져온 설계 노트 (내부용)
```

---

## 설계 레퍼런스 (`_reference/`)

블로그 repo 에서 복사해 온 설계 노트. (내부 source 인용 포함 — public repo 면 `_reference/` 는 `.gitignore` 권장. 내부 링크 `../index.mdx` 는 블로그 글을 가리키며 여기선 끊김 — 정상.)

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
- [x] **Step 1 — CC→OC 플러그인 scaffold**: `claude-code/` 에 `plugin.json` + `hooks/hooks.json` + `scripts/memory-bridge.sh`. SessionEnd hook → `from-claude.md` 생성·갱신·삭제 모두 검증 완료 (2026-06-09). 플러그인명 `memory-bridge-claude`.
- [x] **Step 2 — OC→CC 플러그인**: `opencode/plugin/memory-bridge-opencode.ts` (자동 발견, gitignored; export `MemoryBridgeOpenCode`). 3기능: (1) opencode.json+.gitignore 자가 설치, (2) personal.md 헤더로 메모리 행동 지침, (3) session.idle 마다 personal.md → `from-opencode.md` 복사 + MEMORY.md 요약 갱신. Plan B 채택 (`.cc-memory-path` 포인터, fallback-probe 보조). `from-opencode.md` 생성·claude-fork 자동 로드 검증 완료 (2026-06-10).
- [ ] **Step 3 — marketplace.json + README** (설치·사용 가이드).
- [ ] (블로그) 동작 확인 후 블로그 §3 를 양방향 artifact 로 재작성 + 링크 채우기. ← 블로그 repo 에서.

---

## 저자 / 공개 정보 (README·manifest 용)

- 표시 이름: **Jet** (1인칭 서명) / 브랜드 **Guru Cat**. 본명은 표시 텍스트에 안 씀 (GitHub URL `Taekyo-Lee` 노출은 허용).
- GitHub: https://github.com/Taekyo-Lee · repo: `Taekyo-Lee/multi-harness-plugins`
- Email (공개용): gurucat72@gmail.com
- 회사/기업명 구체 언급 회피.
