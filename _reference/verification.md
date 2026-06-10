# 4편 검증 — 개인 지침 (personal-instructions-two-harnesses)

> 본문(`../index.mdx`)의 *리뷰 포인트* + *저자 실행용 검증 가이드*.
> 카테고리 `CLAUDE.md` §5: **fact 는 코드 grep(Claude), 동작은 trace(저자 직접).** 흐름 단방향.
>
> **조사 시점**: OpenCode main, 2026-06-04 (`27e74d32b`).

---

## 0. 한눈에

| 영역 | 상태 |
|---|---|
| user scope first-match (AGENTS → CLAUDE fallback) | ✅ 코드 + 2편에서 검증 (§1) |
| opencode.json instructions = 항상 attach, gitignored 가능 | ✅ 코드로 닫힘 (§1) |
| OpenCode 자율 memory 부재 | ⚠ **보정 필요** — beast 프롬프트(GPT-4/o1/o3)에 `# Memory` 존재(단 미로드·도구 부재·docs 무). flat 부정 금지. §1 ⚠note + R10 |
| "OpenCode 에 repo 바깥 per-project instruction store 부재" | ⚠ 코드 enumeration 근거 — §2 R2 에서 저자 재확인 권장 |
| editorial 판단 | ⏳ §2 |
| 동작 검증 (.opencode/personal.md 채널, 누설 없음) | ✅ 닫힘 — **T3·T4·T5(R9)·T6(R10) ✅** + T2 라이브, T1 선택 (2026-06-07) |
| §3 양방향 hook artifact (CC↔OC 자동 동기화) | ⬜ **T7 신규** — G(slug 동일성) 게이트 + OC→CC plugin(`session.idle`). 설계 `hook-sync-research.md`. 저자 검증 대기 |

가장 단정 수위가 높은 claim 은 *축 1(위치)* 의 "OpenCode 엔 repo 바깥 개인 store 가 없다" 예요. 코드상 instruction source 가 *global* 아니면 *repo 안* 인 것에서 도출했지만, presentation 전에 한 번 더 점검할 가치가 있어 R2 로 뺐습니다.

---

## 1. 코드로 닫힌 fact

| 본문 주장 | 출처 |
|---|---|
| user scope: `~/.config/opencode/AGENTS.md` → `~/.claude/CLAUDE.md` first-match | `instruction.ts:63-66, 114-119` |
| opencode.json `instructions` = 조건 없이 항상 attach | `instruction.ts:134-148` |
| `instructions` 는 `~/`·절대경로·glob·URL 지원 | `instruction.ts:137-146` |
| instruction *로딩 코드* 는 read-only (loader 가 파일을 write 안 함). 단 모델은 일반 Edit/Write 도구로 instruction 파일을 고칠 수 있음 → R9·R10 | `instruction.ts` (read/glob/find 만, write 부재); 일반 file 도구는 별개 (T5 실측) |
| 자율 memory 페이지 docs 사이드바 부재 | opencode.ai/docs 사이드바 (memory 항목 없음) |
| MEMORY.md = `~/.claude/projects/<id>/memory/`, repo 바깥, 모델 자동+수동 | 8편 `sharing-memory-md` (이미 검증) |
| `~/.claude/CLAUDE.md` machine-wide 개인 자리 | 7편 `placing-long-term-memory` (이미 검증) |

**⚠ CRITICAL 보정 (2026-06-07 재조사: opencode-fork HEAD 2026-06-03 + opencode.ai/docs 라이브). '"OpenCode 엔 memory 없음" flat 단정 금지.**
- memory **도구 없음** (`packages/opencode/src/tool/` 에 memory/remember tool 부재 — edit/write/read/grep/todo/task 등뿐).
- docs 에 memory **기능/페이지 없음** (opencode.ai/docs 사이드바). `/init` 은 명시 호출로 AGENTS.md 생성·개선만 (자율 아님).
- 어떤 memory 파일도 **자동 로드 안 함** — `instruction.ts` 는 AGENTS.md/CLAUDE.md/CONTEXT.md + 글로벌(`~/.config/opencode/AGENTS.md`, `~/.claude/CLAUDE.md`) + opencode.json instructions 만. `.github/instructions/memory.instruction.md` grep 0.
- **그러나** `session/prompt/beast.txt:113-123` 에 `# Memory` 섹션: *"You have a memory… stored in `.github/instructions/memory.instruction.md`… update it when asked"*. 그리고 **beast 는 GPT-4/o1/o3 의 기본 system 프롬프트** (`session/system.ts:20-21`) — 흔한 경우. (VS Code Copilot 'Beast Mode' 프롬프트를 그대로 가져온 것.) 모델은 일반 Edit/Write 로 그 파일을 고치지만, OpenCode 가 그걸 **자동 로드하지 않아** 세션 간 지속이 안 됨 = back 없는 write-only.
- 참고: T5 의 glm-5 는 default 프롬프트(beast 아님)라 # Memory 안내가 없어 '저장해줘' 에 AGENTS.md 를 직접 Edit 함. gpt-4 였다면 beast 안내 따라 `.github/instructions/memory.instruction.md` 로 갔을 것.
- **정밀 framing → R10.**
- **upstream 확인 (2026-06-07, git)**: beast.txt + `system.ts` 의 gpt-4/o1/o3→beast 라우팅은 **upstream anomalyco/opencode** 소속 (beast 커밋 = Dax Raad "update beast prompt for openai models" 등 + 커뮤니티 typo PR; 라우팅 = Kit Langton/Dax PR — *저자 fork 추가 아님*). 유저 `opencode` 바이너리 자체는 fork(`~/workspace/opencode-fork`, upstream=anomalyco/opencode)지만 이 메커니즘은 upstream 동일 → callout 은 *진짜 OpenCode* 동작. beast.txt 최종 변경 2026-02-10(typo)라 본문 시점-anchor(2026-06-04)와 정합.
- **다른 모델 추가 테스트 불요**: `# Memory` 는 *오직 beast.txt* (나머지 anthropic/gemini/kimi/codex/gpt/copilot-gpt-5/default 전부 memory 없음, grep 확인). gpt-4·o1·o3 만 beast → T6(gpt-4o)가 대표; 그 외 모델은 memory 관습 자체가 없어 T5(glm-5=default)처럼 '부재' 재확인일 뿐. xai.ts 'memory' = in-memory 캐시(무관).

