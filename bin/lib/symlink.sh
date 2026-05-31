#!/usr/bin/env bash
# bin/lib/symlink.sh — symlink 설치/제거 (백업·복원 포함)
#
# 의존: common.sh, state.sh (REPO_ROOT, timestamp, backup_if_exists, ensure_parent,
#        is_dry, run_or_dry, log_*, state_record, state_remove, state_backup_for)

# ── symlink 설치 ──────────────────────────────────────────────────────────────
# symlink_install <type> <agent> <name> <src> <dest>
# src: 절대 경로 (파일 또는 디렉토리)
# dest: 절대 경로
symlink_install() {
  local type="$1" agent="$2" name="$3" src="$4" dest="$5"

  if [[ ! -e "$src" ]]; then
    log_warn "소스가 없습니다: ${src} — 건너뜁니다."
    return
  fi

  # 이미 올바른 symlink면 no-op
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    log_skip "${dest} → (이미 올바른 symlink)"
    return
  fi

  local backup=""
  if ! is_dry; then
    ensure_parent "$dest"
    backup="$(backup_if_exists "$dest")"
    ln -s "$src" "$dest"
    state_record "$type" "$agent" "$name" "$dest" "symlink" "$backup"
    if [[ -n "$backup" ]]; then
      log_ok "symlink: ${dest} → ${src}  (기존 백업: ${backup})"
    else
      log_ok "symlink: ${dest} → ${src}"
    fi
  else
    log_dry "symlink: ${dest} → ${src}"
    if [[ -e "$dest" || -L "$dest" ]]; then log_dry "  (기존 파일 백업 예정)"; fi
  fi
}

# ── symlink 제거 ──────────────────────────────────────────────────────────────
# symlink_uninstall <type> <agent> <name> <dest> [--restore]
symlink_uninstall() {
  local type="$1" agent="$2" name="$3" dest="$4" restore="${5:-}"

  if [[ ! -L "$dest" ]]; then
    log_skip "${dest} — symlink 없음, 건너뜁니다."
    state_remove "$type" "$agent" "$name" "$dest" 2>/dev/null || true
    return
  fi

  # 안전장치: 이 repo 를 가리키는 symlink만 삭제
  local target; target="$(readlink "$dest")"
  if [[ "$target" != "${REPO_ROOT}"* ]]; then
    log_warn "${dest} 가 이 repo 를 가리키지 않습니다 (${target}) — 건너뜁니다."
    return
  fi

  local backup; backup="$(state_backup_for "$type" "$agent" "$name" "$dest")"

  if ! is_dry; then
    run_or_dry rm "$dest"
    if [[ "$restore" == "--restore" && -n "$backup" && -e "$backup" ]]; then
      run_or_dry mv "$backup" "$dest"
      log_ok "제거 + 복원: ${dest}  (백업에서 복원: ${backup})"
    else
      log_ok "제거: ${dest}"
    fi
    state_remove "$type" "$agent" "$name" "$dest"
  else
    log_dry "rm symlink: ${dest}"
    if [[ "$restore" == "--restore" && -n "$backup" ]]; then
      log_dry "  복원 예정: ${backup} → ${dest}"
    fi
  fi
}
