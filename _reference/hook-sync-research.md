# §3 리서치 & 설계 — hook 으로 개인 지침 *양방향* 자동 동기화

> 대상 글: 이 폴더의 `../index.mdx` 의 **§3. (Tip) hook 으로 project-scoped 개인 지침 자동 동기화**
> 성격: §3 를 *단방향 팁 → 양방향 artifact* 로 재구성하기 위한 그라운딩 + 설계 노트. 저자가 실제로 만들어 공개할 결과물의 spec.
> 조사 대상: `~/workspace/opencode-fork` (HEAD `27e74d32b`, 2026-06-04). `verification.md` 와 동일 commit.
> 사실/동작 구분 원칙: *코드로 닫은 fact* 는 file:line 으로 앵커, *동작* 은 저자가 trace/실행으로 확인 (루트 CLAUDE.md 철칙). 이 문서의 file:line 인용은 *연구 노트 한정* — 블로그 본문엔 옮기지 않음 (메모 `blog_no_source_code_citations`).

---

## 0. 목표 / 한 줄 요약

- ANCHOR 1 의 결론은 *각자 두고 내용만 옮긴다* (파일은 안 합치고 내용만 베낌). §3 는 그 베끼기를 **양쪽에 hook 을 하나씩 걸어 자동화**.
- **Claude Code 쪽**: `SessionEnd` hook (셸 스크립트) → CC memory 를 OpenCode 가 읽는 파일로 flatten.
- **OpenCode 쪽**: plugin (`event`→`session.idle`) → OpenCode 개인 노트를 CC memory 폴더로 복사.
- 핵심 함정 = **상호 덮어쓰기(clobber)**. 두 hook 이 같은 파일을 쓰면 서로의 결과를 지움. 해결 = *각 harness 는 자기 출처에만 쓰고 상대 출처는 읽기만* + *되돌림(echo) 차단*.

---

## 1. 한눈에 — 두 harness 의 확장 모델 (grounded)

| | Claude Code | OpenCode |
|---|---|---|
| hook 형태 | settings(.local).json 의 **셸 명령** | `Hooks` 객체를 export 하는 **JS/TS plugin 모듈** |
| 세션 *종료* 발화점 | `SessionEnd` (전용, 세션당 1회) | **전용 없음.** `dispose` hook 이 가장 가까움 (plugin teardown 1회) |
| 턴 *종료* 발화점 | `Stop` (턴마다) | `event` hook + `session.status`(`status.type==="idle"`) 또는 `session.idle`(deprecated) — 턴마다 |
| 로딩 위치 | `.claude/settings.local.json` (git-untracked) | `.opencode/plugin/*.{ts,js}` 자동 발견, 또는 opencode.json `plugin` |
| 스크립트 언어 | bash (아무 명령) | TypeScript/JavaScript (`PluginInput.$` 로 BunShell 제공) |
| 개인(비공유) scope | settings.local.json 이 이미 untracked | plugin 파일을 .gitignore (디스크에 있으면 gitignore 여도 로드됨) |

**핵심 비대칭 2가지**:
1. OpenCode 엔 `SessionEnd` 의 *이름 붙은 짝이 없음*. persistent server 라 CLI 식 "세션 종료" 가 약함. 안정적 발화점은 *턴이 끝나 idle 로 바뀔 때* = Claude Code 의 `Stop` 대응 (SessionEnd 아님). `dispose` 가 종료-1회에 가장 가깝지만 hard kill 시 finalizer 미실행 가능 → 신뢰성은 저자 검증.
2. OpenCode hook 은 *코드(plugin)* 라 셸 한 줄이 아니라 `event({event})` 안에서 `event.type` 을 걸러 fs 작업.

---

## 2. OpenCode 확장 모델 = JS/TS plugin

