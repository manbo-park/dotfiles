#!/usr/bin/env bash
# send-context.sh — send-context 스킬의 터미널 조작 담당. 메시지 전송(SendMessage)은 스킬을 실행하는 Claude 가 한다.
#
#   focus <세션명>          : 떠 있는 claude 세션의 herdr 탭·tmux window 로 포커스를 옮긴다
#   open  <세션명> <파일>    : herdr 새 탭·tmux 새 window 에 `claude -n <세션명> "$(cat <파일>)"` 실행 명령을 전달한다 (cwd = 현재 디렉토리)
#
# 종료 코드: 0 성공 / 2 대상 세션 없음 / 3 herdr·tmux 밖이거나 pane 을 찾지 못함 / 1 사용법 오류
set -uo pipefail

die() { echo "$1" >&2; exit "${2:-1}"; }
# 작은따옴표 인용. printf %q 는 bash 3.2 에서 한글을 깨진 UTF-8 로 내보내므로 쓰지 않는다
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

[ $# -ge 2 ] || die "사용법: $0 focus <세션명> | open <세션명> <파일>"
cmd="$1" name="$2"

case "$cmd" in
  focus)
    # 세션명 → 살아 있는 claude 프로세스의 pid·sessionId 후보 전부 (같은 이름이 여럿일 수 있다)
    candidates="$(
      for f in ~/.claude/sessions/*.json; do
        jq -r --arg n "$name" 'select(.name == $n) | "\(.pid) \(.sessionId)"' "$f" 2>/dev/null
      done | while read -r p s; do
        ps -o comm= -p "$p" 2>/dev/null | grep -q 'claude$' && echo "$p $s"
      done
    )"
    [ -n "$candidates" ] || die "떠 있는 세션 「${name}」 을 찾지 못했습니다" 2

    # herdr·tmux 에서 pane 이 찾아지는 첫 후보로 포커스를 옮긴다
    while read -r pid sid; do
      if [ -n "${HERDR_ENV:-}" ] && command -v herdr >/dev/null; then
        pane="$(herdr agent list 2>/dev/null | jq -r --arg s "$sid" '.result.agents[] | select(.agent_session.value == $s) | .pane_id' | head -1)"
        [ -n "$pane" ] && herdr agent focus "$pane" >/dev/null 2>&1 && { echo "herdr pane ${pane} 로 포커스를 옮겼습니다"; exit 0; }
      fi
      if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null; then
        tty="$(ps -o tty= -p "$pid" | tr -d ' ')"
        pane="$(tmux list-panes -a -F '#{pane_tty} #{pane_id}' | awk -v t="/dev/$tty" '$1 == t { print $2; exit }')"
        [ -n "$pane" ] && tmux switch-client -t "$pane" && tmux select-window -t "$pane" && tmux select-pane -t "$pane" \
          && { echo "tmux pane ${pane} 로 포커스를 옮겼습니다"; exit 0; }
      fi
    done <<< "$candidates"
    die "세션 「${name}」 은 떠 있지만 현재 herdr·tmux 안의 pane 이 아닙니다 (Claude Desktop·다른 터미널 등)" 3
    ;;

  open)
    file="${3:-}"
    [ -f "${file}" ] || die "전달 파일이 없습니다: ${file}"
    # 본문은 새 셸이 $(cat) 으로 읽게 해서, 긴 텍스트·따옴표·줄바꿈이 키 입력 과정에서 깨지지 않게 한다
    run="claude -n $(q "$name") \"\$(cat $(q "$file"))\""

    if [ -n "${HERDR_ENV:-}" ] && command -v herdr >/dev/null; then
      # 현재 세션의 workspace 에 연다 (생략하면 사용자가 보고 있는 다른 workspace 에 생길 수 있다)
      read -r tab pane < <(herdr tab create ${HERDR_WORKSPACE_ID:+--workspace "$HERDR_WORKSPACE_ID"} --cwd "$PWD" --label "$name" --focus 2>/dev/null \
        | jq -r '"\(.result.tab.tab_id // "") \(.result.root_pane.pane_id // "")"')
      [ -n "${pane:-}" ] && herdr pane run "$pane" "$run" >/dev/null 2>&1 && { echo "herdr 새 탭 (pane ${pane}) 에 세션 「${name}」 실행 명령을 전달했습니다"; exit 0; }
      # 탭만 열리고 실행에 실패하면 빈 탭이 남지 않게 닫는다
      [ -n "${tab:-}" ] && herdr tab close "$tab" >/dev/null 2>&1
    fi
    # tmux 는 셸이 뜬 window 에 키 입력으로 보낸다 (new-window 에 명령을 주면 .zshrc 미적용·종료 시 window 가 닫힘)
    # 창 이름은 tmux format 으로 전개되므로(#() 는 명령 실행) # 를 ## 로 escape 한다
    if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null; then
      pane="$(tmux new-window -c "$PWD" -n "${name//\#/##}" -P -F '#{pane_id}' 2>/dev/null)"
      [ -n "$pane" ] && tmux send-keys -t "$pane" -l "$run" && tmux send-keys -t "$pane" Enter \
        && { echo "tmux 새 window (pane ${pane}) 에 세션 「${name}」 실행 명령을 전달했습니다"; exit 0; }
    fi
    echo "새 탭/window 를 열지 못했습니다 (herdr·tmux 밖이거나 실행 실패). 직접 실행하세요:" >&2
    echo "  cd $(q "$PWD") && $run" >&2
    exit 3
    ;;

  *) die "알 수 없는 명령: $cmd" ;;
esac
