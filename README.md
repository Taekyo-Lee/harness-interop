# Harness Interop

> AI 코딩 harness 사이의 **상호운용(interoperability)** 플러그인 모음. 첫 제품은 **프로젝트 한정 개인 메모리**를 harness 사이에서 자동 동기화하는 *Memory Bridge* 입니다.

한쪽 harness 에서 남긴 개인 메모리가 다음 세션엔 다른 harness 에도 가 있습니다. 파일은 제자리에 두고 내용만 건너가며, 오가는 파일이 모두 git 추적 밖이라 팀 repo 엔 새지 않습니다.

**현재 지원:** Claude Code ↔ OpenCode 개인 메모리 양방향 동기화 (Memory Bridge).
**예정:** harness 확장(Codex, Gemini CLI 등) + 메모리 외 상호운용(command·config 등). 같은 clobber-safe 패턴으로 늘려갑니다.

> 배경과 설계 의도는 블로그 글 *「Claude Code 와 OpenCode 를 함께 쓸 때, 팀과 공유하지 않는 개인 지침 배치」* (claude-code-vs-opencode 시리즈) 에서 다룹니다.

---

## 무엇을 푸나

Claude Code 와 OpenCode 는 *프로젝트 한정 개인 메모리* 를 완전히 다르게 다룹니다.

- **Claude Code** 는 모델이 *스스로* 사실을 쌓는 memory 시스템이 있고, 그 노트를 **repo 바깥** (`~/.claude/projects/<slug>/memory/`) 에 둡니다. git 에 올라갈 일이 구조적으로 없습니다.
- **OpenCode** 엔 그런 전용 memory 시스템이 없습니다. 개인 노트를 **repo 안** 파일에 직접 적고, `opencode.json` 의 `instructions` 로 끌어오며, `.gitignore` 로 git 에서 빼야 합니다.

메커니즘이 이렇게 다르니 한 파일로 합칠 수 없습니다. 그래서 **각자 두고 내용만 옮기되, 그 옮기기를 hook 으로 자동화**합니다.

---

## 어떻게 동작하나

두 개의 다리가 양방향으로 놓입니다.

```
   Claude Code                                        OpenCode
 ─────────────                                       ──────────
                      ①  SessionEnd hook (세션 끝)
  memory/*.md  ───────────────────────────────────►  .opencode/from-claude.md
  (자율 + 수동)            내용을 flatten 해서 복사            (instructions 로 읽힘)


                      ②  session.idle plugin (턴 끝마다)
  memory/from-opencode.md  ◄───────────────────────  .opencode/personal.md
  (CC 가 자동 로드)         내용을 복사 + 인덱스 갱신          ("기억해줘" 로 쌓임 †)
```

> † OpenCode 가 "기억해줘" 를 `personal.md` 에 적는 건, OC 플러그인이 `personal.md` 헤더에 "기억 요청이 오면 여기 적어라" 안내를 넣고 그 파일을 `opencode.json` 의 `instructions` 로 등록하기 때문입니다 (매 세션 시스템 프롬프트에 실림). 팀 공유 파일인 `AGENTS.md` 가 아니라 gitignored `personal.md` 에 두는 이유 — 개인 메모리 지시를 팀 repo 로 새지 않게.

| # | 방향 | 발화점 | 하는 일 |
|---|---|---|---|
| ① | CC → OpenCode | Claude Code `SessionEnd` hook | memory 폴더를 flatten → `.opencode/from-claude.md` |
| ② | OpenCode → CC | OpenCode `session.idle` plugin | `.opencode/personal.md` → CC memory 의 `from-opencode.md` 로 복사하고, CC 의 `MEMORY.md` 인덱스도 갱신 |

오가는 파일은 4개이고, **각 파일에는 쓰는 쪽이 딱 하나** 입니다 (서로 덮어쓰지 않는 *clobber-safe* 레이아웃).

| 파일 | 위치 | 쓰는 쪽 | 읽는 쪽 |
|---|---|---|---|
| `memory/*.md` (단 `from-opencode.md` 제외) | repo 바깥 `~/.claude/projects/<slug>/memory/` | Claude Code (자율+수동) | Claude Code |
| `.opencode/from-claude.md` | repo 안 (gitignored) | **CC `SessionEnd` hook** | OpenCode |
| `.opencode/personal.md` | repo 안 (gitignored) | OpenCode 모델 | OpenCode |
| `memory/from-opencode.md` | repo 바깥 | **OC plugin** | Claude Code |

