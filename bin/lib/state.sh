#!/usr/bin/env bash
# bin/lib/state.sh — 설치 상태 lockfile + rename 원장 관리
#
# lockfile: ~/.local/state/dotfiles/state.tsv
# 컬럼: type  agent  name  dest  mechanism  backup  ts

STATE_FILE="${HOME}/.local/state/dotfiles/state.tsv"
RENAMES_FILE="${REPO_ROOT}/renames.tsv"

# ── lockfile 초기화 ───────────────────────────────────────────────────────────
state_init() {
  local dir; dir="$(dirname "$STATE_FILE")"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  if [[ ! -f "$STATE_FILE" ]]; then
    printf '# type\tagent\tname\tdest\tmechanism\tbackup\tts\n' > "$STATE_FILE"
  fi
}

# ── 항목 기록 ─────────────────────────────────────────────────────────────────
# state_record <type> <agent> <name> <dest> <mechanism> [backup]
state_record() {
  local type="$1" agent="$2" name="$3" dest="$4" mechanism="$5" backup="${6:-}"
  state_init
  # 기존 동일 항목 제거 후 재기록 (멱등)
  state_remove "$type" "$agent" "$name" "$dest" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$type" "$agent" "$name" "$dest" "$mechanism" "$backup" "$(timestamp)" \
    >> "$STATE_FILE"
}

# ── 항목 제거 ─────────────────────────────────────────────────────────────────
# state_remove <type> <agent> <name> <dest>
state_remove() {
  local type="$1" agent="$2" name="$3" dest="$4"
  [[ -f "$STATE_FILE" ]] || return 0
  # dest 컬럼(4번)까지 일치하는 줄 제거
  local tmp; tmp="$(mktemp)"
  grep -v "^${type}	${agent}	${name}	${dest}	" "$STATE_FILE" > "$tmp" || true
  mv "$tmp" "$STATE_FILE"
}

# ── 항목 조회 ─────────────────────────────────────────────────────────────────
# state_query [type] [agent] [name]  → 일치하는 줄 목록
# 빈 인자는 와일드카드로 처리
state_query() {
  local type="${1:-}" agent="${2:-}" name="${3:-}"
  [[ -f "$STATE_FILE" ]] || return 0

  while IFS=$'\t' read -r t a n d m b ts; do
    [[ "$t" =~ ^# ]] && continue
    [[ -n "$type"  && "$t" != "$type"  ]] && continue
    [[ -n "$agent" && "$a" != "$agent" ]] && continue
    [[ -n "$name"  && "$n" != "$name"  ]] && continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$t" "$a" "$n" "$d" "$m" "$b" "$ts"
  done < "$STATE_FILE"
}

# ── 백업 경로 조회 ────────────────────────────────────────────────────────────
# state_backup_for <type> <agent> <name> <dest>  → backup 경로 (없으면 빈 문자열)
state_backup_for() {
  local type="$1" agent="$2" name="$3" dest="$4"
  [[ -f "$STATE_FILE" ]] || { echo ""; return; }
  while IFS=$'\t' read -r t a n d m b ts; do
    [[ "$t" =~ ^# ]] && continue
    if [[ "$t" == "$type" && "$a" == "$agent" && "$n" == "$name" && "$d" == "$dest" ]]; then
      echo "$b"
      return
    fi
  done < "$STATE_FILE"
  echo ""
}

# ── 전체 lockfile 출력 ────────────────────────────────────────────────────────
state_list() {
  [[ -f "$STATE_FILE" ]] || { log_warn "상태 파일이 없습니다."; return; }
  cat "$STATE_FILE"
}

# ── rename 원장 기록 ──────────────────────────────────────────────────────────
# renames_record <type> <old> <new> [note]
renames_record() {
  local type="$1" old="$2" new="$3" note="${4:-}"
  local today; today="$(date +%Y-%m-%d)"
  printf '%s\t%s\t%s\t%s\t%s\n' "$type" "$old" "$new" "$today" "$note" \
    >> "$RENAMES_FILE"
}

# ── rename 원장 조회 ─────────────────────────────────────────────────────────
# renames_query [type]  → type  old  new  date  note 줄 목록
renames_query() {
  local filter_type="${1:-}"
  [[ -f "$RENAMES_FILE" ]] || return 0
  while IFS=$'\t' read -r t o n d note; do
    [[ "$t" =~ ^# || -z "$t" ]] && continue
    [[ -n "$filter_type" && "$t" != "$filter_type" ]] && continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$t" "$o" "$n" "$d" "$note"
  done < "$RENAMES_FILE"
}
