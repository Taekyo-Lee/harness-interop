# OpenCode Plugin 시스템 — 리서치 노트

> 소스 그라운딩 기준: `~/workspace/opencode-fork` HEAD `27e74d32b` (2026-06-04).  
> 공식 docs: https://opencode.ai/docs/plugins/  
> 저자 검증 상태: § 표시된 항목은 grounded (소스 확인), ⚠ 표시는 docs-only (소스 미확인).

---

## 1. 개요

OpenCode 에는 Claude Code 의 "hook" 에 해당하는 **별도 개념이 없습니다.**  
모든 확장은 **plugin** 하나로 통합돼 있으며, plugin 함수가 반환하는 `Hooks` 객체 안의 콜백(`tool.execute.before`, `event`, `shell.env` 등)이 다른 도구에서 "hook" 이라 부르는 역할을 합니다.

Claude Code 와의 차이:
- **Claude Code** — hook(shell 스크립트)과 plugin(배포 단위)이 분리. hook 은 독립적으로 등록 가능.
- **OpenCode** — plugin 이 유일한 확장 단위. "hook 을 등록한다" = "plugin 에서 해당 콜백을 반환한다".

"marketplace" 라는 용어는 OpenCode 공식 문서에 없습니다 — 커뮤니티가 비공식으로 씁니다.  
설치·등록 방식은 두 가지: **파일 배치(file-based)** 와 **npm 패키지** 입니다.

---

## 2. 플러그인 타입

플러그인에는 두 가지 kind 가 있습니다 (소스: `packages/opencode/src/plugin/shared.ts`):

| kind | 역할 |
|---|---|
| `server` | 백엔드 서버 프로세스에서 실행 — event 구독, tool 정의, `Hooks` 콜백 반환 |
| `tui` | 터미널 UI 에서 실행 — 화면 렌더링·조작 전용 |

우리가 만든 `memory-bridge-opencode.ts` 는 **server kind** 플러그인입니다.

---

## 3. 로딩 메커니즘 (소스 grounded)

### 설치 방식 옵션 1 — 파일 자동 발견 (프로젝트 로컬 또는 전역)

**설치 방법:**

프로젝트 로컬 (이 프로젝트에서만):
```bash
mkdir -p .opencode/plugin
cp /path/to/my-plugin.ts .opencode/plugin/
# 끝. opencode 를 열면 자동으로 로드됨.
```

전역 (모든 프로젝트에서):
```bash
mkdir -p ~/.config/opencode/plugin
cp /path/to/my-plugin.ts ~/.config/opencode/plugin/
```

두 경우 모두 `opencode.json` 수정 불필요. OpenCode 시작 시 두 위치의 `plugin/*.{ts,js}` 를 자동으로 스캔합니다 (소스: `packages/opencode/src/config/plugin.ts:29`). 로컬·전역은 **같은 메커니즘이고 파일 위치만 다릅니다.**

참고:
- 폴더 이름은 `plugin`(단수)를 기본으로 쓰되, `plugins`(복수)도 동일하게 인식됨. (단, `opencode.json` 의 npm 선언 필드는 `plugin` 단수만 유효 — §3 옵션2.)
- 심링크도 인식됨 — 원본 하나를 여러 프로젝트에 심링크로 연결 가능 (복사 대신).
- 프로젝트 로컬로 설치한 파일은 보통 `.gitignore` 에 추가해서 개인용으로 씁니다.

### 설치 방식 옵션 2 — npm 패키지 (프로젝트 로컬 또는 전역)

**설치 방법:**

프로젝트 로컬 (`./opencode.json`):
```json
{
  "plugin": ["my-opencode-plugin"]
}
```

전역 (`~/.config/opencode/opencode.json`):
```json
{
  "plugin": ["my-opencode-plugin"]
}
```

options 를 함께 넘기려면 튜플:
```json
{
  "plugin": [["my-opencode-plugin", { "opt": true }]]
}
```

OpenCode 시작 시 선언된 패키지를 **사용자 홈 전역 캐시(`~/.cache/opencode/packages/<pkg>/`)에** 자동 설치합니다 (`@npmcli/arborist` 사용; 캐시 경로는 패키지 이름으로만 키가 잡혀 같은 패키지를 쓰는 여러 프로젝트가 공유). 소스: `packages/opencode/src/plugin/shared.ts:207–212`, `packages/core/src/npm.ts:77`.