---

## 2. 저자 리뷰 포인트

- [ ] **R1. MEMORY.md 내부 재설명 생략.** 위치(`<id>` 식별자)·autoMemoryDirectory·worktree 차이 등은 8편 cross-ref 만 하고 재설명 안 함. 병행 환경 글로서 적절한 깊이인지 (재독자 친절 vs 중복).
- [ ] **R2. ⚠ "repo 바깥 per-project store 부재" 단정.** 4편에서 가장 센 claim. 코드 enumeration 으로 도출(global/repo-내부만 존재). §3 T3 로 *대체 채널이 실제로 .opencode/personal.md 패턴뿐인지* 저자가 한 번 확인하면 안심. 혹시 회사에서 다른 OpenCode 개인 채널을 쓰고 있으면 본문 보정.
- [ ] **R3. 자율 memory 부재 §3 framing.** "OpenCode 에는 없어요" 가 *부재* 서술로 끝나는지, *약함* 으로 새지 않는지. 축 2 의 핵심.
- [ ] **R4. `.opencode/personal.md` 패턴이 회사 관행과 맞나.** opencode.json instructions → gitignored 파일을 권장 패턴으로 제시함. 회사에서 실제로 쓰는 개인 채널이 이거인지, 아니면 global config 경유인지.
- [ ] **R5. promotion 종착지 = AGENTS.md tie-back.** 3편의 *팀 정본 AGENTS.md (+다리)* 로 promote 종착지를 연결함. 두 편을 묶는 핵심 다리라 자연스러운지 확인.
- [ ] **R6. *자리 / 모양* idiom.** 3편 R2 와 동일 (메모리 충돌). 두 편 함께 결정.
- [ ] **R7. machine-wide "happy accident" framing.** `~/.claude/CLAUDE.md` 가 양쪽에 닿는 걸 2편 ANCHOR 에 기대어 서술. 2편 안 읽은 독자에게도 성립하는지 (cross-ref 충분한지).
- [ ] **R8. CLAUDE.local.md 채널 누락?** (2026-06-07 검증 repo 환경에서 발견) 본문 축 1 은 Claude Code project-개인 = MEMORY.md(repo 바깥)로만 제시하는데, Claude Code 엔 *repo 안 gitignored* 개인 채널인 `CLAUDE.local.md` 도 있음 (`claudemd.ts:944-955`, Local type; 검증 repo `claude-context-engineering` 의 .gitignore 에도 `CLAUDE.local.md`·`GEMINI.local.md` 가 이미 들어있음). 이건 OpenCode 의 `.opencode/personal.md`(repo 안 gitignored 수동)와 *직접 평행*. 본문이 MEMORY.md(자율)에 초점 두려고 의도적으로 뺀 건지, 아니면 축 1 에 'Claude Code 도 repo 안 옵션(CLAUDE.local.md)이 있다'를 한 줄 넣을지 리뷰에서 결정. (축 2 자율 vs 수동 대비는 그대로 유효.)
- [ ] **R9. 축 2 'read-only / 사람이 손으로' 수위 (T5 실측 발견).** T5 에서 OpenCode 모델(glm-5)이 "memory 에 저장" 요청에 *일반 Edit 도구로 AGENTS.md 를 직접 수정* 함 (memory 시스템이 없으니 때운 것). 'instruction *로딩* 시스템 read-only'(`instruction.ts`)는 맞지만, 본문 line 259·261 의 "모델이 instruction 파일에 써넣는 경로가 없어요" / "모든 개인 지침을 사람이 손으로 적습니다" 는 *tool 가진 agent 가 일반 파일 도구로 instruction 파일을 고칠 수 있다* 는 실측과 충돌 소지. 보정안: "자율/전용 memory *시스템* 부재(백그라운드 자동 축적·전용 store 없음)" 로 한정하고, "일반 파일 도구로 직접 편집은 가능하지만 그건 memory 가 아니라 수동 편집" 한 줄. 축 2 의 *자율 memory 부재* 결론 자체는 유지.
- [x] **R10. ⚠→✅ 축 2 'OpenCode 엔 memory 없음' = beast.txt 때문에 위험 (2026-06-07 재조사, §1 ⚠note; 본문 콜아웃 반영 + T6 PASS).** GPT-4/o1/o3 의 기본 프롬프트 `beast.txt` 에 `# Memory`(`.github/instructions/memory.instruction.md`) 섹션이 있어, *flat 부정은 GPT-4 사용자에게 즉시 반박당함* (저자 우려 지점). 단 (a) memory 도구 없음 (b) 그 파일을 OpenCode 가 자동 로드 안 함 → 세션 간 지속 X (c) docs 무. **보정안**: 본문 축 2 를 *"OpenCode 엔 1급 memory **서브시스템** 이 없다 (전용 도구·관리 store·자동 로드 전무, docs 무). GPT-4 계열 preset(beast)이 Copilot 에서 가져온 `# Memory` 줄을 갖지만, OpenCode 가 그 파일을 자동 로드하지 않아 진짜 지속 memory 가 아니라 일반 파일 편집일 뿐"* 으로 재작성. Claude Code 는 전용 메커니즘(도구+관리 store+매 세션 자동 로드). **4편에서 가장 시급한 정확도 이슈.** → **해결: 본문 콜아웃('🔍 그럼 beast 의 # Memory 는?') 추가 + 주장 완화('1급 시스템 없음') + T6 양쪽 part PASS(2026-06-07). 표현 최종 다듬기만 내일 review.**

