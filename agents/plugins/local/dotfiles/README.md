# dotfiles 플러그인

dotfiles에서 관리하는 자작 Claude Code 스킬·훅 모음 (로컬 마켓플레이스 `dotfiles-local`).

- `/retitle`: 대화를 한국어로 요약해 세션 이름을 바꾼다. 플랜·구현 단계면 `[plan] 요약`·`[impl] 요약`.
- `/send-context <설명> [-t 세션명] [-n [세션명]]`: 이 세션의 맥락 일부를 다른 세션에 전달한다.
- `/independent-review [대상] [관점]`: 결과물을 컨텍스트 없는 서브에이전트에게 읽기 전용으로 리뷰시키고, 지적마다 동의·반박을 붙여 보고한다.
- `/pr-description`: 브랜치의 커밋·diff·이슈 티켓을 근거로 PR description을 작성한다.
- `/proofread-ai-slop`: 완성된 문서(.md/.html)의 AI 티를 검출하고 교정한다.

## 설치

```bash
pcfg install plugins dotfiles
```

설치 후 Claude Code를 재시작한다. 플러그인은 저장소 원본에서 읽히므로 고친 뒤에도 재시작하면 된다. 반영되지 않으면 `/plugin marketplace update dotfiles-local` 후 `/plugin update dotfiles@dotfiles-local`.

## 요구 사항

- Claude Code 2.1.332 이상 (hook의 `sessionTitle` 출력)
- `python3`, `jq`
- retitle: hook 안에서 `claude -p --model haiku`를 호출하므로 Claude Code가 로그인되어 있어야 한다.
- send-context: 탭 포커스·새 탭 열기는 herdr 또는 tmux 안에서만 동작한다. 그 밖에서는 메시지 전달만 하고 실행 명령을 안내한다.
