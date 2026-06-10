# [ARCHIVED] §3 상세본 — hook 으로 양방향 자동 동기화

> 2026-06-09 에 index.mdx §3 에서 떼어내 보관한 **상세본 전문**입니다.
>
> **왜 뺐나**: §3 은 독자가 §1·§2 를 읽고 *아이디어만 캐치하고 끄덕이는* 짧은 teaser 로 줄였습니다. 넷으로 나눈 파일 배치, hook 코드 2종(셸 스크립트 / OpenCode plugin), 검증 콜아웃 같은 *실제로 굴러가게 만드는 디테일*은 블로그가 아니라 별도 repo `multi-harness-plugins` (배포용 plugin) 가 본거지가 됩니다.
>
> **상태**: 이 프로즈는 draft 단계였고 동작이 저자 검증 전이었습니다 (verification.md 의 T7 / slug 동일성 게이트). 그대로 다시 본문에 붙이지 말고, plugin repo 가이드의 **원재료**로 쓰세요.
>
> **관련 문서**: 같은 폴더의 `hook-sync-research.md` (소스 grounded 조사), `verification.md` (검증 시나리오), `00-progress-and-plan.md` (진행/계획).
>
> 아래는 떼어낸 시점의 index.mdx 본문 그대로입니다 (line 314–484).

---

## 3. (Tip) hook 으로 project-scoped 개인 지침 양방향 자동 동기화

ANCHOR 1 의 결론은 *각자 두고 내용만 옮긴다* 였어요. 두 harness 의 저장 위치가 다르니 파일을 하나로 합치지 말고, 노트의 *내용* 만 한쪽에서 다른 쪽으로 베껴 두자는 거였죠. 그런데 이 베끼기를 손으로 하면 금세 밀려요. Claude Code 쪽 memory 는 [*MEMORY.md*](../sharing-memory-md/) 에서 봤듯 작업 중에 *저절로* 쌓이고, OpenCode 쪽 노트는 앞에서 본 <span class="k">.opencode/personal.md</span> 에 제가 직접 적어 두거든요. 양쪽 다 늘어날 때마다 반대편에 다시 옮겨 줘야 합니다.

이번 장은 그 옮기기를 *양방향으로* 자동화하는 이야기예요. 이 글의 하이라이트이자, 제가 실제로 만들어 쓰는 작은 artifact 이기도 해요. 한쪽이 아니라 양쪽에 hook 을 하나씩 걸어서, Claude Code 에 쌓인 memory 는 OpenCode 로, OpenCode 에 적어 둔 노트는 Claude Code 로, 손대지 않아도 서로 흘러가게 만듭니다.

### 두 다리는 생김새가 달라요

방향이 둘이니 다리도 둘인데, 두 harness 가 확장되는 방식이 서로 달라서 다리의 생김새도 달라요.

<div class="pair-grid">
  <div class="pair-card claudecode">
    <span class="pair-title">Claude Code → OpenCode</span>
    <p class="pc-line">세션이 끝날 때 도는 셸 hook</p>
    <p class="pc-line"><span class="pc-path">.claude/settings.local.json</span> 에 등록 <span class="pc-tag auto">자동</span></p>
  </div>
  <div class="pair-card opencode">
    <span class="pair-title">OpenCode → Claude Code</span>
    <p class="pc-line">한 턴이 끝날 때 도는 작은 plugin</p>
    <p class="pc-line"><span class="pc-path">.opencode/plugin/</span> 에 두면 로드 <span class="pc-tag auto">자동</span></p>
  </div>
</div>

발화 시점도 자연스럽게 달라져요. Claude Code 엔 *세션이 끝날 때 한 번* 도는 hook(<span class="k">SessionEnd</span>)이 있어서, 끝나는 순간 최신 memory 를 한 번 내보내면 됩니다. OpenCode 엔 그 "세션 종료 한 번" 에 꼭 맞는 hook 이 없어서, 대신 *모델이 한 턴을 끝내고 멈출 때*(idle)마다 도는 신호에 걸어요. plugin 이 하는 일이 파일 한 장 복사라 가볍고, 여러 번 돌아도 결과가 같아서 턴마다 돌아도 괜찮습니다.

### 먼저, 서로 덮어쓰지 않게

양방향에서 제일 조심할 건 두 다리가 서로의 입력을 지워 버리는 거예요. 순진하게 짜면 이렇게 됩니다. Claude Code hook 이 "OpenCode 가 읽는 파일" 을 통째로 덮어쓰고, OpenCode plugin 도 "Claude Code 가 읽는 파일" 을 통째로 덮어써요. 한 방향만 켤 땐 괜찮지만, 둘 다 켜는 순간 매번 서로가 적어 둔 걸 지웁니다.

