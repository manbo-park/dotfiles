# dotfiles 플러그인

dotfiles에서 관리하는 자작 Claude Code 스킬·훅 모음 (로컬 마켓플레이스 `dotfiles-local`).

- `/retitle`: 대화를 한국어로 요약해 세션 이름을 바꾼다. 플랜·구현 단계면 `[plan] 요약`·`[impl] 요약`.
- `/send-context <설명> [-t 세션명] [-n [세션명]]`: 이 세션의 맥락 일부를 다른 세션에 전달한다.

## 설치

```bash
pcfg install plugins dotfiles
```

설치 후 Claude Code를 재시작한다. 원본을 고친 뒤에는 `/plugin marketplace update dotfiles-local` 후 `/plugin update dotfiles@dotfiles-local`.

## 요구 사항

- Claude Code 2.1.332 이상 (hook의 `sessionTitle` 출력)
- `python3`, `jq`
- retitle: hook 안에서 `claude -p --model haiku`를 호출하므로 Claude Code가 로그인되어 있어야 한다.
- send-context: 탭 포커스·새 탭 열기는 herdr 또는 tmux 안에서만 동작한다. 그 밖에서는 메시지 전달만 하고 실행 명령을 안내한다.
