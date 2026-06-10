# Claude Code 플러그인 / marketplace / hook 스키마 (검증됨)

> 출처: Claude Code 공식 docs (아래 링크). 이 작업(CC→OC `SessionEnd` 동기화 플러그인)용으로 정리.
> 상태 표기: ✅ docs 로 확인된 fact / ⬜ 저자가 fork 로 눈확인 필요.
> docs:
> - 플러그인 reference: https://code.claude.com/docs/en/plugins-reference.md
> - marketplace: https://code.claude.com/docs/en/plugin-marketplaces.md
> - hooks: https://code.claude.com/docs/en/hooks.md

---

## 1. 플러그인 디렉토리 레이아웃 ✅

번들 hook + 셸 스크립트를 담는 최소 구조:

```
<plugin-dir>/
├── .claude-plugin/
│   └── plugin.json        # manifest
├── hooks/
│   └── hooks.json         # hook 선언 (또는 plugin.json 안에 인라인)
└── scripts/
    └── sync-memory.sh     # 번들 스크립트 (chmod +x)
```

이 repo 는 marketplace 이자 플러그인 호스트라, CC 플러그인은 하위 폴더(예: `claude-code/`)에 두고 marketplace.json 의 `source` 가 그 경로를 가리키게 한다.

---

## 2. plugin.json ✅

- **필수**: `name` (kebab-case).
- **권장**: `version`(semver, 생략 시 git SHA), `description`, `author`, `repository`.
- hook 을 별도 파일로 둘 거면 굳이 `hooks` 키 불필요 — `hooks/hooks.json` 이 자동 인식됨. (인라인하려면 `plugin.json` 에 `hooks` 객체를 직접 넣어도 됨.)

우리 용도 예시:
```json
{
  "name": "claude-to-opencode-sync",
  "version": "0.1.0",
  "description": "Flatten Claude Code project memory into OpenCode's instruction file on session end.",
  "author": { "name": "Jet", "email": "gurucat72@gmail.com" },
  "repository": "https://github.com/Taekyo-Lee/multi-harness-plugins",
  "license": "MIT"
}
```

---

## 3. hooks/hooks.json — SessionEnd ✅