규칙 하나로 풀려요. *각 harness 는 자기 출처 파일에만 쓰고, 상대에게서 건너온 내용은 따로 받는다.* 그래서 파일을 넷으로 나눠요.

<table class="compare-table">
  <thead>
    <tr><th>파일</th><th>쓰는 쪽</th><th>읽는 쪽</th><th>역할</th></tr>
  </thead>
  <tbody>
    <tr>
      <td><span class="k">memory/</span> 의 노트들</td>
      <td>Claude Code (자동)</td>
      <td>Claude Code</td>
      <td>Claude Code 자기 출처</td>
    </tr>
    <tr>
      <td><span class="k">.opencode/personal.md</span></td>
      <td>내가 OpenCode 에서 적음</td>
      <td>OpenCode</td>
      <td>OpenCode 자기 출처</td>
    </tr>
    <tr class="row-accent">
      <td><span class="k">.opencode/from-claude.md</span></td>
      <td>Claude Code hook</td>
      <td>OpenCode</td>
      <td>Claude Code → OpenCode 도착함</td>
    </tr>
    <tr class="row-accent">
      <td><span class="k">memory/from-opencode.md</span></td>
      <td>OpenCode plugin</td>
      <td>Claude Code</td>
      <td>OpenCode → Claude Code 도착함</td>
    </tr>
  </tbody>
</table>

읽는 쪽은 손댈 게 없어요. Claude Code 는 자기 memory 폴더를 통째로 읽으니, OpenCode 가 거기 떨어뜨린 <span class="k">from-opencode.md</span> 도 그냥 memory 노트 하나로 따라 읽혀요. OpenCode 는 <span class="k">opencode.json</span> 의 instructions 로 자기 <span class="k">personal.md</span> 와 건너온 <span class="k">from-claude.md</span> 를 같이 붙여 읽고요.

남은 건 *에코 차단* 하나예요. 내보낼 때는 상대에게서 받은 파일을 빼고 보냅니다. Claude Code hook 은 memory 를 모을 때 <span class="k">from-opencode.md</span> 를 건너뛰고, OpenCode plugin 은 자기 <span class="k">personal.md</span> 만 보내요. 안 그러면 같은 노트가 양쪽을 끝없이 왕복합니다.

### 다리 1. Claude Code → OpenCode

세션이 끝나는 순간 이 프로젝트의 Claude Code memory 를 한데 모아, OpenCode 가 읽는 파일(<span class="k">.opencode/from-claude.md</span>)로 흘려보냅니다. 쓸 hook 은 <span class="k">SessionEnd</span>, 둘 곳은 <span class="k">.claude/settings.local.json</span> 이에요. Claude Code 의 project 설정 중 *git 에 올라가지 않는 개인 레이어* 죠. 개인 노트를 git 바깥에 두려고 여기까지 왔으니, 그걸 나르는 hook 도 같은 *나만의 git-untracked 공간* 에 둡니다.

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/sync-memory.sh\"" }
        ]
      }
    ]
  }
}
```

<details class="fold">
<summary><span>📜 hook 이 부르는 스크립트 (<span class="k">.claude/sync-memory.sh</span>)</span></summary>

<div class="fold-body">
<p>Claude Code 가 이 프로젝트 memory 를 모아 두는 폴더를 찾아, 그 안의 노트들을 하나로 이어 <span class="k">.opencode/from-claude.md</span> 에 씁니다. 세션이 끝날 때마다 <em>덮어써서</em> 늘 최신 memory 와 똑같이 맞춰요. 단 OpenCode 에서 건너온 <span class="k">from-opencode.md</span> 는 모을 때 건너뜁니다. 그게 도로 OpenCode 로 돌아가면 같은 노트가 끝없이 왕복하니까요.</p>

```bash
#!/usr/bin/env bash
# Claude Code 의 이 프로젝트 memory 를 OpenCode 가 읽는 파일로 모은다.

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
slug="$(printf '%s' "$proj" | tr -c '[:alnum:]' '-')"
mem="$HOME/.claude/projects/$slug/memory"
out="$proj/.opencode/from-claude.md"

[ -d "$mem" ] || exit 0          # 아직 memory 가 없으면 조용히 종료

