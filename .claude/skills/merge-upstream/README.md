# 🔄 merge-upstream

**미러(사내) clone 이 public 원본의 변경을 받아오는 "운반" skill** — Claude Code 에서 `/merge-upstream` 한 마디로 fetch → merge → 재회사화 → 검증 → push 까지 한 번에.

> 이 repo 를 사내 git 호스트의 미러로 운영할 때를 위한 maintainer 도구입니다. 플러그인 사용자라면 필요 없습니다.

## 🧭 왜

미러 운영의 반복 작업은 "원본이 바뀔 때마다 옮기기"입니다. 손으로 하면 단계가 많고 — fetch, merge, 충돌 해소, *새로 들어온 내용의 재회사화*, 검증, push — 한 단계만 빠져도 "설치 문서가 조용히 public 을 가리키는 반쪽 미러"가 됩니다. 이 skill 은 그 전체를 한 호출로 묶고, 마지막 push 는 배포 계약 검증(`verify-release.sh`)이 `✓ RELEASE OK` 일 때만 일어납니다.

## 🗂 구성

| 파일 | 역할 |
|---|---|
| `SKILL.md` | 공용 절차 — 환경 게이트, remote 확인/등록, fetch·merge, 충돌 처리 원칙, 에러 대응 |
| `SKILL.local.md` | **이 repo 전용 규칙** — 충돌 Rule 0 + post-merge 액션 (아래). 공용 절차가 런타임에 로드하며, 충돌 시 이쪽이 우선 |

## 🔒 환경 게이트

`.env` 의 `A2G_LOCATION` 이 `COMPANY` / `CORP` / `PRODUCTION` 일 때만 동작합니다. 그 외(HOME/DEVELOPMENT)에서는 즉시 거부 — 그 머신들은 public 원본을 직접 push 하는 쪽이라 merge 방향 자체가 성립하지 않습니다. `.env` 는 gitignored 이므로 미러 clone 에서 직접 만듭니다:

```bash
A2G_LOCATION=COMPANY
REMOTE_REPO=https://github.com/Taekyo-Lee/harness-interop.git
```

(`REMOTE_REPO` 는 `upstream` remote 가 아직 없을 때의 fallback — skill 이 영구 등록할지 1회만 쓸지 물어봅니다.)

## ⚙️ 동작 (한 호출 안에서)

1. 게이트 + `SKILL.local.md` 로드 + origin/upstream remote 확인
2. clean tree·main 브랜치 확인 (dirty 면 중단 — 먼저 commit/stash)
3. `git fetch upstream` → `git merge upstream/main`
   - fetch 실패 시 credential 진단보다 먼저 "원본이 일시 private 인지"를 확인합니다 (증상이 동일하게 보임)
4. 충돌 시 **Rule 0**: 자기참조(설치 URL·`MARKETPLACE_REPO`·`RAW_BASE`·plugin.json `repository` 등) 충돌은 **upstream 통째 수용** — 다음 단계 sweep 이 결정론적으로 재회사화하므로, 손merge 는 drift 만 만듭니다
5. post-merge: [`mirror-localize`](../mirror-localize/README.md) 실행 — merge 가 새로 들여온 파일/줄은 충돌 0건으로 *미회사화 상태로* 합류하므로, 멱등 sweep 이 매번 받아냅니다
6. `bash verify-release.sh HEAD` = `✓ RELEASE OK` 필수
7. 그 후에만 `git push origin main`

## 🚀 사용

미러 clone 의 Claude Code 에서:

```text
/merge-upstream
```

이게 전부입니다. tree 가 dirty 해서 멈추면 변경분을 commit 하고 다시 호출하세요.

---

짝꿍: [`mirror-localize`](../mirror-localize/README.md) — 이 skill 이 **운반**, 짝꿍이 **변환(회사화)** 을 맡습니다.