---

## 3. 실행 검증 (저자가 직접)

> **검증 repo**: 모든 테스트는 실 repo `~/workspace/claude-context-engineering` 에서 (3편과 동일, 회사도 동일). 아래 *공통 검증 repo* 참고.
> **4편 테스트는 전부 OpenCode 쪽**(T1~T5)이라 실행은 `opencode` 만 — claude/claude-fork 구분 불필요 (OpenCode 는 Langfuse 라우팅 걱정 없음). Claude Code 주장(machine-wide `~/.claude/CLAUDE.md`, MEMORY.md)은 2·7·8편 + 3편 trace 로 이미 닫힘.
> **주의**: T1·T2 는 *global 개인 파일* 을 건드려 백업 필요 + 이미 2편 검증 → 선택(T2 는 아래대로 이미 라이브). **T3·T4·T5 가 4편 고유 필수**, claude-context-engineering 안에서 비파괴로.

### 관찰 자리 (공통)

| harness | trace 에서 볼 곳 | 패턴 |
|---|---|---|
| OpenCode | 첫 generation system input | `Instructions from: <path>` + magic |
| Claude Code | 첫 user message `<system-reminder>` | `# claudeMd` 의 `Contents of <path>` + magic |

### 공통 검증 repo

모든 동작 검증은 실 repo `~/workspace/claude-context-engineering` 에서 (3편과 동일, 회사도 동일). cwd 한 번만 잡고 아래 블록을 그 안에서 실행.

```bash
cd ~/workspace/claude-context-engineering   # 아래 블록은 이 안에서 (블록마다 cd 반복 안 함)
```

- **바이너리**: 4편 T1~T5 는 전부 OpenCode → 그냥 **`opencode`**. claude/claude-fork 구분은 *Claude Code* trace 테스트에만 해당(3편: trace 필요하면 `claude-fork`, 아니면 `claude`) — 4편엔 Claude Code 테스트가 없어 안 씀. OpenCode 는 Langfuse 라우팅 걱정 없음.
- **환경 사실 (이 머신, 2026-06-07 확인)**: OpenCode user-scope 는 `~/.config/opencode/AGENTS.md` 가 **존재**(`# Global AGENTS.md`) → first-match. `~/.claude/CLAUDE.md` 는 **부재** → fallback 안 탐. 그래서 **T2(user-scope shadowing)는 이미 라이브 상태** — 이 세션 초반 OpenCode trace 가 `Instructions from: ~/.config/opencode/AGENTS.md` 만 있고 `~/.claude/CLAUDE.md` 는 없는 걸 그대로 보여줬음.
- **예상 OpenCode trace noise (결과 무관)**: user-scope `~/.config/opencode/AGENTS.md` + project `…/claude-context-engineering/AGENTS.md`(기존 `Project Root AGENTS.md`) 가 같이 뜸. magic 문구로 personal 채널만 골라 봄.
- **비파괴 (실 repo)**: git clean 유지. **`rm -rf`·`git push` 금지.** 생성 파일만 만들고 끝나면 지움. `.gitignore` 는 tracked 라 *append* 후 `git checkout -- .gitignore` 로 복구. 안전망: `git reset --hard origin/main` + `git clean -fd`.

> **Claude Code 쪽 cross-ref**: machine-wide `~/.claude/CLAUDE.md` 가 Claude Code 에 닿는다는 주장은 3편 T2/T3 trace 에서 fork user-scope `~/.claude-fork/CLAUDE.md`(`# << USER LEVEL CLAUDE.md >>`) 블록으로 이미 관측됨 (공식 `claude` = `~/.claude/CLAUDE.md`, fork = `~/.claude-fork` remap). MEMORY.md 는 8편 검증. 그래서 4편은 OpenCode 쪽만 새로 확인.

---

### T3 (필수). OpenCode 의 project 개인 채널 — gitignored 파일을 attach 하나