literal shape (우리 용도):
```json
{
  "description": "Sync Claude Code memory to OpenCode on session end",
  "hooks": {
    "SessionEnd": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/sync-memory.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

- `matcher` = `end_reason` 에 대한 pipe-delimited 매칭. `"*"` = 모든 종료 사유. 우리는 세션이 어떻게 끝나든 flatten 하고 싶으니 `"*"`.
- `timeout` 선택 (기본 600초). flatten 은 가벼우니 30 으로 충분.
- **SessionEnd 는 비차단(async)** — exit code/stdout 으로 종료를 막거나 결정 제어 못 함. 우리는 막을 필요 없으니 무관. 스크립트는 `exit 0` 로 끝내면 됨.

---

## 4. 경로·환경변수 ✅ (단 plugin 컨텍스트는 ⬜ 눈확인)

- **`${CLAUDE_PLUGIN_ROOT}`** ✅ — 플러그인 설치 루트의 절대경로. 번들 스크립트 호출은 반드시 이걸로. 셸 form 이면 따옴표: `"${CLAUDE_PLUGIN_ROOT}/scripts/sync-memory.sh"`.
- **`$CLAUDE_PROJECT_DIR`** — SessionEnd hook 에서 사용 가능(=유저의 프로젝트 디렉토리). 이게 핵심: 스크립트가 `<project>/.opencode/` 와 memory slug 를 여기서 도출.
  - ⬜ **저자 눈확인**: *플러그인으로 배송된* SessionEnd hook 에서도 `CLAUDE_PROJECT_DIR` 이 (플러그인 루트가 아니라) **유저 프로젝트**를 가리키는지. 어긋나면 stdin 의 `cwd` 로 대체.
- **stdin JSON** ✅ — SessionEnd 는 stdin 으로 JSON payload 를 줌:
  ```json
  { "session_id": "...", "transcript_path": "...", "cwd": "...",
    "hook_event_name": "SessionEnd", "end_reason": "clear" }
  ```
  `cwd` 가 프로젝트 경로의 신뢰 가능한 fallback. `jq -r '.cwd' < /dev/stdin` 로 읽음.
- `end_reason` 값 ✅: `clear` / `resume` / `logout` / `prompt_input_exit` / `bypass_permissions_disabled` / `other`.

> 함의: `sync-memory.sh` 의 프로젝트 경로 도출을 `proj="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd')}"` 식으로 견고하게. (`_reference/hook-sync-research.md` §7a 는 `${CLAUDE_PROJECT_DIR:-$PWD}` 였음 — 플러그인 컨텍스트에선 stdin `cwd` 가 더 안전할 수 있으니 저자 확인 후 확정.)

---

## 5. SessionEnd 발화 caveat ⬜

- `/clear`, `--resume`/`--continue` 로의 일시정지, logout, `-p` 모드 입력 끝 등에서 발화.
- **hard kill(SIGKILL)/크래시 시 미발화 가능** — 다음 정상 종료가 따라잡으니 동기화는 결국 수렴(idempotent). 본문/README 에 "강제 종료 땐 다음 세션 끝에 반영" 한 줄 명시 권장.
- ⬜ 저자가 fork 에서 정상 종료·`/clear`·Ctrl-C 각각에 발화 여부 관찰 (Langfuse trace + `.opencode/from-claude.md` mtime).

---

## 6. marketplace.json (repo 를 설치 가능하게) ✅

위치: **repo 루트의 `.claude-plugin/marketplace.json`** (하위 폴더 아님).

```json
{
  "name": "multi-harness-plugins",
  "owner": { "name": "Jet" },
  "plugins": [
    {
      "name": "claude-to-opencode-sync",
      "source": "./claude-code",
      "description": "CC -> OpenCode: flatten project memory on session end"
    }
  ]
}
```

- `source` 는 상대경로(이 repo 안 하위 폴더), GitHub shorthand(`owner/repo`), 또는 source 객체 가능. 같은 repo 안 플러그인이면 상대경로(`./claude-code`)가 깔끔.
- OC 플러그인을 여기 같이 등록할지는 Step 2 에서 (OC 는 marketplace 가 아니라 opencode.json `plugin`/npm 경로라, marketplace.json 엔 CC 만 들어갈 수도 있음).

---

## 7. 유저 설치 명령 ✅

```bash
# 1) marketplace 추가 (1회)
/plugin marketplace add Taekyo-Lee/multi-harness-plugins

# 2) 플러그인 설치
/plugin install claude-to-opencode-sync@multi-harness-plugins
```

비대화형(CLI):
```bash
claude plugin marketplace add Taekyo-Lee/multi-harness-plugins
claude plugin install claude-to-opencode-sync@multi-harness-plugins --scope user
```

브랜치/태그 고정: `/plugin marketplace add Taekyo-Lee/multi-harness-plugins@v0.1.0`.

---

## 8. 버전 요구사항 ✅(docs 기준)

- marketplace / 플러그인-번들 hook(`hooks/hooks.json`): Claude Code v2.1.0+.
- ⬜ 저자 fork 버전이 이를 충족하는지 한 번 확인 (`claude --version`).

---

## 9. gotchas

- hook JSON 유효성: `claude plugin validate ./claude-code` 로 검증. `matcher` 는 `"clear|resume"` 형태(공백·따옴표 분리 X).
- 스크립트 경로는 항상 `${CLAUDE_PLUGIN_ROOT}` (상대경로 X). 셸 form 이면 따옴표로 감쌀 것.
- stdin 은 JSON — `jq ... < /dev/stdin` 으로 파싱. 빈 줄로 읽지 말 것.
- `version` 을 plugin.json 과 marketplace.json 양쪽에 중복으로 박지 말 것 (한 곳만).
- 스크립트 `chmod +x` 잊지 말 것.
