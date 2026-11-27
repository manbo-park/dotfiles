#!/usr/bin/env bash
# bin/lib/merge.sh — settings 파일에 JSON 조각(jq) merge·remove
#
# 의존: common.sh, state.sh (require_cmd, backup_if_exists, is_dry,
#        run_or_dry, log_*, state_record, state_remove, timestamp)

# ── 내부: top-key 유무에 따른 jq 경로 ────────────────────────────────────────
# $top 이 빈 문자열이면 [$key], 아니면 [$top, $key] 를 $p 로 바인딩한다.
_JQ_PATH_EXPR='(if $top == "" then [$key] else [$top, $key] end) as $p'

# ── JSON merge ────────────────────────────────────────────────────────────────
# json_merge <settings-json> <top-key> <name> <fragment-json>
#   settings-json: ~/.claude/settings.json 등
#   top-key: "mcpServers" | "" (빈 값이면 최상위 키에 직접 merge)
#   name: 아이템 이름 (키 식별자)
#   fragment-json: 아이템 정의 JSON 파일 경로 또는 inline JSON 문자열
json_merge() {
  local settings="$1" top_key="$2" name="$3" fragment="$4"
  require_cmd jq

  # fragment가 파일이면 읽고, 아니면 문자열 그대로
  local payload
  if [[ -f "$fragment" ]]; then
    payload="$(cat "$fragment")"
  else
    payload="$fragment"
  fi

  # 이미 동일한 값이면 no-op
  if [[ -f "$settings" ]]; then
    local same
    same="$(jq --argjson val "$payload" --arg key "$name" --arg top "$top_key" \
      "$_JQ_PATH_EXPR"' | if (getpath($p)) == $val then "yes" else "no" end' "$settings" 2>/dev/null || echo no)"
    if [[ "$same" == '"yes"' ]]; then
      log_skip "json-merge [${top_key}.${name}]: ${settings} (이미 최신 내용)"
      return
    fi
  fi

  if ! is_dry; then
    ensure_parent "$settings"
    # 파일이 없으면 빈 객체로 초기화
    [[ -f "$settings" ]] || echo '{}' > "$settings"

    local backup; backup="$(backup_if_exists "$settings")"
    # settings 자체를 일단 백업 복사로 이전, merge 결과를 원본 위치에 씀
    if [[ -n "$backup" ]]; then
      # backup_if_exists 가 이미 이동시킴 → backup에서 읽어야 함
      local src="$backup"
    else
      local src="$settings"
      local tmp_bak; tmp_bak="${settings}.pcfg-bak.$(timestamp)"
      cp "$settings" "$tmp_bak"
      src="$tmp_bak"
      backup="$tmp_bak"
    fi

    # jq: .<top_key>.<name> = <payload> (top_key 가 비면 .<name> = <payload>)
    jq --argjson val "$payload" \
       --arg key "$name" \
       --arg top "$top_key" \
       "$_JQ_PATH_EXPR"' | setpath($p; $val)' \
       "$src" > "$settings"

    state_record "${_CURRENT_TYPE:-merge}" "${_CURRENT_AGENT:-unknown}" \
                 "$name" "$settings" "merge" "$backup"
    log_ok "json-merge [${top_key}.${name}]: ${settings}"
  else
    log_dry "json-merge [${top_key}.${name}]: ${settings}"
  fi
}

# ── JSON remove ───────────────────────────────────────────────────────────────
# json_remove <settings-json> <top-key> <name> [--restore]
json_remove() {
  local settings="$1" top_key="$2" name="$3" restore="${4:-}"
  require_cmd jq

  if [[ ! -f "$settings" ]]; then
    log_skip "${settings} — 파일 없음, 건너뜁니다."
    return
  fi

  # 키가 존재하는지 확인
  local exists; exists="$(jq --arg top "$top_key" --arg key "$name" \
    "$_JQ_PATH_EXPR"' | if (getpath($p)) != null then "yes" else "no" end' "$settings" 2>/dev/null || echo "no")"
  if [[ "$exists" != '"yes"' ]]; then
    log_skip "[${top_key}.${name}] 키가 없습니다 — 건너뜁니다."
    return
  fi

  if ! is_dry; then
    local backup; backup="$(state_backup_for "${_CURRENT_TYPE:-merge}" \
      "${_CURRENT_AGENT:-unknown}" "$name" "$settings")"

    local tmp; tmp="$(mktemp)"
    jq --arg top "$top_key" --arg key "$name" \
       "$_JQ_PATH_EXPR"' | delpaths([$p])' "$settings" > "$tmp"
    mv "$tmp" "$settings"

    if [[ "$restore" == "--restore" && -n "$backup" && -e "$backup" ]]; then
      mv "$backup" "$settings"
      log_ok "json-remove + 복원: [${top_key}.${name}] (${settings})"
    else
      log_ok "json-remove [${top_key}.${name}]: ${settings}"
    fi
    state_remove "${_CURRENT_TYPE:-merge}" "${_CURRENT_AGENT:-unknown}" "$name" "$settings"
  else
    log_dry "json-remove [${top_key}.${name}]: ${settings}"
  fi
}
