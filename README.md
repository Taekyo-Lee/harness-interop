<div align="center">

# 🌉 Harness Interop

**AI 코딩 harness 사이의 상호운용(interoperability) 플러그인 monorepo**

도구는 바꿔도, 맥락은 끊기지 않게.<br>
어느 harness 를 열든 — 당신의 메모리 · 지침 · 설정은 **이미 거기 있습니다.**

| Claude Code | OpenCode | Codex | Gemini CLI |
|:---:|:---:|:---:|:---:|
| ✅ 지원 | ✅ 지원 | 🔜 예정 | 🔜 예정 |

</div>

---

## 🧭 왜

요즘 우리는 harness 를 하나만 쓰지 않습니다 — 작업에 따라, 모델에 따라 갈아탑니다. 문제는 갈아타는 순간 **개인 맥락이 함께 넘어가지 않는다**는 것. 이 프로젝트에서 기억시킨 사실들, 나만의 지침이 이전 harness 에 남겨집니다.

원인은 구조적입니다. harness 마다 개인 맥락을 담는 그릇이 다르거든요 — Claude Code 는 repo *바깥*에 모델이 스스로 쌓는 memory 시스템, OpenCode 는 repo *안* 파일을 `instructions` 로 등록하는 방식. 그릇이 다르니 한 파일로 합칠 수 없습니다.

그래서 이 repo 의 플러그인들은 합치는 대신 **각자의 그릇에 두고, 내용만 자동으로 건너가게** 합니다 — 당신이 다음 harness 를 열기 전에, 이미.

> 📚 배경과 설계 의도: 블로그 *「Claude Code 와 OpenCode 를 함께 쓸 때, 팀과 공유하지 않는 개인 지침 배치」* (claude-code-vs-opencode 시리즈)

## 🔌 플러그인 카탈로그

| 카테고리 | 플러그인 | Target harness | ⚡ 설치 |
|:---:|:---:|:---:|:---|
| 🧠 **개인 메모리 공유** | [`memory-bridge-claude`](plugins-claude/memory-bridge-claude/README.md) | Claude Code | `curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-claude/install.sh \| bash` **(추천 · 한방 설치)**<br>`bash <(curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-claude/install.sh)` (대화형 선택) |
| 🧠 **개인 메모리 공유** | [`memory-bridge-opencode`](plugins-opencode/memory-bridge-opencode/README.md) | OpenCode | `curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-opencode/install.sh \| bash` **(추천 · 한방 설치)**<br>`bash <(curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-opencode/install.sh)` (대화형 선택) |

## 🗂 레이아웃

```
harness-interop/
├── .claude-plugin/marketplace.json   # 이 repo 를 Claude Code marketplace 로
├── plugins-claude/                   # Claude Code 용 플러그인 모음
│   ├── install.sh                    #   설치 스크립트 (대화형)
│   └── memory-bridge-claude/         #   → 상세는 폴더 안 README
├── plugins-opencode/                 # OpenCode 용 플러그인 모음
│   ├── install.sh                    #   설치 스크립트 (대화형)
│   └── memory-bridge-opencode/       #   → 상세는 폴더 안 README
├── resources/                        # 컴포넌트 수집 공간 (추후 번들 예정)
└── verify-release.sh                 # 배포 계약 검증 (maintainer 용 — 검사 목록은 트리에서 유도)
```

💻 **공통 요구사항:** Linux / macOS / WSL (native Windows 미지원 — 셸 스크립트 기반)

