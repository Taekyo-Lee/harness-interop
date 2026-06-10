# §3 작업 현황 & 검증 계획 (먼저 읽는 지도)

> 이 문서 = *지금까지 뭘 했고 / 왜 했고 / 뭘 검증할지* 의 지도. 한 장짜리 오리엔테이션.
> 상세 설계·소스 앵커 → `hook-sync-research.md`. 저자 실행 테스트(T1~T6 + 추가될 T7) → `verification.md`.
> 대상 글: `../index.mdx` 의 **§3. (Tip) hook 으로 project-scoped 개인 지침 자동 동기화**.
> 조사 대상: `~/workspace/opencode-fork` HEAD `27e74d32b` (2026-06-04, verification.md 와 동일 commit).

---

## 1. 목적 — 왜 이 작업을 하나

§3 의 위상이 바뀌었습니다.

- **전**: "Claude Code memory 를 OpenCode 로 보내는 *단방향* 편의 팁."
- **후**: **양쪽에 hook 을 하나씩 걸어 개인 지침을 *양방향* 동기화하는 artifact.** 단순 분석이 아니라 *저자가 실제로 만들어 유저에게 공개할 결과물*. 이 글의 **하이라이트**.

두 다리:
- **Claude Code → OpenCode**: `SessionEnd` hook (셸 스크립트).
- **OpenCode → Claude Code**: plugin (`event` → `session.idle`).

그래서 본문 문장보다 **레퍼런스 구현이 맞는지** 가 먼저예요. 사람들이 그대로 복붙해 돌릴 코드니까요.

---

## 2. 지금까지 한 작업

### 2a. 리서치 — opencode-fork 소스로 닫은 fact

OpenCode 의 확장 모델이 Claude Code 와 근본적으로 다르다는 걸 소스로 확인했습니다 (상세 file:line 은 `hook-sync-research.md` §2~§4, §9).

- 확장 = **JS/TS plugin** (`Hooks` 객체 export). 셸 명령 hook 이 아님. 패키지 `@opencode-ai/plugin`.
- **세션 *종료* 전용 hook 없음.** `dispose`(teardown 1회)가 가장 가깝고, 턴 종료 신호는 `session.status`(idle)·`session.idle`(deprecated) — Claude Code 의 `Stop` 대응.
- 이벤트 envelope = `{ type, properties }`. plugin 의 `event` hook 에서 `event.type === "session.idle"` 로 필터.
- plugin 자동 발견 위치 = **`.opencode/plugin(s)/*.{ts,js}`**. gitignore 여도 디스크에 있으면 로드.
- OC 쪽 "출처" = AGENTS.md 가이드 따라 모델이 `.opencode/personal.md` 에 적는 것 (verification.md T5/T6 과 연결).

### 2b. 설계 결정

- **clobber(상호 덮어쓰기) 문제 발견**: 단방향 §3 의 CC hook 은 `.opencode/personal.md` 를 통째로 덮어씀. OC→CC 다리가 생기면 그게 *OpenCode 자기 입력* 을 매 세션 지움.
- **해결 = clobber-safe 4파일 레이아웃** (상세 `hook-sync-research.md` §6): 각 harness 는 *자기 출처에만 쓰고 상대 출처는 읽기만*. 건너온 내용은 별도 파일(`from-claude.md` / `from-opencode.md`)로 받음. CC 출력 대상을 `.opencode/personal.md` → `.opencode/from-claude.md` 로 분리.
- **에코 차단**: CC hook 은 flatten 시 `from-opencode.md` 제외, OC plugin 은 `.opencode/personal.md` 만 내보냄. 안 하면 노트가 무한 왕복.
- **발화점 선택**: OC 는 `session.idle`(턴마다, 복사 가볍고 idempotent), CC 는 기존대로 `SessionEnd` 유지. 저자 추천 채택.

### 2c. 만들고 고친 것

| 파일 | 위치 | 상태 |
|---|---|---|
| `hook-sync-research.md` | 이 폴더 | **신규.** 설계 spec + 소스 앵커 + 레퍼런스 구현 3종(`sync-memory.sh`/`sync-to-claude.ts`/opencode.json) |
| `00-progress-and-plan.md` | 이 폴더 | **신규** (이 문서) |
| 개인 메모리 3개 | repo 밖 (`~/.claude/.../memory/`) | 설계 제약 보존: 양방향 artifact·clobber 주의·OC hook fact |
| `../index.mdx` §3 | 본문 | **미수정.** 아직 *단방향 + clobber 버그* 버전. 검증 후 통째로 재작성 예정 |