**가설**: opencode.json 의 `instructions: [".opencode/personal.md"]` 가 gitignored 파일을 항상 attach. trace 에 그 magic.

**fixture** (repo `~/workspace/claude-context-engineering`)
| 파일 | git | 내용 |
|---|---|---|
| `opencode.json` | 새로 생성 | `{ "instructions": [".opencode/personal.md"] }` |
| `.gitignore` | 기존에 append | `.opencode/personal.md` 한 줄 추가 |
| `.opencode/personal.md` | **ignored** | `MAGIC-PERSONAL: vault-indigo-5` |

```bash
# (cwd = ~/workspace/claude-context-engineering)
mkdir -p .opencode
printf '{\n  "instructions": [".opencode/personal.md"]\n}\n' > opencode.json
printf '\n# (T3 fixture)\n.opencode/personal.md\n' >> .gitignore        # append, 덮어쓰기 아님
printf 'MAGIC-PERSONAL: vault-indigo-5\n' > .opencode/personal.md
git check-ignore .opencode/personal.md   # 경로가 출력되면 = gitignored (commit 불필요)
opencode   # 아무 프롬프트 한 번, 종료
# --- 복구 ---
rm -rf .opencode opencode.json
git checkout -- .gitignore
```

**체크리스트**
| 봐야 할 것 | 기대 |
|---|---|
| `Instructions from: …/claude-context-engineering/.opencode/personal.md` | 있음 |
| `MAGIC-PERSONAL: vault-indigo-5` | 있음 |
| `git check-ignore` 출력 | `.opencode/personal.md` (= ignored) |
| (noise) user-scope `~/.config/opencode/AGENTS.md` + project `AGENTS.md` | 같이 뜸 (무관) |

