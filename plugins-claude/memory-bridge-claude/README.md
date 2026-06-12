# 🧠 memory-bridge-claude

> **Claude Code → OpenCode** 개인 메모리 다리 — Claude Code 에게 "기억해줘" 한 것을, 같은 프로젝트의 OpenCode 도 그대로 기억합니다.

양방향을 원하면 짝꿍인 [memory-bridge-opencode](../../plugins-opencode/memory-bridge-opencode/) 를 함께 설치하세요 (OpenCode → Claude Code 방향).

---

## 📦 설치

개인 메모리이므로 user scope(`~/.claude`, 머신 전체)에 설치하지 않고, **작업하고자 하는 프로젝트 폴더** 혹은 그 하위 폴더(= Claude Code 를 열 바로 그 위치)에서 설치합니다.

그 폴더의 Claude Code 안에서:

```text
/plugin marketplace add Taekyo-Lee/harness-interop
/plugin install memory-bridge-claude@harness-interop
```

터미널 한 줄 (clone 불필요, 대화형 UI):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-claude/install.sh)
```

## 🚀 써보기

1. Claude Code 에서: *"Kim's favorite movie 는 Rashomon 이야, 기억해줘"*
2. 같은 프로젝트에서 OpenCode 를 열고: *"Kim's favorite movie 알아?"*
3. **"Rashomon"** 이라고 답하면 성공입니다.

## 📋 요구사항

- Claude Code **v2.1.0+** (플러그인 번들 hook)
- Linux / macOS / WSL (hook 이 `bash` 스크립트 — native Windows 미지원)
- `jq` 권장 (stdin payload 파싱 — 없어도 동작)