- 공개 plugin API: `packages/plugin/src/index.ts`. 패키지명 **`@opencode-ai/plugin`** (`packages/plugin/package.json:3`).
- `Plugin = (input: PluginInput, options?) => Promise<Hooks>` (`index.ts:74`). `PluginInput` 필드: `client, project, directory, worktree, serverUrl, $` (BunShell) (`index.ts:56-66`). **`directory` = 프로젝트 디렉토리** (slug 계산에 사용). 이 값은 `ctx.directory` (`plugin/index.ts:143,152`) → `AppFileSystem.resolve()` = **`realpathSync(path.resolve())`, symlink 해석** (`instance-store.ts:106`, `util/filesystem.ts:134-141`). 일반 프로젝트는 `worktree === directory` (`project.ts:239`). → G(§6·§8) 의 근거: symlink 없는 경로면 CC slug 와 일치.
- `interface Hooks` (`index.ts:222-334`) 의 lifecycle 관련 멤버:
  - `dispose?: () => Promise<void>` (`:223`) — plugin scope 닫힐 때 (teardown).
  - `event?: (input: { event: Event }) => Promise<void>` (`:224`) — **버스 전 이벤트 수신**. `event.type` 으로 필터.
  - 그 외 `chat.message`(:234), `chat.params`(:247), `tool.execute.before/after`(:266/:274), `permission.ask`(:261), `experimental.*` 등.
- 실제 발화: `packages/opencode/src/plugin/index.ts:273-282` — `bus.subscribeAll()` 스트림을 돌며 모든 hook 의 `hook["event"]?.({ event: input })` 호출 (`:277`). `dispose` 는 `Effect.addFinalizer` 로 scope 종료 시 호출 (`:258-270`).
- plugin 모양 예시 (`packages/plugin/src/example.ts`):
  ```ts
  export const ExamplePlugin: Plugin = async (_ctx) => {
    return { tool: { mytool: tool({ /* ... */ }) } }
  }
  ```

---

## 3. 세션 생명주기 이벤트 (발화점)

`packages/opencode/src/session/status.ts`:
- `Event.Status` = **`"session.status"`**, payload `{ sessionID, status }` (`:34-41`). `status` = `{ type: "idle" | "retry" | "busy" }` (`Info`, `:8-32`).
- `Event.Idle` = **`"session.idle"`**, payload `{ sessionID }` — **`// deprecated` 표시** (`:42-48`). 단 아직 publish 됨.
- `set()` 에서 status 가 idle 로 바뀌면 `bus.publish(Event.Status, ...)` 항상 + `bus.publish(Event.Idle, { sessionID })` (`:77-86`).
- idle 진입 시점: 모델이 한 차례 응답을 마칠 때. `packages/opencode/src/session/processor.ts:777` (`status.set(ctx.sessionID, { type: "idle" })`).

세션 CRUD 이벤트 (`packages/opencode/src/session/session.ts`): `session.created`(:346) / `session.updated`(:352) / `session.deleted`(:359). 모두 *세션 객체 CRUD* 지 TUI/프로세스 종료가 아님. → "세션 종료" 발화점으로 부적합.

**이벤트 envelope = `{ type, properties }`** (`packages/opencode/src/bus/bus-event.ts:6,13,28,38`). 소비자들이 `event.type` / `event.properties.X` 로 읽음:
- `cli/cmd/run/stream.transport.ts:124-133` — `if (event.type === "message.updated") return event.properties.sessionID` 등.
- `acp/event.ts:112-113` — `event.properties.part`, `event.properties.sessionID`.
- `cli/cmd/tui/feature-plugins/system/notifications.ts:7` — `Extract<Event, { type: "session.error" }>["properties"]["error"]`.
→ plugin 의 `event` hook 에서 `event.type === "session.idle"` + `event.properties.sessionID` 로 읽으면 됨.

**§3 발화점 선택**: `session.idle` 사용 (payload 단순, 아직 발화). deprecated 표시이므로, 안 되면 `session.status` 의 `event.properties.status.type === "idle"` 로 교체 — *검증 가이드에 이 fallback 명시*. cadence 는 턴마다 = `Stop` 대응. 복사는 가볍고 idempotent (같은 파일 같은 내용으로 덮음) 이라 자주 돌아도 무방.

---

## 4. plugin 로딩 — 어디 두면 자동 로드되나