각 hook 은 *자기 출처에만 쓰고 상대 출처는 읽기만* 합니다. CC hook 은 `from-claude.md` 만 쓰고 flatten 때 `from-opencode.md` 는 건너뜁니다 (에코 차단). OC plugin 은 `personal.md` 만 보내고 `from-claude.md` 는 건드리지 않습니다.

---

## 설치

두 harness 의 설치 방식이 다릅니다 — Claude Code 는 marketplace 로, OpenCode 는 파일 복사로.

### 사전 요구사항

- **Claude Code** — `SessionEnd` hook 스크립트는 `bash` 로 돕니다. `jq` 가 있으면 좋습니다 (stdin payload 파싱용 — 없어도 `CLAUDE_PROJECT_DIR` 로 동작).
- **OpenCode** — 별도 설치 불필요. 플러그인 의존성(`@opencode-ai/plugin`) 은 OpenCode 가 처음 로드할 때 자동으로 받아옵니다.

### 1. Claude Code 플러그인 (CC → OpenCode)

이 repo 가 곧 marketplace 입니다. Claude Code 안에서:

```text
/plugin marketplace add Taekyo-Lee/harness-interop
/plugin install memory-bridge-claude@harness-interop
```

설치하면 `SessionEnd` hook 이 걸립니다. 세션을 끝낼 때마다 이 프로젝트의 CC memory 가 `.opencode/from-claude.md` 로 flatten 됩니다.

### 2. OpenCode 플러그인 (OpenCode → CC)

OpenCode 는 `.opencode/plugin/*.ts` 를 **자동 발견** 합니다. 동기화할 프로젝트 루트에서 플러그인 파일 하나만 떨어뜨리면 됩니다.

```bash
mkdir -p .opencode/plugin
curl -fsSL \
  https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/opencode/plugin/memory-bridge-opencode.ts \
  -o .opencode/plugin/memory-bridge-opencode.ts
```

그다음 그 프로젝트에서 OpenCode 를 열면 플러그인이 알아서:

- `opencode.json` 의 `instructions` 에 `personal.md` 와 `from-claude.md` 를 추가하고,
- `.gitignore` 에 동기화 파일들을 추가하고 (이미 `.opencode/` 를 통째로 ignore 중이면 건너뜀),
- `.opencode/personal.md` 에 "기억 요청이 오면 여기 적어라" 안내 헤더를 넣습니다.

`opencode.json` 도 `.gitignore` 도 **직접 손댈 필요가 없습니다.** 파일을 떨어뜨리는 것이 설치의 전부입니다.

---

## 써보기

1. **Claude Code 에서** 무언가를 기억시킵니다 — 예: "Kim's favorite movie 는 Rashomon 이야, 기억해줘". 세션을 끝내면(`/exit`) `.opencode/from-claude.md` 에 그 사실이 flatten 됩니다.
2. **OpenCode 를 그 프로젝트에서** 열고 "Kim's favorite movie 알아?" 라고 물으면, `from-claude.md` 가 `instructions` 로 실려 있어 대답합니다.
3. **OpenCode 에서** 거꾸로 기억시킵니다 — "Henry 별명은 IRON MAN, 기억해줘". 모델이 `.opencode/personal.md` 에 적고, 턴이 끝나면 플러그인이 CC memory 의 `from-opencode.md` 로 복사합니다.
4. **Claude Code 를 다시** 열고 "Henry 별명 알아?" 라고 물으면, `MEMORY.md` 인덱스에서 그 사실을 보고 노트를 읽어 대답합니다.

오가는 파일은 모두 gitignored 라 팀원이 clone 해도 보이지 않습니다.

---

## 디렉토리 레이아웃

```
harness-interop/
├── .claude-plugin/
│   └── marketplace.json          # 이 repo 를 Claude Code marketplace 로
├── claude-code/                  # ① CC → OpenCode 플러그인
│   ├── .claude-plugin/plugin.json
│   ├── hooks/hooks.json          # SessionEnd hook 등록
│   └── scripts/memory-bridge.sh  # flatten 스크립트
├── opencode/                     # ② OpenCode → CC 플러그인 (복사해서 설치)
│   └── plugin/memory-bridge-opencode.ts
└── README.md
```

---

## 만든이

**Jet** ([Guru Cat](https://github.com/Taekyo-Lee)) · gurucat72@gmail.com

라이선스: MIT
