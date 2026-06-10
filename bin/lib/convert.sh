#!/usr/bin/env bash
# bin/lib/convert.sh — rules 변환기
#   - cursor: .md → .mdc (frontmatter 래핑, pcfg 마커 포함)
#   - codex:  AGENTS.md 내 마커 블록 삽입/제거
#
# 의존: common.sh, state.sh

# ── cursor: .md → .mdc ────────────────────────────────────────────────────────
# 내부: .mdc 파일 내용 생성 (skip 판정·실제 쓰기에서 공통 사용)
_mdc_content() {
  local src="$1" name="$2"
  printf '%s\n' '---'
  printf '%s\n' "$(pcfg_marker_begin "$name")"
  printf 'description: auto-converted from dotfiles agents/rules/%s.md\n' "$name"
  printf '%s\n' '---'
  cat "$src"
}

# convert_to_mdc <src-md> <dest-mdc> <name>
convert_to_mdc() {
  local src="$1" dest="$2" name="$3"

  if [[ ! -f "$src" ]]; then
    log_warn "소스가 없습니다: ${src} — 건너뜁니다."
    return
  fi

  # 이미 동일한 내용이면 no-op
  if [[ -f "$dest" ]] && _mdc_content "$src" "$name" | diff -q - "$dest" >/dev/null 2>&1; then
    log_skip "변환(mdc): ${dest} (이미 최신 내용)"
    return
  fi

  if ! is_dry; then
    ensure_parent "$dest"
    local backup=""; backup="$(backup_if_exists "$dest")"
    _mdc_content "$src" "$name" > "$dest"
    state_record "rules" "cursor" "$name" "$dest" "convert" "$backup"
    log_ok "변환(mdc): ${dest}"
  else
    log_dry "변환(mdc): ${src} → ${dest}"
  fi
}

# ── cursor: .mdc 제거 ─────────────────────────────────────────────────────────
# remove_mdc <dest-mdc> <name> [--restore]
remove_mdc() {
  local dest="$1" name="$2" restore="${3:-}"

  if [[ ! -f "$dest" ]]; then
    log_skip "${dest} — 파일 없음, 건너뜁니다."
    return
  fi

  # 안전장치: pcfg 마커가 있을 때만 삭제
  if ! grep -q "$(pcfg_marker_begin "$name")" "$dest" 2>/dev/null; then
    log_warn "${dest} 에 pcfg 마커가 없습니다 — 건너뜁니다."
    return
  fi

  local backup; backup="$(state_backup_for "rules" "cursor" "$name" "$dest")"

  if ! is_dry; then
    rm "$dest"
    if [[ "$restore" == "--restore" && -n "$backup" && -e "$backup" ]]; then
      mv "$backup" "$dest"
      log_ok "제거(mdc) + 복원: ${dest}"
    else
      log_ok "제거(mdc): ${dest}"
    fi
    state_remove "rules" "cursor" "$name" "$dest"
  else
    log_dry "rm mdc: ${dest}"
  fi
}

# ── codex: AGENTS.md 마커 블록 삽입 ─────────────────────────────────────────
# 내부: 마커 블록(begin..end 포함) 생성 (skip 판정·실제 쓰기에서 공통 사용)
_agents_section_block() {
  local src="$1" begin="$2" end="$3"
  printf '%s\n' "$begin"
  cat "$src"
  printf '\n%s\n' "$end"
}

# merge_agents_section <agents-md> <src-md> <name>
merge_agents_section() {
  local agents_md="$1" src="$2" name="$3"
  local begin; begin="$(pcfg_marker_begin "$name")"
  local end;   end="$(pcfg_marker_end   "$name")"

  if [[ ! -f "$src" ]]; then
    log_warn "소스가 없습니다: ${src} — 건너뜁니다."
    return
  fi

  # 이미 동일한 섹션이 있으면 no-op
  if [[ -f "$agents_md" ]] && grep -qF "$begin" "$agents_md"; then
    local current expected
    current="$(awk -v b="$begin" -v e="$end" \
      '$0==b{cap=1} cap{print} $0==e{exit}' "$agents_md")"
    expected="$(_agents_section_block "$src" "$begin" "$end")"
    if [[ "$current" == "$expected" ]]; then
      log_skip "merge-section(codex AGENTS.md): ${name} (이미 최신 내용)"
      return
    fi
  fi

  if ! is_dry; then
    ensure_parent "$agents_md"
    # AGENTS.md 가 없으면 새로 생성
    [[ -f "$agents_md" ]] || touch "$agents_md"

    # 이미 해당 섹션이 있으면 먼저 제거 (재설치 멱등)
    _remove_agents_section_raw "$agents_md" "$name"

    # 블록 추가
    {
      printf '\n'
      _agents_section_block "$src" "$begin" "$end"
    } >> "$agents_md"

    state_record "rules" "codex" "$name" "$agents_md" "merge-section" ""
    log_ok "merge-section(codex AGENTS.md): ${name}"
  else
    log_dry "merge-section: ${name} → ${agents_md}"
  fi
}

# ── codex: AGENTS.md 마커 블록 제거 ─────────────────────────────────────────
# remove_agents_section <agents-md> <name>
remove_agents_section() {
  local agents_md="$1" name="$2"

  if [[ ! -f "$agents_md" ]]; then
    log_skip "${agents_md} — 파일 없음, 건너뜁니다."
    return
  fi

  if ! grep -qF "$(pcfg_marker_begin "$name")" "$agents_md"; then
    log_skip "${name} 섹션이 없습니다 — 건너뜁니다."
    return
  fi

  if ! is_dry; then
    _remove_agents_section_raw "$agents_md" "$name"
    state_remove "rules" "codex" "$name" "$agents_md"
    log_ok "remove-section(codex AGENTS.md): ${name}"
  else
    log_dry "remove-section: ${name} from ${agents_md}"
  fi
}

# 내부: 마커 블록을 실제로 제거 (awk 사용)
_remove_agents_section_raw() {
  local agents_md="$1" name="$2"
  local begin; begin="$(pcfg_marker_begin "$name")"
  local end;   end="$(pcfg_marker_end   "$name")"
  local tmp; tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip=1; next }
    $0 == e { skip=0; next }
    !skip   { print }
  ' "$agents_md" > "$tmp"
  mv "$tmp" "$agents_md"
}