- 자동 발견: `packages/opencode/src/config/plugin.ts:26-38` — `Glob.scan("{plugin,plugins}/*.{ts,js}", { cwd: dir, absolute: true, dot: true, symlink: true })`.
- 그 `dir` = **`.opencode`**. 호출부 `packages/opencode/src/config/config.ts:664-667` 주석: *"Auto-discovered plugins under `.opencode/plugin(s)`"*. → **`.opencode/plugin/*.{ts,js}` (또는 `.opencode/plugins/`)** 에 두면 자동 로드.
- 명시 등록도 가능: opencode.json `plugin: ["./.opencode/plugin/foo.ts"]`. file 스펙 = 로컬 dev 코드로 취급, npm 호환성 게이트 skip (`packages/opencode/src/plugin/loader.ts:124`). 경로는 *선언한 config 파일 기준* 으로 resolve (`config/plugin.ts:50-59`).
- **개인 scope**: plugin 파일을 .gitignore. `Glob.scan` 은 디스크를 보므로 gitignore 여도 로드됨 (= CC 의 settings.local.json 이 untracked 여도 동작하는 것과 평행). 팀원 clone 엔 파일이 없어 자동 발견 0 → 조용히 skip (T4 의 instructions 누설 없음과 같은 결).
- `.opencode/plugin/sync-to-claude.ts` 로 두면 `.opencode/personal.md`·`.opencode/from-claude.md` 와 한곳에 모여 관리 깔끔.

---

## 5. OpenCode 쪽 "출처" — verification.md 와 연결

`verification.md` §1 + T5/T6 에서 코드로 닫힌 사실:
- OpenCode 엔 **1급 memory 서브시스템 없음** (전용 도구·관리 store·자동 로드 전무).
- "memory 에 저장해줘" → 모델이 *일반 Edit 도구* 로 instruction 파일을 고침. default 프롬프트(glm-5)는 AGENTS.md 직접 수정(T5), beast(gpt-4 계열)는 `.github/instructions/memory.instruction.md` 에 쓰지만 **자동 로드 안 됨** → 다음 세션에 안 돌아옴(T6, "back 없는 write-only").

→ OC 쪽 *출처* = **AGENTS.md 에 적은 가이드를 따라 모델이 `.opencode/personal.md` 에 append 하는 것**. 그 목적지가 opencode.json `instructions` 에 등록된 파일(`.opencode/personal.md`)이라야 다음 세션에 다시 읽힘 (beast 의 `.github/...` 가 안 돌아오는 이유와 같은 차이). 이 *출처 파일* 을 OC plugin 이 CC memory 로 복사 = OC→CC 다리.

---

## 6. 설계 — clobber-safe 4파일 레이아웃

**원칙**: 파일마다 *쓰는 쪽을 정확히 하나* 로 고정. 건너오는 내용은 *원래 내 노트와 다른 파일* 로 받음.

| 파일 | 위치 | 쓰는 쪽 (유일) | 읽는 쪽 |
|---|---|---|---|
| `memory/*.md` (단 `from-opencode.md` 제외) | repo 바깥 `~/.claude/projects/<slug>/memory/` | Claude Code (자율+수동) | Claude Code (자동 로드) |
| `.opencode/personal.md` | repo 안 (gitignored) | OpenCode 모델 (AGENTS.md 가이드 따라 "기억해줘") | OpenCode (opencode.json `instructions`) |
| `.opencode/from-claude.md` | repo 안 (gitignored) | **Claude Code `SessionEnd` hook** | OpenCode (opencode.json `instructions`) |
| `~/.claude/projects/<slug>/memory/from-opencode.md` | repo 바깥 | **OpenCode plugin** | Claude Code (자동 로드) |

- opencode.json `instructions: [".opencode/personal.md", ".opencode/from-claude.md"]` → OpenCode 가 *자기 노트 + CC 노트* 둘 다 읽음.
- Claude Code 는 memory 폴더를 통째로 자동 로드하므로 `from-opencode.md` 가 *OC 노트* 를 자연히 들여옴.
- **에코(되돌림) 차단** (이게 load-bearing):
  - CC hook 은 flatten 할 때 `from-opencode.md` 제외 (OC 에서 받은 걸 다시 OC 로 안 보냄).
  - OC plugin 은 `.opencode/personal.md`(자기 것)만 보내고 `.opencode/from-claude.md` 는 안 건드림.
  - 안 그러면 노트가 두 harness 를 무한 왕복.