**✅ 결과 (2026-06-07, 저자 실행 — PASS).** 실 repo `claude-context-engineering` 에 opencode.json(`instructions: [".opencode/personal.md"]`) + gitignored `.opencode/personal.md`(MAGIC-PERSONAL), `opencode`(모델 glm-5) 프롬프트 `say hello`. system input:
- ✅ `Instructions from: …/claude-context-engineering/.opencode/personal.md` → `MAGIC-PERSONAL: vault-indigo-5` → **gitignored 개인 파일이 opencode.json instructions 로 attach 됨**.
- ✅ Step 1 의 `git check-ignore` + `git status`(personal.md 안 잡힘)로 repo 비노출 확인.
- ℹ️ 예상 noise 그대로: user-scope `~/.config/opencode/AGENTS.md`(# Global AGENTS.md) + project `AGENTS.md`(Project Root AGENTS.md). 로딩 순서 env → user AGENTS → project AGENTS → personal.md(instructions) → skills.
- → 본문 축 1 의 OpenCode 개인 채널(`.opencode/personal.md` via opencode.json instructions) empirical 확정.

---

### T4 (필수). 누설 없음 — fresh clone 엔 개인 파일이 안 따라가나

**가설**: gitignored 라 clone 한 팀원에겐 파일이 없음 → OpenCode 가 매치 0 개로 *조용히* 넘어감 (에러 없음, 개인 노트 비노출).

> clone 은 commit 된 내용만 가져가요. 그래서 T4 만 *임시 commit* 이 필요 — 실 repo 라 **반드시 reset 으로 원복**. personal.md 는 gitignored 라 commit 에 안 들어감. (블록 self-contained — fixture 부터 만듦.)

```bash
# (cwd = ~/workspace/claude-context-engineering) — fixture 셋업
mkdir -p .opencode
printf '{\n  "instructions": [".opencode/personal.md"]\n}\n' > opencode.json
printf '\n# (T4 fixture)\n.opencode/personal.md\n' >> .gitignore
printf 'MAGIC-PERSONAL: vault-indigo-5\n' > .opencode/personal.md
# 임시 commit → clone → 관찰
ORIG=$(git rev-parse HEAD)                  # 원본 HEAD 기록
git add opencode.json .gitignore            # config 만 stage (personal.md 는 ignored 라 안 들어감)
git commit -qm "TEMP T4 fixture (reset 예정)"
cd /tmp; rm -rf personal-clone
git clone -q ~/workspace/claude-context-engineering personal-clone; cd personal-clone
ls .opencode/personal.md 2>/dev/null && echo "LEAKED" || echo "OK: not present"
opencode   # clone 안에서 아무 프롬프트 한 번, 종료
# --- 원본 repo 복구 ---
cd ~/workspace/claude-context-engineering
git reset --hard "$ORIG"     # TEMP commit + .gitignore/opencode.json 원복
rm -rf .opencode             # untracked personal.md/dir 제거
rm -rf /tmp/personal-clone
```

**체크리스트**
| 봐야 할 것 | 기대 |
|---|---|
| clone 의 `.opencode/personal.md` 존재 | 없음 (안 따라감) |
| clone trace 에 `MAGIC-PERSONAL` | **없음** |
| OpenCode 에러/경고 | 없음 (매치 0 으로 조용) |
| 복구 후 원본 `git status` | clean (`origin/main`) |

**✅ 결과 (2026-06-07, 저자 실행 — PASS).** T3 fixture 를 임시 commit(`ORIG=f940e0f`) 후 `/tmp/personal-clone` 으로 clone, clone 안에서 `opencode`(glm-5). 관측:
- ✅ clone 에 `.opencode/personal.md` 없음 (`OK: not present`) — gitignored 라 clone 에 안 따라옴. tracked `opencode.json`(personal.md 를 가리킴)은 따라옴.
- ✅ clone trace 에 `MAGIC-PERSONAL` 없음, `Instructions from: …/personal-clone/.opencode/personal.md` 헤더도 없음 → 없는 파일을 OpenCode 가 **조용히 skip** (에러/경고 없음).
- ✅ clone 엔 user-scope `# Global AGENTS.md` + clone project `Project Root AGENTS.md` 만 정상 attach.
- → 본문 '누설 없음' (gitignore 규율 → 개인 노트가 팀원 clone 에 안 감 + OpenCode 매치 0 조용히 skip) empirical 확정.

---

### T5 (보너스). 자율 write-back 부재 재확인

**가설**: 세션 중 OpenCode 가 AGENTS.md / instructions 파일에 *스스로 써넣지* 않음 (read-only).

```bash
# (cwd = ~/workspace/claude-context-engineering) — fixture 셋업
mkdir -p .opencode
printf '{\n  "instructions": [".opencode/personal.md"]\n}\n' > opencode.json
printf '\n# (T5 fixture)\n.opencode/personal.md\n' >> .gitignore
printf 'MAGIC-PERSONAL: vault-indigo-5\n' > .opencode/personal.md
# 해시 비교
sha1sum AGENTS.md .opencode/personal.md   # 실행 전 해시
opencode   # "이 프로젝트에 대해 기억해둘 만한 걸 메모해줘" 같이 memory 유도 프롬프트, 종료
sha1sum AGENTS.md .opencode/personal.md   # 실행 후 해시: 같아야 함 (모델이 안 씀)
# --- 복구 ---
rm -rf .opencode opencode.json; git checkout -- .gitignore
```

**체크리스트**
| 봐야 할 것 | 기대 |
|---|---|
| `.opencode/personal.md` 해시 | 동일 (모델이 안 건드림) |
| 전용/자율 memory store 에 자동 기록 | 없음 (OpenCode 에 memory 시스템 부재) |
| AGENTS.md 등 instruction 파일 | agent 가 *일반 Edit 도구* 로 요청받아 바꿀 수 있음 (memory 아님). `git checkout` 으로 원복 |

**✅/⚠️ 결과 (2026-06-07, 저자 실행).** fixture 위에서 `opencode`(glm-5) 에 "커밋 전 lint 규칙을 memory 에 저장해줘" 프롬프트:
- 모델이 memory 도구가 없으니 **일반 Edit 로 AGENTS.md 에 직접 `## Pre-commit Rules / Always run lint before committing changes` 를 append** ("완료. AGENTS.md에 규칙을 추가했습니다").
- 해시: AGENTS.md `8610709…`→`9d11dfc…` (**바뀜**), `.opencode/personal.md` `6eeba47…` 그대로. `git checkout -- AGENTS.md` 로 원복.
- ✅ **확인**: 전용/자율 memory 시스템 없음 (모델이 일반 파일 편집으로 때움). docs memory 페이지 없음(§1).
- ⚠️ **보정 필요**: instruction 파일이 결과적으로 바뀜 → 본문 '읽기 전용'/'사람이 손으로만' 은 *로딩 코드* 한정으로 읽혀야 함. tool 가진 agent 는 일반 Edit 로 AGENTS.md 수정 가능. → R9.
- → 축 2 *자율 memory 부재* 결론은 확정, *표현 수위* 만 R9 에서 조정.

---

### T6 (보너스, R10). beast 프롬프트의 # Memory 가 실제로 어떻게 동작하나

callout(본문) 뒷받침용. **가설 둘**:
- (A) **gpt-4 계열(→beast)** 로 "기억해줘" 하면 모델이 `# Memory` 안내 따라 `.github/instructions/memory.instruction.md` 에 씀.
- (B) 그 파일은 **다음 세션에 자동 로드 안 됨** (`instruction.ts` 가 안 읽음) → "back 없는 메모".

> **모델**: id 에 `gpt-4`(또는 o1/o3) 포함돼야 beast 적용. 예: `opencode -m openai/gpt-4o` (본인 접근 가능한 것; openrouter 면 `-m openrouter/openai/gpt-4o`). beast 확인 = trace system 프롬프트에 "You are opencode, an agent - please keep going…" + `# Memory` 섹션.
> repo = claude-context-engineering. `.github` 는 원래 없음 → 끝나고 `rm -rf .github`. 비파괴.

**Part A — gpt-4 가 memory 파일에 쓰나**
```bash
# (cwd = ~/workspace/claude-context-engineering)
ls .github 2>/dev/null && echo "주의: .github 이미 있음" || echo ".github 없음 (정상)"
opencode -m openai/gpt-4o
#   프롬프트: "앞으로 이 repo 에선 커밋 전 항상 lint 돌리기. 이 규칙을 memory 에 저장해줘."
#   응답 + 건드린 파일 보고 종료
echo '--- memory 파일 ---'; cat .github/instructions/memory.instruction.md 2>/dev/null || echo "없음"
git status --short
```
| 봐야 할 것 (A) | 기대 |
|---|---|
| `.github/instructions/memory.instruction.md` 생성 + lint 규칙 (+ `applyTo: '**'` frontmatter) | 있음 (beast # Memory 관습) |
| AGENTS.md | 안 바뀜이 이상적 (gpt-4 는 memory 파일로). 바뀌면 `git checkout -- AGENTS.md` |

**Part B — 그 파일이 자동 로드되나 (핵심)**
```bash
# Part A 의 memory.instruction.md 가 있는 상태에서 새 세션:
opencode -m openai/gpt-4o
#   "say hello" 한 번, 종료 → Langfuse trace 의 system input 확인
```
| 봐야 할 것 (B) | 기대 |
|---|---|
| `Instructions from: …/.github/instructions/memory.instruction.md` 헤더 | **없음** (자동 로드 X) |
| lint 규칙 문구가 instruction 으로 실림 | **없음** |
| system 프롬프트의 `# Memory` 안내 텍스트 | 있음 — *프롬프트는 memory 를 약속하지만 파일은 안 실림* (이 대비가 callout 의 핵심) |

**✅ 결과 (2026-06-07, 저자 실행 — PASS, 양쪽 part).** `opencode -m openrouter/openai/gpt-4o` (→ beast 확인: system 프롬프트가 "You are opencode, an agent…" + `# Memory` 섹션).
- **Part A ✅**: "lint 규칙 memory 에 저장해줘" → 모델이 `* Glob "**/.github/instructions/memory.instruction.md"` 로 먼저 찾고 `# Wrote .github/instructions/memory.instruction.md` (`applyTo: '**'` frontmatter + lint 규칙). git status `?? .github/...` 만 — **AGENTS.md 안 건드림** (T5 의 glm-5 와 대비: 관습 있는 모델은 지정 memory 파일로).
- **Part B ✅ (핵심)**: 새 gpt-4o 세션 trace 의 `Instructions from:` 는 user-scope `# Global AGENTS.md` + project `Project Root AGENTS.md` **둘뿐**. `.github/instructions/memory.instruction.md` 헤더 **없음**, Part A 의 lint 규칙도 **안 실림**. 단 beast system 프롬프트엔 `# Memory` 안내 텍스트가 그대로 있음.
- ⭐ **한 trace 안의 대비**: 프롬프트는 "너 memory 있어(`.github/.../memory.instruction.md`)" 라 *약속* 하는데, OpenCode 로더는 그 파일을 *다시 안 읽음* → 모델이 저장한 memory 가 다음 세션에 안 돌아옴 = **back 없는 write-only**.
- → 본문 콜아웃 "🔍 그럼 beast 의 # Memory 는?" 의 모든 주장(beast 존재 · 일반 편집으로 씀 · 자동 로드 안 됨) 실측 뒷받침. R10 empirical 확정.

**복구**
```bash
rm -rf .github                          # 테스트로 생긴 것만 (원래 없었음)
git checkout -- AGENTS.md 2>/dev/null   # 혹시 모델이 건드렸으면
git status -sb                          # clean 확인
```

---

### T7 (필수, §3 양방향 artifact). hook 으로 개인 지침 *양방향* 동기화

> §3 가 *단방향 팁 → 양방향 artifact* 로 위상이 바뀜 (저자가 만들어 공개할 결과물). 이 테스트가 그 동작을 닫는다.
> 레퍼런스 구현·4파일 레이아웃·소스 앵커: `hook-sync-research.md` §6·§7·§9.
> ⚠ **T1~T6 중 처음으로 *진짜 CC memory 폴더* 를 건드리는 테스트.** OC→CC 다리가 `~/.claude/projects/<slug>/memory/from-opencode.md` 를 만든다. 전용 bridge 파일이라 노트 자체를 오염시키진 않지만 **끝나고 반드시 삭제**.

두 다리:
- **CC→OC**: `SessionEnd` hook → `.opencode/from-claude.md` (CC memory flatten, `from-opencode.md` 는 제외 = 에코 차단)
- **OC→CC**: plugin(`session.idle`) → `~/.claude/projects/<slug>/memory/from-opencode.md` (`.opencode/personal.md` 복사)

**검증 repo**: CC memory 가 *있는* repo 라야 의미가 있음. 이 블로그 repo(`~/workspace/taekyo-lee.github.io`)엔 이미 노트가 쌓여 있어 CC→OC flatten 을 바로 볼 수 있음. claude-context-engineering 으로 하려면 그 repo 의 CC memory 폴더가 먼저 있어야 함(없으면 G 만 먼저 보거나 `claude` 한 번 열어 노트 하나 남김).

#### G (게이트). slug 동일성 — OC `directory`→slug == CC memory 폴더

**왜 급소**: 양방향에서 새로 생긴 가정. OC plugin 이 받는 `directory` 로 slug 를 만들어 CC memory 폴더를 가리키는데, 이게 CC 의 `CLAUDE_PROJECT_DIR` slug 와 한 글자라도 다르면 OC 는 엉뚱한 폴더에 쓰고 CC 는 딴 데서 읽음 → **에러 없이 sync 실패**. G 가 무너지면 OC→CC 절반이 통째로 재설계.

**grounded(소스)**: OC 의 `directory` 는 `realpathSync(path.resolve(...))` 라 **symlink 를 끝까지 해석**한다 (`util/filesystem.ts:134-141`, 주석 "resolves symlinks so callers using the result as a cache key"; `instance-store.ts:106` 에서 `AppFileSystem.resolve(input.directory)`). 그래서 *프로젝트 경로에 symlink 구간이 있고 CC 는 그걸 안 푼다면* 두 slug 가 어긋난다. symlink 없는 평범한 경로면 일치 → 이 테스트로 *내 환경* 에서 직접 확인.

```bash
cd ~/workspace/taekyo-lee.github.io   # CC memory 가 있는 repo

# (1) CC 쪽 실제 memory 폴더 이름
ls -d ~/.claude/projects/*taekyo-lee-github-io*/memory

# (2) OC 가 plugin 에 줄 directory = repo 의 realpath, 그걸로 만든 slug
#     (OC plugin 의 directory.replace(/[^A-Za-z0-9]/g,'-') 와 동일 규칙)
printf '%s\n' "$(realpath .)"
printf '%s\n' "$(realpath .)" | tr -c '[:alnum:]' '-'

# (3) (참고) CC 가 보는 절대경로가 symlink 를 푸는지
pwd; pwd -P     # 두 값이 다르면 경로에 symlink 구간 있음 → 어긋날 소지
```

**관찰**:
- [ ] (1) 에서 `/memory` 를 뗀 `<slug>` 와 (2) 의 slug 가 **동일** → G 통과, OC→CC 가 같은 폴더를 가리킴.
- [ ] `pwd` 와 `pwd -P` 가 같음 (경로에 symlink 없음) → realpath 해석차로 어긋날 일 없음.
- [ ] 어긋나면 → plan B(`hook-sync-research.md` §5): plugin 이 `directory` 대신 CC 와 *같은 기준 경로* 를 쓰게 고정하거나, CC hook 이 memory 폴더 경로를 파일로 남겨 plugin 이 읽게. 결과 알려주면 레퍼런스 코드의 slug 도출을 그에 맞게 고침.

> **사전 대조 (2026-06-09, Claude — 파일시스템만)**: 이 블로그 repo 는 경로에 symlink 없음 (`pwd` = `pwd -P` = `realpath`), 그리고 `realpath`-slug 가 실제 CC memory 폴더명 `-home-jetlee-workspace-taekyo-lee-github-io` 와 **이미 일치**. 즉 *경로 도출* 쪽 G 는 초록불. 저자 T7 은 *런타임 값* (OC plugin 이 실제로 주는 `directory`, T7-a 의 probe 로그) 이 이와 같은지 확인하는 절차. claude-context-engineering 등 다른 repo 로 검증하면 그 repo 경로로 다시 대조.

#### T7-a. plugin 자동 로드 (`.opencode/plugin/`) + T7-b. session.idle 발화

**가설**: `.opencode/plugin/*.ts` 에 둔 plugin 이 opencode.json 등록 없이 자동 로드 (`config/plugin.ts:29` glob; gitignore 여도 디스크에 있으면 로드). 그리고 매 턴 종료(idle)마다 `event` hook 이 `session.idle` 을 받음.

fixture `.opencode/plugin/_probe.ts` (session.idle 마다 로그 남기는 최소 플러그인):
```ts
import type { Plugin } from "@opencode-ai/plugin"
import { appendFileSync } from "node:fs"
export const Probe: Plugin = async ({ directory }) => ({
  event: async ({ event }) => {
    if (event.type !== "session.idle") return
    appendFileSync("/tmp/oc-probe.log", `idle dir=${directory}\n`)
  },
})
```
```bash
mkdir -p .opencode/plugin
# (위 _probe.ts 를 .opencode/plugin/ 에 저장)
rm -f /tmp/oc-probe.log
opencode   # "say hello" → (가능하면 한 번 더 프롬프트) → 종료
cat /tmp/oc-probe.log 2>/dev/null || echo "안 찍힘"
```
| 봐야 할 것 | 기대 |
|---|---|
| `/tmp/oc-probe.log` 에 `idle dir=…` 줄 | 있음 → 자동 로드 + `session.idle` 발화 |
| 줄이 *턴마다* 쌓임 | idle = `Stop` 대응 cadence 확인 |
| `dir=` 값 | G 의 `realpath .` 와 동일해야 |
| 안 찍힘 | (a) 바이너리가 plugin 자동발견 미지원(구버전) → opencode.json `plugin: ["./.opencode/plugin/_probe.ts"]` 명시 시도, (b) `session.idle` 이 deprecated 로 빠짐 → 필터를 `event.type==="session.status" && event.properties.status?.type==="idle"` 로 바꿔 재시도. 어느 쪽이었는지 보고 |

#### T7-c. OC 가 `.opencode/from-claude.md` 를 attach (CC→OC 도착)

T3 와 같은 패턴. instructions 에 *2개째* 파일을 더해 그게 실리는지.
```bash
printf '{\n  "instructions": [".opencode/personal.md", ".opencode/from-claude.md"]\n}\n' > opencode.json
printf '\n# (T7 fixture)\n.opencode/personal.md\n.opencode/from-claude.md\n.opencode/plugin/_probe.ts\n' >> .gitignore
printf 'MAGIC-FROM-CLAUDE: relay-amber-7\n' > .opencode/from-claude.md
opencode   # 종료 → trace
```
| 봐야 할 것 | 기대 |
|---|---|
| `Instructions from: …/.opencode/from-claude.md` + `MAGIC-FROM-CLAUDE: relay-amber-7` | trace 에 있음 → CC→OC 가 instructions 2번째 파일로 도착 |

#### T7-d. CC 가 `from-opencode.md` 를 자동 로드 (OC→CC 도착) + 에코 차단

```bash
slug="$(printf '%s' "$(realpath .)" | tr -c '[:alnum:]' '-')"
mem="$HOME/.claude/projects/$slug/memory"
printf -- '---\nname: _t7_probe\ndescription: T7 test note\n---\nMAGIC-FROM-OPENCODE: relay-jade-3\n' > "$mem/from-opencode.md"   # ⚠ 표시된 테스트 파일
claude   # 새 세션 → 첫 system-reminder 의 # claudeMd / memory 에 magic 이 실리나
```
| 봐야 할 것 | 기대 |
|---|---|
| CC 세션 context 에 `MAGIC-FROM-OPENCODE: relay-jade-3` | 있음 → CC 가 `from-opencode.md` 를 자동 로드 (8편 MEMORY.md 패턴) |
| CC hook(`sync-memory.sh`) 한 번 더 돌린 뒤 `.opencode/from-claude.md` 안에 `MAGIC-FROM-OPENCODE` | **없어야 함** → flatten 이 `from-opencode.md` 를 제외 = 에코 차단 동작 |

**복구 (반드시)**
```bash
rm -f "$mem/from-opencode.md"          # ⚠ CC memory 에 둔 테스트 노트 삭제 (진짜 memory 오염 방지)
rm -rf .opencode opencode.json /tmp/oc-probe.log
git checkout -- .gitignore
git status -sb                          # clean 확인
```

#### 본문 주장 ↔ 관찰 매핑 (채워서 회신)
| 항목 | 관찰 결과 | 표현 수정? |
|---|---|---|
| G slug 동일성 (symlink 케이스 포함) | | |
| plugin 자동 로드 (`.opencode/plugin/`) | | |
| `session.idle` 발화 (deprecated fallback 필요?) | | |
| OC 가 `from-claude.md` attach | | |
| CC 가 `from-opencode.md` 로드 + 에코 차단 | | |

이 표를 채워 주면 §3 양방향 본문의 단정 표현을 관찰에 맞게 고침. (흐름: 저자 실행·관찰 → Claude 가 본문 반영.)

---

### T1·T2 (선택, global 건드림 — 백업 후). user scope fallback / shadowing

> 이미 2편에서 검증됨. 재현하려면 실제 global 파일을 임시 조작하므로 **반드시 백업**.

**이 머신 현재 상태 (2026-06-07)**: `~/.config/opencode/AGENTS.md` **존재**, `~/.claude/CLAUDE.md` **부재**. 그래서:
- **T2(shadowing)는 이미 라이브** — 별도 셋업 없이 이 세션 초반 OpenCode trace 가 `Instructions from: ~/.config/opencode/AGENTS.md` 만 보이고 `~/.claude/CLAUDE.md` 는 없는 상태를 그대로 보여줬음. 추가 확인 불필요.
- **T1(fallback) 재현** 은 `~/.config/opencode/AGENTS.md` 를 잠깐 치우고 `~/.claude/CLAUDE.md` 를 만들어야 발동 → global 2개 조작이라 백업 필수 + 이미 2편 검증 → *권장 안 함*.

```bash
# T1 재현이 정말 필요할 때만 (global 조작, 백업/원복 포함):
[ -f ~/.config/opencode/AGENTS.md ] && mv ~/.config/opencode/AGENTS.md /tmp/bak.opencode.AGENTS.md
mkdir -p ~/.claude; printf 'MAGIC-USER-CLAUDE: ridge-teal-2\n' > ~/.claude/CLAUDE.md   # fallback 타깃 생성
opencode   # trace 에 MAGIC-USER-CLAUDE 등장 = fallback 발동
# 원복:
rm -f ~/.claude/CLAUDE.md
[ -f /tmp/bak.opencode.AGENTS.md ] && mv /tmp/bak.opencode.AGENTS.md ~/.config/opencode/AGENTS.md
```

---

## 4. 검증 후 반영 흐름

1. T3·T4(필수) → 본문 *축 1(위치) + 누설 없음* 단정 확정. T5 → *축 2(자율 부재)* 확정.
2. R2 의 단정 수위는 T3 결과(대체 채널 부재 확인) + 저자 회사 관행으로 close.
3. 새 fact 는 raw(`03-Claude-vs-OpenCode/`)에 동기화 (카테고리 §0). 특히 *cross-compat 의 개인 채널* 은 raw 에 아직 전용 노트 없음 → 검증 후 seed 추가 권장.
4. R1·R3~R7 editorial 은 리뷰 대화에서 close.
5. **T7(필수, §3) → 본문 §3 를 *양방향 artifact* 로 재작성.** G(slug 동일성) 결과로 plugin 의 slug 도출을 확정하고, OC→CC plugin 발화·도착을 닫은 뒤 §3 + "한 눈에 비교"·"Take-home" 을 양방향 결론으로 갱신. (현재 본문 §3 는 clobber 버그 있는 단방향 — 재작성 전까지 보류.)
