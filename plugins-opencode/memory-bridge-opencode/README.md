# 🧠 memory-bridge-opencode

> **OpenCode → Claude Code** 개인 메모리 다리 — OpenCode 에게 "기억해줘" 한 것을, 같은 프로젝트의 Claude Code 도 그대로 기억합니다.

양방향을 원하면 짝꿍인 [memory-bridge-claude](../../plugins-claude/memory-bridge-claude/) 를 함께 설치하세요 (Claude Code → OpenCode 방향).

---

## 📦 설치

개인 메모리이므로 머신 전체(global, `~/.config/opencode/`)에 설치하지 않고, **작업하고자 하는 프로젝트 폴더** 혹은 그 하위 폴더(= OpenCode 를 열 바로 그 위치)에서 설치합니다.

그 폴더에서 한 줄 (clone 불필요, 대화형 UI):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Taekyo-Lee/harness-interop/main/plugins-opencode/install.sh)
```

## 🚀 써보기

1. OpenCode 에서: *"Henry 별명은 IRON MAN, 기억해줘"*
2. 같은 프로젝트에서 Claude Code 를 열고: *"Henry 별명 알아?"*
3. **"IRON MAN"** 이라고 답하면 성공입니다.

## 📋 요구사항

- OpenCode (로컬 `.ts` 플러그인 자동 발견 지원 버전)
- Linux / macOS / WSL