받아오는 곳은 **기본적으로 공개 npm 레지스트리(`https://registry.npmjs.org`, 즉 npmjs.com)** 이고, 표준 `.npmrc` 를 따르므로 사내·스코프별 레지스트리로 바꿀 수 있습니다 (소스: `packages/core/src/npm-config.ts`).

> 이건 `plugin` 배열에 선언한 **npm 패키지에만** 해당합니다. 로컬 `.ts` 플러그인이 import 하는 `@opencode-ai/plugin` 은 별개로 `.opencode/node_modules/` 에 설치됩니다 — 설치 경로가 둘로 갈립니다 (상세: §7).

### 여러 방식이 혼재할 때의 로드 순서

낮은 우선순위 → 높은 우선순위 순으로 로드됩니다:

1. `~/.config/opencode/opencode.json` 의 `plugin` 배열 (전역 npm)
2. `./opencode.json` 의 `plugin` 배열 (프로젝트 npm)
3. `~/.config/opencode/plugin/*.{ts,js}` (전역 파일)
4. `.opencode/plugin/*.{ts,js}` (프로젝트 로컬 파일) ← 가장 높음

같은 npm 패키지가 여러 번 선언되면 중복 제거됩니다. 같은 이름의 파일 플러그인과 npm 플러그인은 별도 인스턴스로 로드됩니다.

---

## 4. 플러그인 구조 (소스 grounded)

소스: `packages/plugin/src/index.ts`

### 기본 시그니처

```typescript
import type { Plugin } from "@opencode-ai/plugin"

export const MyPlugin: Plugin = async ({ directory, client, project, worktree, $ }) => {
  // 초기화 코드 (매 세션 시작마다 실행)

  return {
    // 반환값 = Hooks 객체
    event: async ({ event }) => { /* 이벤트 핸들러 */ },
    tool: { /* 커스텀 tool 정의 */ },
    "tool.execute.before": async (input, output) => { /* ... */ },
    dispose: async () => { /* 정리 */ },
  }
}
```

### PluginInput 파라미터

```typescript
type PluginInput = {
  client: ReturnType<typeof createOpencodeClient>  // SDK 클라이언트
  project: Project                                  // 프로젝트 메타
  directory: string                                 // 프로젝트 루트 절대경로
  worktree: string                                  // 현재 worktree 경로
  $: BunShell                                       // Bun 쉘 API
}
```

`directory` 는 `realpathSync` 로 symlink 해석된 경로입니다 (slug 계산 시 주의).

### Hooks 반환 타입 (주요 항목)

```typescript
interface Hooks {
  dispose?: () => Promise<void>
  event?: (input: { event: Event }) => Promise<void>
  config?: (input: Config) => Promise<void>
  tool?: { [key: string]: ToolDefinition }
  auth?: AuthHook
  provider?: ProviderHook
  "chat.message"?: (...) => Promise<void>
  "chat.params"?: (...) => Promise<void>
  "tool.execute.before"?: (...) => Promise<void>
  "tool.execute.after"?: (...) => Promise<void>
  "shell.env"?: (...) => Promise<void>
  "permission.ask"?: (...) => Promise<void>
  "experimental.chat.messages.transform"?: (...) => Promise<void>
  "experimental.chat.system.transform"?: (...) => Promise<void>
  "experimental.session.compacting"?: (...) => Promise<void>
  "experimental.compaction.autocontinue"?: (...) => Promise<void>
  "tool.definition"?: (...) => Promise<void>
}
```

`tool.execute.before` / `tool.execute.after` 는 input/output 쌍 → Immer draft 로 output 변형 가능.

---

## 5. 이벤트 시스템

### 이벤트 구독 방법

`event` hook 으로 모든 이벤트 수신 → `event.type` 으로 분기:

```typescript
event: async ({ event }) => {
  if (event.type === "session.idle") {
    // 턴 완료 후 처리
  }
}
```

### 알려진 이벤트 타입 (docs 기준)

| 이벤트 | 설명 |
|---|---|
| `session.created` | 세션 시작 |
| `session.idle` | 턴 완료 (deprecated 표기 있으나 여전히 발화) |
| `session.compacted` | 세션 압축 완료 |
| `session.status` | 세션 상태 변화 — `status.type === "idle"` 로 idle 감지 가능 |
| `file.edited` | 파일 수정 |
| `file.watcher.updated` | 파일 시스템 변화 감지 |
| `command.executed` | 커맨드 실행 |
| `tool.execute.before` | tool 실행 전 |
| `tool.execute.after` | tool 실행 후 |
| permission 이벤트 | 권한 요청 |
| LSP 이벤트 | 언어 서버 관련 |
| message 이벤트 | 메시지 관련 |
| shell 이벤트 | 쉘 실행 관련 |
| TUI 이벤트 | UI 관련 |
| todo 이벤트 | todo 관련 |

