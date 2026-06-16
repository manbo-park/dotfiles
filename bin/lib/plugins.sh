#!/usr/bin/env bash
# bin/lib/plugins.sh — 에이전트 플러그인 설치·제거 (mechanism: plugin)
#
# 의존: common.sh, targets.sh (REPO_ROOT, is_dry, run_or_dry, log_*)
#
# 플러그인 정의:  agents/plugins/<plugin>.json  (파일명 = 플러그인 ID)
#   에이전트별 키 아래에 그 에이전트용 설치 정보를 둔다.
#   {
#     "claude": { "marketplace": "<name>", "source": "<github-repo-or-url>" }
#   }
#   해당 에이전트 키가 없으면 그 에이전트 설치는 건너뛴다.
#   동일 플러그인을 여러 에이전트에 설치하려면 키를 여러 개 둔다.
#
# 상태 진실원은 각 에이전트 CLI 가 보유한다 (state.tsv 에 기록하지 않음).

# JSON 필드 읽기:  _plugin_field <name> <jq-path>
_plugin_field() {
  jq -r "${2} // empty" "${REPO_ROOT}/agents/plugins/${1}.json" 2>/dev/null
}

# 정의 JSON 에 해당 에이전트 키가 있는지:  _plugin_has_agent <name> <agent>
_plugin_has_agent() {
  local val; val="$(_plugin_field "$1" ".\"${2}\"")"
  [[ -n "$val" ]]
}

# ── 설치 ─────────────────────────────────────────────────────────────────────
# plugin_install <agent> <name>
plugin_install() {
  local agent="$1" name="$2"
  if ! _plugin_has_agent "$name" "$agent"; then
    log_skip "plugins/${name}/${agent} — 정의에 ${agent} 항목이 없습니다."
    return
  fi
  case "$agent" in
    claude) _plugin_install_claude "$name" ;;
    *)      log_warn "plugins: 알 수 없는 에이전트 '${agent}' (${name})" ;;
  esac
}

_plugin_install_claude() {
  local name="$1"
  if ! command -v claude &>/dev/null; then
    log_warn "plugins/${name}/claude — 'claude' CLI 가 없어 건너뜁니다."
    return
  fi
  local mk src; mk="$(_plugin_field "$name" '.claude.marketplace')"
  src="$(_plugin_field "$name" '.claude.source')"
  if [[ -z "$mk" || -z "$src" ]]; then
    log_warn "plugins/${name}/claude — marketplace/source 가 정의되지 않았습니다."
    return
  fi

  _plugin_ensure_marketplace_claude "$mk" "$src"

  if claude plugin list 2>/dev/null | grep -q "${name}@${mk}"; then
    log_skip "plugins/${name}/claude — 이미 설치되어 있습니다."
    return
  fi
  run_or_dry claude plugin install "${name}@${mk}"
  is_dry || log_ok "플러그인 설치: ${name}@${mk} (claude)"
}

# 마켓플레이스가 없으면 추가:  _plugin_ensure_marketplace_claude <marketplace> <source>
_plugin_ensure_marketplace_claude() {
  local mk="$1" src="$2"
  if claude plugin marketplace list 2>/dev/null | grep -qw "$mk"; then
    return
  fi
  run_or_dry claude plugin marketplace add "$src"
  is_dry || log_ok "마켓플레이스 추가: ${mk} (${src})"
}

# ── 제거 ─────────────────────────────────────────────────────────────────────
# plugin_uninstall <agent> <name> <restore_flag>
# 마켓플레이스는 다른 플러그인과 공유될 수 있어 제거하지 않는다.
plugin_uninstall() {
  local agent="$1" name="$2" _restore_flag="${3:-}"
  case "$agent" in
    claude) _plugin_uninstall_claude "$name" ;;
    *)      log_warn "plugins: 알 수 없는 에이전트 '${agent}' (${name})" ;;
  esac
}

_plugin_uninstall_claude() {
  local name="$1"
  if ! command -v claude &>/dev/null; then
    log_warn "plugins/${name}/claude — 'claude' CLI 가 없어 건너뜁니다."
    return
  fi
  local mk; mk="$(_plugin_field "$name" '.claude.marketplace')"
  [[ -z "$mk" ]] && return
  if ! claude plugin list 2>/dev/null | grep -q "${name}@${mk}"; then
    log_skip "plugins/${name}/claude — 설치되어 있지 않습니다."
    return
  fi
  run_or_dry claude plugin uninstall "${name}@${mk}"
  is_dry || log_ok "플러그인 제거: ${name}@${mk} (claude)"
}

# ── 설치 여부 (cmd_list 용) ──────────────────────────────────────────────────
# plugin_is_installed <agent> <name>
plugin_is_installed() {
  local agent="$1" name="$2"
  case "$agent" in
    claude)
      command -v claude &>/dev/null || return 1
      local mk; mk="$(_plugin_field "$name" '.claude.marketplace')"
      [[ -n "$mk" ]] || return 1
      claude plugin list 2>/dev/null | grep -q "${name}@${mk}"
      ;;
    *) return 1 ;;
  esac
}
