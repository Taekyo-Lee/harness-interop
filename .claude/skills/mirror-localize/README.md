# 🪞 mirror-localize

**미러(사내) clone 의 자기참조를 미러 자신의 주소로 재작성하는 "변환" skill** — 설치 명령·marketplace 안내·plugin.json `repository`·`verify-release.sh` 감시 패턴이 public 원본 대신 미러를 가리키게 합니다.

> 이 repo 를 사내 git 호스트의 미러로 운영할 때를 위한 maintainer 도구입니다. 플러그인 사용자라면 필요 없습니다.

## 🧭 왜

repo 를 사내 호스트로 미러하면 트리 안의 자기참조는 전부 public 원본(github.com / raw.githubusercontent.com)을 가리킨 채로 옵니다. 그대로 두면 동료의 설치가 *몰래 public 에서* 코드를 당겨오거나, 폐쇄망에선 그냥 실패합니다. 더 나쁜 건 **부분 회사화** — 핵심 파일만 바뀌고 설치 문서가 남는 상태. 그래서 이 skill 은 "잔재 게이트 통과"를 완료의 정의로 강제합니다: source 를 가리키는 줄이 허용 목록 밖에 하나라도 남으면 실패이고, 아무것도 commit 하지 않습니다.

## 🗂 구성

| 파일 | 역할 |
|---|---|
| `SKILL.md` | 얇은 래퍼 — "아래 한 줄을 실행하고 결과를 전달하라" |
| `localize.sh` | **실행부 전체** — 모든 바이트 조작이 여기 (tracked, git 으로 운반) |

skill 실행 = 이 한 줄입니다:

```bash
bash .claude/skills/mirror-localize/localize.sh
```

**왜 스크립트인가**: 일부 사내망 전송 구간은 모델 경유 tool 호출의 `<` 포함 문자열을 변형시키는 것이 실측됐습니다 (`<` 직후 토큰 이중화 — 재시도해도 동일). README 처럼 `<` 가 흔한 파일에선 모델이 즉석에서 만드는 edit 페이로드를 신뢰할 수 없으므로, 치환 로직을 tracked 스크립트에 박아 git 으로 운반하고 모델은 `<` 없는 명령 한 줄만 칩니다. 실패한다고 모델이 대상 파일을 손으로 패치하면 안 됩니다 — 그 손패치가 바로 부패가 망가뜨리는 경로입니다.

## ⚙️ localize.sh 가 하는 일 (순서대로)

1. **게이트** — `.env` 의 `A2G_LOCATION` ∈ {`COMPANY`, `CORP`, `PRODUCTION`} 아니면 중단 (HOME/DEVELOPMENT 는 public 원본을 들고 있어 회사화하면 오염)
2. **identity** — MIRROR = `git remote get-url origin`, SOURCE = `upstream` remote 또는 `.env` 의 `REMOTE_REPO`. 손타이핑 금지; 이 clone 이 곧 source 면 중단
3. **probe** — 미러 raw URL 3형식을 익명 curl 로 시도 (enterprise 인스턴스는 익명 접근을 404 로 위장하는 경우가 많음). 전부 막혀 있으면 설치 명령을 clone 형태로 전환 — 이때 clone 은 **`/tmp` 임시 폴더로** 합니다. 설치 명령은 "플러그인을 쓸 프로젝트 폴더"에서 실행되므로, 그 자리에 clone 하면 프로젝트마다 repo 가 증식하기 때문입니다
4. **sweep** (멱등) — README 카탈로그 행, install.sh 헤더 주석, `MARKETPLACE_REPO`, `RAW_BASE`, 배너 URL, plugin.json `repository`, `verify-release.sh` 의 raw URL 감시 패턴. 옛 형태의 회사화 잔재도 마이그레이션 키로 잡아 자동 교정
5. **미러 공지** — 루트 README 맨 위 한 줄 blockquote (`mirror-of:` 마커 = 멱등 가드; 이 줄만은 *의도적으로* public 원본을 가리키며 sweep 에서 보호됨)
6. **잔재 게이트** — source `OWNER/REPO` 의 `git grep`. 허용 잔재는 셋뿐: 미러 공지 · `.claude/skills/` (워크플로 문서가 source 를 정당하게 언급) · `.env.example` (`REMOTE_REPO=` 는 upstream 포인터라 회사화하면 자기 자신을 가리킴). 그 외 발견 시 exit 1
7. **commit → `bash verify-release.sh HEAD` → push** (`--no-push` 옵션으로 push 만 생략 가능 — 테스트용)

## 🚀 언제

- **첫 셋업**: 미러 push + `.env` 생성 직후 1회 — `/mirror-localize`
- **유지보수**: [`merge-upstream`](../merge-upstream/README.md) 의 post-merge 가 매 merge 후 자동 호출 — 따로 부를 일이 없습니다

멱등이라 언제 다시 돌려도 안전합니다 — 이미 회사화된 트리에선 no-op. upstream 이 README 의 설치 셀 문구를 바꾸면 `localize.sh` 안의 하드코딩 템플릿을 함께 갱신하세요 (의도된 하드코딩 — 치환 결과를 모델이 즉석 생성하지 않게 하기 위함).

---

짝꿍: [`merge-upstream`](../merge-upstream/README.md) — 짝꿍이 **운반**, 이 skill 이 **변환(회사화)** 을 맡습니다.