**우리 플러그인에서의 사용:** `session.idle` 으로 턴 완료를 감지, fallback 으로 `session.status` + `props?.status?.type === "idle"`.

---

## 6. npm 플러그인 패키지 구조 (소스 grounded)

소스: `packages/opencode/src/plugin/shared.ts`

npm 패키지로 배포하는 경우 `package.json` 구조:

```json
{
  "name": "my-opencode-plugin",
  "version": "1.0.0",
  "exports": {
    "./server": "./dist/server.js",
    "./tui": "./dist/tui.js"
  },
  "engines": {
    "opencode": ">=0.3.0"
  }
}
```

- `exports["./server"]` — server kind 엔트리포인트.  
- `exports["./tui"]` — tui kind 엔트리포인트.  
- `engines.opencode` — semver range; 주 버전이 0이면 호환성 검사 건너뜀 (개발 버전 허용).  
- npm 플러그인은 파일 플러그인과 달리 **호환성 검사(semver)** 통과 필요.

파일 플러그인(`file://` 스펙 또는 경로 스펙)은 호환성 검사를 건너뜁니다 — 로컬 개발 코드로 간주.

---

## 7. 의존성 설치 — 두 경로 구분

설치 위치가 **두 가지로 갈립니다.** 헷갈리기 쉬운 급소.  
공통점: 런타임은 Bun 이지만 실제 설치는 `@npmcli/arborist`(Node npm)가 합니다 (소스: `packages/core/src/npm.ts`). docs 의 "bun install" 표현과 다름.

### 경로 A — npm 플러그인 패키지 (전역 캐시)

`opencode.json` 의 `plugin` 배열에 선언한 npm 패키지.  
→ **`~/.cache/opencode/packages/<pkg>/`** (사용자 홈 전역 캐시). 호출: `Npm.add()`.  
→ 프로젝트를 건드리지 않고 여러 프로젝트가 공유.

### 경로 B — `.opencode/` 설정 디렉토리의 의존성 (프로젝트 안)

OpenCode 는 시작 시 **모든 `.opencode` 디렉토리에 대해 자동으로** (소스: `packages/opencode/src/config/config.ts:624–658`):

1. `.opencode/package.json` 생성·갱신 → `@opencode-ai/plugin` 의존성 추가
2. `.opencode/.gitignore` 생성 (`ensureGitignore`)
3. 백그라운드(`forkDetach`)로 **`.opencode/node_modules/`** 에 설치. 호출: `Npm.install(dir)`.

→ 로컬 `.ts` 플러그인이 `import ... from "@opencode-ai/plugin"` 할 수 있게 하려는 것.  
→ **플러그인 파일이 없어도** 모든 `.opencode` 디렉토리에 실행됨.  
→ `zod`·`effect` 등은 `@opencode-ai/plugin` 의 전이 의존성.  
→ `node_modules` 가 이미 있고 `package.json`/lock 이 깨끗하면 재설치 건너뜀.

> **우리 테스트에서 `.opencode/node_modules/` 가 생긴 이유가 바로 경로 B 입니다.** 우리는 `plugin` 배열에 npm 패키지를 선언한 적이 없어서 경로 A 의 전역 캐시(`~/.cache/opencode/packages/`)는 비어 있습니다.

---

## 8. 플러그인 메타 추적

소스: `packages/opencode/src/plugin/meta.ts`

`~/.local/share/opencode/state/plugin-meta.json` (또는 `OPENCODE_PLUGIN_META_FILE` env)에 로드된 플러그인 이력 기록:

```json
{
  "<plugin-id>": {
    "source": "file",
    "spec": "file:///path/to/plugin.ts",
    "target": "file:///path/to/plugin.ts",
    "first_time": 1234567890,
    "last_time": 1234567890,
    "load_count": 42,
    "fingerprint": "file:///path/to/plugin.ts|<mtime>"
  }
}
```

파일 플러그인은 mtime 으로 fingerprint → 변경 시 "updated" state.

---

## 9. 커스텀 tool 등록

플러그인에서 `tool` 키로 커스텀 도구 등록 가능 (Zod 스키마 사용 — `@opencode-ai/plugin`의 `tool()` 헬퍼):

