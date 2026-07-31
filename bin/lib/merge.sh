#!/usr/bin/env bash
# bin/lib/merge.sh — settings 파일에 JSON(jq)/TOML 조각 merge·remove
#
# 의존: common.sh, state.sh (require_cmd, backup_if_exists, is_dry,
#        run_or_dry, log_*, state_record, state_remove, timestamp)

# ── 내부: top-key 유무에 따른 jq 경로 ────────────────────────────────────────
# $top 이 빈 문자열이면 [$key], 아니면 [$top, $key] 를 $p 로 바인딩한다.
_JQ_PATH_EXPR='(if $top == "" then [$key] else [$top, $key] end) as $p'

# ── JSON merge ────────────────────────────────────────────────────────────────
# json_merge <settings-json> <top-key> <name> <fragment-json>
#   settings-json: ~/.claude/settings.json 등
#   top-key: "mcpServers" | "hooks" | "" (빈 값이면 최상위 키에 직접 merge)
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

# ── TOML merge (mcps → codex config.toml) ────────────────────────────────────
# toml_merge_mcp <config-toml> <name> <fragment-json>
#   fragment-json: 표준 MCP JSON ( {"command":…, "args":…, "env":…} )
#   → [mcp_servers.<name>] 섹션으로 변환 후 삽입
toml_merge_mcp() {
  local config_toml="$1" name="$2" fragment="$3"

  local payload
  if [[ -f "$fragment" ]]; then
    payload="$(cat "$fragment")"
  else
    payload="$fragment"
  fi

  # JSON → TOML 섹션 변환
  local toml_section; toml_section="$(_json_to_toml_mcp_section "$name" "$payload")"
  if [[ -z "$toml_section" ]]; then
    log_warn "TOML 변환 실패: ${name} — 건너뜁니다."
    return
  fi

  # 이미 동일한 섹션이 있으면 no-op
  if [[ -f "$config_toml" ]]; then
    local current
    current="$(awk -v hdr="[mcp_servers.${name}]" '
      $0==hdr {cap=1; print; next}
      cap && /^\[/ {cap=0}
      cap {print}
    ' "$config_toml")"
    if [[ "$current" == "$toml_section" ]]; then
      log_skip "toml-merge [mcp_servers.${name}]: ${config_toml} (이미 최신 내용)"
      return
    fi
  fi

  if ! is_dry; then
    ensure_parent "$config_toml"
    [[ -f "$config_toml" ]] || touch "$config_toml"

    # 기존 동일 섹션 제거 (멱등)
    _toml_remove_section "$config_toml" "$name"

    local backup_tmp; backup_tmp="${config_toml}.pcfg-bak.$(timestamp)"
    cp "$config_toml" "$backup_tmp"

    printf '\n%s\n' "$toml_section" >> "$config_toml"
    state_record "mcps" "codex" "$name" "$config_toml" "merge-toml" "$backup_tmp"
    log_ok "toml-merge [mcp_servers.${name}]: ${config_toml}"
  else
    log_dry "toml-merge [mcp_servers.${name}]: ${config_toml}"
  fi
}

# ── TOML remove ───────────────────────────────────────────────────────────────
# toml_remove_mcp <config-toml> <name> [--restore]
toml_remove_mcp() {
  local config_toml="$1" name="$2" restore="${3:-}"

  if [[ ! -f "$config_toml" ]]; then
    log_skip "${config_toml} — 파일 없음, 건너뜁니다."
    return
  fi

  if ! is_dry; then
    local backup; backup="$(state_backup_for "mcps" "codex" "$name" "$config_toml")"
    _toml_remove_section "$config_toml" "$name"

    if [[ "$restore" == "--restore" && -n "$backup" && -e "$backup" ]]; then
      mv "$backup" "$config_toml"
      log_ok "toml-remove + 복원: [mcp_servers.${name}] (${config_toml})"
    else
      log_ok "toml-remove [mcp_servers.${name}]: ${config_toml}"
    fi
    state_remove "mcps" "codex" "$name" "$config_toml"
  else
    log_dry "toml-remove [mcp_servers.${name}]: ${config_toml}"
  fi
}

# ── 내부: TOML 섹션 제거 ─────────────────────────────────────────────────────
_toml_remove_section() {
  local config_toml="$1" name="$2"
  local section_header="[mcp_servers.${name}]"
  local tmp; tmp="$(mktemp)"
  awk -v hdr="$section_header" '
    $0 == hdr { in_section=1; next }
    in_section && /^\[/ { in_section=0 }
    !in_section { print }
  ' "$config_toml" > "$tmp"
  mv "$tmp" "$config_toml"
}

# ── 내부: JSON MCP → TOML 섹션 문자열 생성 ───────────────────────────────────
# dasel 또는 python3 사용
_json_to_toml_mcp_section() {
  local name="$1" json="$2"

  if command -v dasel &>/dev/null; then
    # dasel: JSON stdin → TOML 변환, 섹션 헤더 붙여서 출력
    local toml_body; toml_body="$(echo "$json" | dasel -r json -w toml 2>/dev/null)" || true
    if [[ -n "$toml_body" ]]; then
      printf '[mcp_servers.%s]\n%s\n' "$name" "$toml_body"
      return
    fi
  fi

  if command -v python3 &>/dev/null; then
    # JSON을 환경변수로 전달 (heredoc이 stdin을 소비하므로 stdin 재사용 불가)
    PCFG_MCP_JSON="$json" python3 - "$name" <<'PYEOF'
import sys, json, os
name = sys.argv[1]
data = json.loads(os.environ['PCFG_MCP_JSON'])

lines = [f'[mcp_servers.{name}]']
for k, v in data.items():
    if isinstance(v, str):
        escaped = v.replace('\\', '\\\\').replace('"', '\\"')
        lines.append(f'{k} = "{escaped}"')
    elif isinstance(v, list):
        items = ', '.join(f'"{x}"' if isinstance(x, str) else str(x) for x in v)
        lines.append(f'{k} = [{items}]')
    elif isinstance(v, dict):
        for dk, dv in v.items():
            escaped = str(dv).replace('\\', '\\\\').replace('"', '\\"')
            lines.append(f'{k}.{dk} = "{escaped}"')
    elif isinstance(v, bool):
        lines.append(f'{k} = {"true" if v else "false"}')
    elif isinstance(v, (int, float)):
        lines.append(f'{k} = {v}')
print('\n'.join(lines))
PYEOF
    return
  fi

  echo ""
}
