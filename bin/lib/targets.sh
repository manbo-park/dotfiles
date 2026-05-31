#!/usr/bin/env bash
# bin/lib/targets.sh — (type, agent) → {dest, mechanism, format} 레지스트리

# ── 지원 매트릭스 ─────────────────────────────────────────────────────────────
# skills/hooks: claude, cursor 만 지원 (codex 미지원)
# rules/mcps:   claude, cursor, codex 모두 지원
# shellcheck disable=SC2034  # 간접 참조로 사용 (${!varname})
SUPPORTED_AGENTS_rules="claude cursor codex"
SUPPORTED_AGENTS_skills="claude cursor"
SUPPORTED_AGENTS_hooks="claude cursor"
SUPPORTED_AGENTS_mcps="claude cursor codex"

# 해당 type 을 지원하는 에이전트 목록 반환
supported_agents() {
  local type="$1"
  local varname="SUPPORTED_AGENTS_${type}"
  echo "${!varname:-}"
}

# ── destination 산출 ──────────────────────────────────────────────────────────
# target_dest <type> <agent> <name>  → destination 경로 (stdout)
# 지원하지 않으면 빈 문자열 반환
target_dest() {
  local type="$1" agent="$2" name="$3"
  case "${type}:${agent}" in
    rules:claude)  echo "$HOME/.claude/rules/${name}.md" ;;
    rules:cursor)  echo "$HOME/.cursor/rules/${name}.mdc" ;;
    rules:codex)   echo "$HOME/.codex/AGENTS.md" ;;          # 파일 자체, 섹션 merge
    skills:claude) echo "$HOME/.claude/skills/${name}" ;;
    skills:cursor) echo "$HOME/.cursor/skills/${name}" ;;
    hooks:claude)  echo "$HOME/.claude/settings.json" ;;     # .hooks 키에 merge
    hooks:cursor)  echo "$HOME/.cursor/settings/settings.json" ;;  # .hooks 키에 merge
    mcps:claude)   echo "$HOME/.claude/settings.json" ;;     # .mcpServers 키에 merge
    mcps:cursor)   echo "$HOME/.cursor/mcp.json" ;;          # .mcpServers 키에 merge
    mcps:codex)    echo "$HOME/.codex/config.toml" ;;        # [mcp_servers.<name>] merge
    *)             echo "" ;;
  esac
}

# ── mechanism 산출 ────────────────────────────────────────────────────────────
# target_mechanism <type> <agent>  → symlink | convert | merge | merge-toml | merge-section
target_mechanism() {
  local type="$1" agent="$2"
  case "${type}:${agent}" in
    rules:claude)  echo "symlink" ;;
    rules:cursor)  echo "convert" ;;    # .md → .mdc (frontmatter 래핑)
    rules:codex)   echo "merge-section" ;;  # AGENTS.md 내 마커 블록
    skills:claude) echo "symlink" ;;
    skills:cursor) echo "symlink" ;;
    hooks:claude)  echo "merge" ;;      # JSON .hooks 키
    hooks:cursor)  echo "merge" ;;      # JSON .hooks 키
    mcps:claude)   echo "merge" ;;      # JSON .mcpServers 키
    mcps:cursor)   echo "merge" ;;      # JSON .mcpServers 키
    mcps:codex)    echo "merge-toml" ;; # TOML [mcp_servers.<name>]
    *)             echo "" ;;
  esac
}

# ── merge 대상 JSON 키 산출 ───────────────────────────────────────────────────
# merge 방식일 때 어떤 최상위 키 아래에 삽입할지
target_merge_key() {
  local type="$1" agent="$2"
  case "${type}:${agent}" in
    hooks:claude)  echo "hooks" ;;
    hooks:cursor)  echo "hooks" ;;
    mcps:claude)   echo "mcpServers" ;;
    mcps:cursor)   echo "mcpServers" ;;
    *)             echo "" ;;
  esac
}

# ── 단일 파일 소스 경로 산출 ─────────────────────────────────────────────────
# agents/<type>/<name> 기준의 소스 파일/디렉토리 경로
# REPO_ROOT 가 설정되어 있어야 함
source_path() {
  local type="$1" name="$2"
  echo "${REPO_ROOT}/agents/${type}/${name}"
}

# ── 에이전트 목록 파싱 ────────────────────────────────────────────────────────
# resolve_agents <type> <agent-arg>
# agent-arg: "all" | "" | "claude" | "cursor" | "codex"
# 지원 매트릭스를 교차 적용해 실제 에이전트 목록 반환
resolve_agents() {
  local type="$1" agent_arg="${2:-all}"
  local supported; supported="$(supported_agents "$type")"

  if [[ -z "$supported" ]]; then
    echo ""
    return
  fi

  if [[ "$agent_arg" == "all" ]]; then
    echo "$supported"
    return
  fi

  # 단일 에이전트 요청 — 지원 여부 확인
  if [[ " $supported " == *" ${agent_arg} "* ]]; then
    echo "$agent_arg"
  else
    log_warn "type '${type}' 는 agent '${agent_arg}' 를 지원하지 않습니다. 건너뜁니다."
    echo ""
  fi
}