- 두 파일 모두 writer 가 하나뿐이라 덮어쓰기 충돌 없음. 양방향 다 자동.

원래 단방향 §3 의 버그: CC hook 이 `.opencode/personal.md` 를 직접 덮어써 OpenCode 자기 노트를 매 세션 지움. → 출력 대상을 `.opencode/from-claude.md` 로 분리해 해결.

---

## 7. 레퍼런스 구현 (저자가 만들 결과물)

### 7a. Claude Code → OpenCode: `SessionEnd` hook

`.claude/settings.local.json` (git-untracked 개인 레이어):
```json
{
  "hooks": {
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/sync-memory.sh\"" } ] }
    ]
  }
}
```

`.claude/sync-memory.sh`:
```bash
#!/usr/bin/env bash
# Claude Code 의 이 프로젝트 memory 를 OpenCode 가 읽는 파일로 flatten 한다.
# OpenCode 에서 건너온 노트(from-opencode.md)는 되돌려보내지 않는다 (에코 차단).
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
slug="$(printf '%s' "$proj" | tr -c '[:alnum:]' '-')"
mem="$HOME/.claude/projects/$slug/memory"
out="$proj/.opencode/from-claude.md"

[ -d "$mem" ] || exit 0
mkdir -p "$(dirname "$out")"
{
  echo "<!-- Claude Code SessionEnd hook 이 자동 생성. 직접 수정하지 마세요. -->"
  echo
  for f in "$mem"/*.md; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "from-opencode.md" ] && continue   # OpenCode 에서 온 노트는 제외
    cat "$f"; echo
  done
} > "$out"
```

### 7b. OpenCode → Claude Code: plugin (`session.idle`)

`.opencode/plugin/sync-to-claude.ts` (자동 발견됨):
```ts
import type { Plugin } from "@opencode-ai/plugin"
import { homedir } from "node:os"
import { join, dirname } from "node:path"
import { mkdir, copyFile, access } from "node:fs/promises"

// OpenCode 개인 노트(.opencode/personal.md)를 Claude Code 가 읽는 memory 폴더로 흘려보낸다.
// 세션이 잦아들 때(session.idle)마다 최신본으로 덮어쓴다.
export const SyncToClaude: Plugin = async ({ directory }) => {
  return {
    event: async ({ event }) => {
      if (event.type !== "session.idle") return                // deprecated 면 "session.status" + status.type==="idle"
      const slug = directory.replace(/[^A-Za-z0-9]/g, "-")     // CC 의 tr -c '[:alnum:]' '-' 와 동일 규칙
      const src = join(directory, ".opencode", "personal.md")
      const out = join(homedir(), ".claude", "projects", slug, "memory", "from-opencode.md")
      try { await access(src) } catch { return }               // 아직 개인 노트가 없으면 종료
      await mkdir(dirname(out), { recursive: true })
      await copyFile(src, out)
    },
  }
}
```

### 7c. opencode.json + .gitignore

```json
{
  "instructions": [".opencode/personal.md", ".opencode/from-claude.md"]
}
```
```
# .gitignore
.opencode/personal.md
.opencode/from-claude.md
.opencode/plugin/sync-to-claude.ts
```

---

## 8. grounded vs 저자 검증 필요 (철칙)

