#!/usr/bin/env bash
# bin/lib/targets.sh — (type, agent) → {dest, mechanism, format} 레지스트리

# ── destination 산출 ──────────────────────────────────────────────────────────
# target_dest <type> <agent> <name>  → destination 경로 (stdout)
# 지원하지 않으면 빈 문자열 반환
target_dest() {
  local type="$1" agent="$2" name="$3"
  case "${type}:${agent}" in
    rules:claude)  echo "$HOME/.claude/rules/${name}.md" ;;
    skills:claude) echo "$HOME/.claude/skills/${name}" ;;
    hooks:claude)  echo "$HOME/.claude/settings.json" ;;     # .hooks 키에 merge
    mcps:claude)   echo "$HOME/.claude.json" ;;               # .mcpServers 키에 merge
    settings:claude) echo "$HOME/.claude/settings.json" ;;  # 최상위 키에 merge
    *)             echo "" ;;
  esac
}

# ── mechanism 산출 ────────────────────────────────────────────────────────────
# target_mechanism <type> <agent>  → symlink | merge | plugin
target_mechanism() {
  local type="$1" agent="$2"
  case "${type}:${agent}" in
    rules:claude)  echo "symlink" ;;
    skills:claude) echo "symlink" ;;
    hooks:claude)  echo "merge" ;;      # JSON .hooks 키
    mcps:claude)   echo "merge" ;;      # JSON .mcpServers 키
    plugins:claude) echo "plugin" ;;    # claude plugin install (파일 dest 없음)
    settings:claude) echo "merge" ;;    # JSON 최상위 키
    *)             echo "" ;;
  esac
}

# ── merge 대상 JSON 키 산출 ───────────────────────────────────────────────────
# merge 방식일 때 어떤 최상위 키 아래에 삽입할지
target_merge_key() {
  local type="$1" agent="$2"
  case "${type}:${agent}" in
    hooks:claude)  echo "hooks" ;;
    mcps:claude)   echo "mcpServers" ;;
    settings:claude) echo "" ;;      # 최상위 (중첩 키 없음)
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