> 본문 §3 는 일부러 안 건드렸습니다. 검증으로 동작을 확인한 뒤 *한 번에, 맞게* 갈아끼우려고요. 하이라이트는 두 번 쓰지 않습니다.

---

## 3. 무엇을 검증할지 (저자가 직접 — 철칙)

흐름은 단방향: *저자 실행·관찰·보고 → Claude 가 doc·본문 반영*. Claude 가 sandbox 에서 `opencode`/`claude` 돌려 그 출력을 fact 로 본문에 넣지 않음.

| # | 검증할 것 | 왜 중요 | 어긋나면 |
|---|---|---|---|
| **G** | **slug 동일성 — OC plugin 의 `directory`→slug == CC `CLAUDE_PROJECT_DIR`→memory 폴더** | **급소.** 양방향에서 새로 생긴 가정. 한 글자(끝 슬래시·symlink·worktree)만 달라도 OC 는 엉뚱한 폴더에 쓰고 CC 는 딴 데서 읽음 | **에러 없이 sync 실패.** 레퍼런스 코드의 slug 도출을 고쳐야 함 (정규화 또는 경로 명시 전달) |
| T7-a | plugin 이 `.opencode/plugin/` 에서 자동 로드되나 | OC→CC 다리 존재 자체 | opencode.json `plugin` 으로 명시 등록 |
| T7-b | `session.idle` 이 매 턴 실제 발화하고 plugin 이 받나 | 다리 발화 | `session.status` + `status.type==="idle"` 로 fallback |
| T7-c | OC 가 `.opencode/from-claude.md` 를 자동 attach 하나 | CC→OC 도착 (instructions 2개째) | T3 패턴 그대로 — 경로/instructions 점검 |
| T7-d | CC 가 `from-opencode.md` 를 다음 세션에 자동 로드하나 | OC→CC 도착 | 8편 MEMORY.md 자동 로드 패턴 재확인 |
| T7-e | (대안 발화점 쓸 때만) `dispose` 가 종료 경로에서 발화하나 | SessionEnd 대칭 대안 | idle 기반 유지 |
| — | 하위폴더/worktree 에서 열어도 같은 slug 인지 | verification.md 와 동일 미해결 | 본문 경로 설명 보정 |

가장 먼저 닫을 건 **G(slug 동일성)** 입니다. 이게 무너지면 4파일 레이아웃의 OC→CC 절반이 통째로 다시 설계돼요.

---

## 4. 다음 단계 (추천 순서)

1. **(Claude, 소스)** OpenCode 가 plugin 에 주는 `directory` 가 *정규화된 절대경로* 인지 소스로 확인 → G 가정을 "근거 있음, 최종 눈확인만" 으로 좁힘. (소스 읽기라 철칙 위반 아님.)
2. **(저자, 실행)** `verification.md` 에 추가할 **T7** (위 §3 표) 을 돌려 G·T7-a~d 관찰 보고.
3. **(Claude, 본문)** 관측된 동작 위에 §3 를 *양방향 artifact* 로 재작성 (두 메커니즘 비대칭 + 4파일 레이아웃 + 코드 2종).
4. **(Claude, 본문)** "한 눈에 비교 (수정 필요)" · "Take-home (수정 필요)" 를 양방향 결론으로 갱신.

현재 멈춘 지점: 1번 시작 직전. 저자 "go" 대기.

---

## 5. 열린 결정 / 리스크

- **G 가 어긋날 경우의 plan B**: slug 를 양쪽에서 따로 계산하지 말고, CC hook 이 memory 폴더 경로를 OC 가 읽을 수 있는 곳에 한 줄 남기거나, OC plugin 이 `$CLAUDE_PROJECT_DIR` 대신 *알려진 절대경로* 를 쓰게. (검증 결과 보고 결정.)
- **`session.idle` deprecated 표시**: 아직 발화하지만 미래에 빠질 수 있음. 본문/코드에 `session.status` fallback 을 같이 적어 두는 게 안전.
- **cadence 비대칭**: CC=세션종료(SessionEnd), OC=턴마다(idle). 둘 다 옳지만 글에서 "왜 다른가" 를 한 줄 설명해야 독자가 안 헷갈림 (OC 엔 SessionEnd 대응이 없어서 — 이게 글의 좋은 재료).
- **본문 §3 현재 버그**: 지금 라이브 §3 는 clobber 버그가 있는 단방향. 재작성 전까지 이 상태. (의도된 보류.)