| 항목 | 종류 | 상태 |
|---|---|---|
| OC 확장 = JS/TS plugin (셸 hook 아님) | fact | ✅ 소스 (`plugin/src/index.ts:74,222`) |
| OC 에 named SessionEnd 없음; `event` hook + `dispose` | fact | ✅ 소스 (`plugin/index.ts:258-282`) |
| 턴 종료 신호 = `session.status`(idle) / `session.idle`(deprecated) | fact | ✅ 소스 (`session/status.ts:34-48,77-86`) |
| 이벤트 envelope = `{ type, properties }` | fact | ✅ 소스 (`bus/bus-event.ts`, 소비자 다수) |
| plugin 자동 발견 = `.opencode/plugin(s)/*.{ts,js}` | fact | ✅ 소스 (`config/plugin.ts:29` + `config.ts:664`) |
| 패키지명 `@opencode-ai/plugin` | fact | ✅ `packages/plugin/package.json:3` |
| CC slug = 절대경로의 비영숫자→`-` | fact | ✅ verification.md + 실측 (repo 루트 기준) |
| **OC 의 `directory` == CC 의 `CLAUDE_PROJECT_DIR`** (같은 slug → 같은 memory 폴더) | behavior (일부 grounded) | ⚠ **핵심 가정(G).** OC `directory` = `realpathSync(path.resolve())` 로 **symlink 해석** (`util/filesystem.ts:134-141`, `instance-store.ts:106`). 경로에 symlink 구간이 있고 CC 가 안 풀면 어긋나 *조용히 sync 실패*. 저자가 T7 의 G 로 양쪽 slug 비교 |
| `session.idle` 이 매 턴 실제 발화하고 plugin 이 받는지 | behavior | ⬜ 저자 검증 (trace/로그). deprecated 면 `session.status` fallback |
| OC 가 `.opencode/from-claude.md` 를 자동 attach 하는지 | behavior | ⬜ 저자 검증 (T3 패턴 그대로 — instructions 에 두 번째 파일 추가) |
| CC 가 `from-opencode.md` 를 자동 로드하는지 | behavior | ⬜ 저자 검증 (8편 MEMORY.md 자동 로드 패턴) |
| `dispose` 가 종료 경로(정상/Ctrl-C/kill)에서 발화하는지 | behavior | ⬜ (대안 fire-point 쓸 경우만) 저자 검증 |
| 하위폴더/worktree 에서 열어도 같은 slug 인지 | behavior | ⬜ verification.md 와 동일 미해결 — 저자 확인 |

---

## 9. source 앵커 모음 (opencode-fork @ 27e74d32b)

- `packages/plugin/src/index.ts` — `Plugin`(:74), `interface Hooks`(:222), `dispose`(:223), `event`(:224), `PluginInput`(:56-66)
- `packages/plugin/src/example.ts` — plugin 모양 예시
- `packages/plugin/package.json:3` — `@opencode-ai/plugin`
- `packages/opencode/src/plugin/index.ts:258-282` — `dispose` finalizer + `event` 디스패치(`subscribeAll`)
- `packages/opencode/src/plugin/loader.ts:124` — file 스펙 = 로컬 dev, npm 게이트 skip
- `packages/opencode/src/session/status.ts:34-48,77-86` — `session.status` / `session.idle`(deprecated) 정의·발화
- `packages/opencode/src/session/processor.ts:777` — idle 진입 (턴 종료)
- `packages/opencode/src/session/session.ts:346,352,359` — session.created/updated/deleted
- `packages/opencode/src/bus/bus-event.ts:6,13,28,38` — 이벤트 `{type, properties}` envelope
- `packages/opencode/src/cli/cmd/run/stream.transport.ts:124-133`, `acp/event.ts:112-113`, `cli/cmd/tui/feature-plugins/system/notifications.ts:7` — `event.type`/`event.properties` 소비 예
- `packages/opencode/src/config/plugin.ts:26-38,50-59` — 자동 발견 glob + file 스펙 resolve
- `packages/opencode/src/config/config.ts:664-667` — 호출부 + `.opencode/plugin(s)` 주석
- `packages/opencode/src/plugin/index.ts:143,148-152` — `PluginInput.directory = ctx.directory`
- `packages/opencode/src/project/instance-store.ts:106,124` — `directory = AppFileSystem.resolve(input.directory)`
- `packages/opencode/src/util/filesystem.ts:134-141` — `resolve()` = `realpathSync(path.resolve())`, **symlink 해석** (G 의 근거)
- `packages/opencode/src/project/project.ts:239` — 일반 프로젝트는 `worktree === directory`
- OC memory 부재 / beast `# Memory` / write-only: `verification.md` §1, T5(R9), T6(R10)