mkdir -p "$(dirname "$out")"
{
  echo "<!-- Claude Code SessionEnd hook 이 자동 생성. 직접 수정하지 마세요. -->"
  echo
  for f in "$mem"/*.md; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "from-opencode.md" ] && continue   # OpenCode 에서 건너온 노트는 도로 안 보냄
    cat "$f"; echo
  done
} > "$out"
```

<p>memory 폴더 위치는 프로젝트 경로에서 정해져요. 위 스크립트는 프로젝트 경로의 영문·숫자가 아닌 글자를 <span class="k">-</span> 로 바꾼 이름을 써서 <span class="k">&#126;/.claude/projects/&lt;그-이름&gt;/memory/</span> 를 가리킵니다.</p>
</div>
</details>

그리고 OpenCode 가 이 파일을 함께 읽도록 instructions 에 한 줄 더해요. 앞에서 <span class="k">personal.md</span> 를 등록했던 그 자리예요.

```json
{
  "instructions": [".opencode/personal.md", ".opencode/from-claude.md"]
}
```

### 다리 2. OpenCode → Claude Code

반대 방향이에요. OpenCode 에 적어 둔 개인 노트(<span class="k">.opencode/personal.md</span>)를 Claude Code 가 읽는 memory 폴더로 보냅니다. OpenCode 는 셸 hook 대신 작은 plugin 으로 확장하니, <span class="k">.opencode/plugin/</span> 아래에 파일 하나를 두면 OpenCode 가 켜질 때 알아서 불러요. 이 plugin 은 모델이 한 턴을 끝낼 때(idle)마다 personal.md 를 Claude Code 의 이 프로젝트 memory 폴더 안 <span class="k">from-opencode.md</span> 로 복사합니다.

<details class="fold">
<summary><span>📜 OpenCode plugin (<span class="k">.opencode/plugin/sync-to-claude.ts</span>)</span></summary>

<div class="fold-body">
<p>한 턴이 끝나 idle 신호가 올 때마다, OpenCode 의 개인 노트를 Claude Code memory 폴더의 <span class="k">from-opencode.md</span> 로 복사합니다. 보내는 건 자기 <span class="k">personal.md</span> 하나뿐이에요. Claude Code 에서 건너온 <span class="k">from-claude.md</span> 는 건드리지 않아서, 이쪽도 에코가 안 생깁니다.</p>

```ts
import type { Plugin } from "@opencode-ai/plugin"
import { homedir } from "node:os"
import { join, dirname } from "node:path"
import { mkdir, copyFile, access } from "node:fs/promises"

export const SyncToClaude: Plugin = async ({ directory }) => {
  return {
    event: async ({ event }) => {
      // 버전에 따라 "session.status" 로 오고 status.type === "idle" 일 수 있어요.
      if (event.type !== "session.idle") return

      const slug = directory.replace(/[^A-Za-z0-9]/g, "-")
      const src = join(directory, ".opencode", "personal.md")
      const out = join(homedir(), ".claude", "projects", slug, "memory", "from-opencode.md")

      try { await access(src) } catch { return }   // 아직 개인 노트가 없으면 조용히 종료
      await mkdir(dirname(out), { recursive: true })
      await copyFile(src, out)
    },
  }
}
```

<p>slug 를 만드는 규칙(영문·숫자가 아닌 글자를 <span class="k">-</span> 로 바꾸기)은 다리 1 의 셸 스크립트와 똑같아요. 그래야 양쪽이 <em>같은</em> memory 폴더를 가리킵니다.</p>
</div>
</details>

Claude Code 는 다음 세션에 memory 폴더를 읽을 때 이 <span class="k">from-opencode.md</span> 도 노트 하나로 함께 실어요. memory 노트가 세션 시작에 자동으로 따라 읽히는, 앞서 [*MEMORY.md*](../sharing-memory-md/) 에서 본 그 길을 그대로 탑니다.

<div class="callout">
발화 시점과 memory 폴더의 정확한 경로는 환경마다 조금씩 달라요. 그대로 쓰기 전에 세 가지를 직접 확인하세요. (1) 두 harness 가 *같은 프로젝트를 같은 이름으로* 가리키는지. 다리 1 이 쓰는 폴더 이름과 다리 2 가 만드는 slug 가 일치해야 해요. 경로 중간에 symlink 가 끼면 한쪽만 풀어 이름이 어긋날 수 있어요. (2) OpenCode 의 idle 신호 이름은 버전에 따라 <span class="k">session.idle</span> 이거나 <span class="k">session.status</span> 예요. plugin 이 실제로 받는지 보세요. (3) 세션을 한 번씩 돌린 뒤 <span class="k">.opencode/from-claude.md</span> 와 <span class="k">from-opencode.md</span> 가 각각 갱신되는지 눈으로 확인하세요.
</div>

이렇게 양쪽에 다리를 하나씩 놓으면, 개인 지침은 Claude Code 와 OpenCode 어느 쪽에서 늘려도 다음 세션엔 반대편에도 가 있어요. 파일은 ANCHOR 1 대로 *각자* 두고 오가는 건 *내용* 뿐이라, 팀 repo 엔 한 글자도 새지 않습니다.