```typescript
import { tool } from "@opencode-ai/plugin"
import { z } from "zod"

return {
  tool: {
    my_tool: tool({
      description: "Does X",
      parameters: z.object({ input: z.string() }),
      execute: async ({ input }) => ({ output: "result" }),
    })
  }
}
```

같은 이름의 tool 이 있으면 플러그인 tool 이 built-in 보다 우선합니다 (docs).

---

## 10. 배포 옵션 비교

| 방식 | 설치 | 적합한 용도 |
|---|---|---|
| **파일 — 프로젝트 로컬** | `.opencode/plugin/*.ts` 에 복사 | 개인용, 팀 내부, gitignored |
| **파일 — 전역** | `~/.config/opencode/plugin/*.ts` 에 복사 | 한 사용자의 모든 프로젝트 공통 |
| **npm 패키지** | `opencode.json` 의 `plugin` 배열에 패키지명 | 공개 배포, 버전 관리 |

위 두 "파일" 방식은 **§3 옵션 1과 같은 메커니즘** (Glob 자동 발견)이고 위치만 다릅니다.

우리 OC→CC 플러그인은 **파일 — 프로젝트 로컬 방식** 을 선택했습니다 (개인 메모리 = gitignored 파일이라 npm 배포 부적합).

---

## 11. Claude Code 와의 비교

| 항목 | Claude Code | OpenCode |
|---|---|---|
| hook / plugin 분리 | 별도 개념 — hook(shell 스크립트)은 plugin 없이도 독립 등록 가능; plugin 은 hook + 스크립트를 묶는 배포 단위 | 없음 — plugin 이 유일한 확장 단위; "hook 등록" = plugin 함수가 해당 콜백을 반환하는 것 |
| "marketplace" | 공식 지원 (`/plugin marketplace add <owner>/<repo>`) | 비공식 용어, 지원 없음 |
| 설치·발견 | marketplace 등록 후 `/plugin install`; hook 은 plugin 내 `hooks.json` 에 명시 | `plugin/*.{ts,js}` 파일 복사 = 자동 발견·설치 (또는 npm 패키지 선언) |
| 의존성 | 스크립트가 자체 조달 | `opencode.json` 에 패키지 선언 시 자동 설치 (arborist) |
| 발화점 | `SessionStart/End`, `Pre/PostToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `PreCompact`, `Notification` | `session.idle`, `tool.execute.before/after`, `chat.*`, `file.*`, `shell.env`, … |
| 이벤트 수 | 9종 hook event | 15+ 이벤트 타입 |
| 출력 캡처 | stdout JSON 반환 | Hooks 객체 직접 반환 |
| stderr | `>&2` = 무시 | `console.error()` = 터미널 red 출력 (오류 아님) |

---

## 12. 커뮤니티 플러그인 예시 (kdnuggets 기준, 저자 미검증)

1. **Oh My Openagent** — 배경 agent, LSP/AST 도구, MCP 통합, Claude Code 호환.
2. **Opencode Antigravity Auth** — OAuth로 Gemini 3.1 Pro, Claude Opus 4.6 Thinking 접근.
3. **Opencode Supermemory** — 세션·프로젝트 간 영속 메모리.
4. **Opencode Pty** — 의사 터미널(Pseudoterminal) 지원 (장기 실행 프로세스).
5. **Opencode Websearch Cited** — 인용 포함 웹 검색 (Google/OpenAI/OpenRouter 백엔드).
6. **Opencode Wakatime** — AI 코딩 활동·시간 추적.
7. **Opencode Agent Skills** — 프로젝트 폴더에서 재사용 가능 agent skill 로드.

> ⚠ 위 플러그인들은 저자 검증 없음 — 실제 설치 전 해당 repo 에서 직접 확인 필요.

---

## 13. 우리 플러그인 (`memory-bridge-opencode.ts`) 과의 연결

| 이 문서 § | 연결 포인트 |
|---|---|
| §3 옵션 1 | `.opencode/plugin/memory-bridge-opencode.ts` 복사 = 자동 발견·로드 |
| §4 | `Plugin` 타입 사용, `directory` 파라미터로 프로젝트 루트 수신 |
| §5 | `session.idle` 이벤트 구독으로 턴마다 sync |
| §10 | 파일 복사 방식 선택 (개인·gitignored 용도) |
| §11 | `console.error()` = stderr = 빨간 텍스트 (오류 아님) |

`directory` 는 `realpathSync` 해석 경로 → Plan B `.cc-memory-path` 포인터 파일로 slug 불일치 위험 우회 (상세: `hook-sync-research.md` §6, §8).
