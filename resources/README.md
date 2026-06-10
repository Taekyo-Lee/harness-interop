# resources/

장차 플러그인으로 묶일 컴포넌트들의 수집 공간입니다. 여기 있는 것들은 **아직 marketplace 에 노출되지 않습니다** — skills 가 충분히 쌓여 번들이 필요해지면, [anthropics/skills](https://github.com/anthropics/skills) 패턴처럼 marketplace entry 가 이 폴더를 `source` 로 삼아 부분집합 번들을 구성할 예정입니다.

| 폴더 | 들어갈 것 |
|---|---|
| `skills/` | `<이름>/SKILL.md` 형태의 skill 디렉토리 |
| `hooks/` | 플러그인별 hook 선언 파일 (`<플러그인>.hooks.json`) |
| `scripts/` | hook 이 `${CLAUDE_PLUGIN_ROOT}/scripts/…` 로 참조하는 스크립트 |
