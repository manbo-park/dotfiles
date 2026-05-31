#!/usr/bin/env bash
# bin/lib/manifest.sh — 아이템 열거 + manifest 파싱
#
# 의존: common.sh, targets.sh (REPO_ROOT 필요)

# ── agents 아이템 열거 ────────────────────────────────────────────────────────
# list_agent_items <type>  → 이름 목록 (한 줄에 하나)
list_agent_items() {
  local type="$1"
  local dir="${REPO_ROOT}/agents/${type}"
  [[ -d "$dir" ]] || return 0

  case "$type" in
    rules)
      find "$dir" -maxdepth 1 -name '*.md' -not -name '.gitkeep' \
        | sort | xargs -I{} basename {} .md
      ;;
    skills)
      find "$dir" -maxdepth 1 -mindepth 1 -type d \
        | sort | xargs -I{} basename {}
      ;;
    hooks)
      find "$dir" -maxdepth 1 -mindepth 1 -type d \
        | sort | xargs -I{} basename {}
      ;;
    mcps)
      find "$dir" -maxdepth 1 -name '*.json' -not -name '.gitkeep' \
        | sort | xargs -I{} basename {} .json
      ;;
    *)
      log_warn "알 수 없는 type: ${type}"
      ;;
  esac
}

# ── configs 아이템 열거 ───────────────────────────────────────────────────────
# list_config_items  → 프로그램 이름 목록
list_config_items() {
  local dir="${REPO_ROOT}/configs"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -mindepth 1 -type d \
    | sort | xargs -I{} basename {}
}

# ── manifest 파싱 ─────────────────────────────────────────────────────────────
# parse_manifest <manifest-file>  → "source\tdestination" 줄 목록
# 빈 줄·# 주석 제거, ~ / $VAR 확장 적용
parse_manifest() {
  local mf="$1"
  [[ -f "$mf" ]] || return 0

  while IFS= read -r line; do
    # 빈 줄·주석 제거
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # 공백 분리 (첫 토큰=src, 나머지=dest)
    local src rest
    read -r src rest <<< "$line"
    [[ -z "$src" || -z "$rest" ]] && continue
    local dest; dest="$(expand_path "$rest")"
    printf '%s\t%s\n' "$src" "$dest"
  done < "$mf"
}

# ── configs manifest 경로 산출 ────────────────────────────────────────────────
# configs_manifest <prog>  → manifest 파일 절대 경로
configs_manifest() {
  local prog="$1"
  echo "${REPO_ROOT}/configs/${prog}/manifest"
}

# ── configs 설치 쌍 열거 ─────────────────────────────────────────────────────
# configs_pairs <prog>  → "abs-source\tabs-dest" 줄 목록
# manifest 없으면 에러 안내
configs_pairs() {
  local prog="$1"
  local mf; mf="$(configs_manifest "$prog")"
  if [[ ! -f "$mf" ]]; then
    log_warn "configs/${prog}/manifest 가 없습니다. destination 을 지정하려면 manifest 를 추가하세요. 건너뜁니다."
    return 0
  fi

  local base_dir="${REPO_ROOT}/configs/${prog}"
  while IFS=$'\t' read -r src dest; do
    local abs_src="${base_dir}/${src}"
    if [[ ! -e "$abs_src" ]]; then
      log_warn "소스 파일이 없습니다: ${abs_src} — 건너뜁니다."
      continue
    fi
    printf '%s\t%s\n' "$abs_src" "$dest"
  done < <(parse_manifest "$mf")
}

# ── agents override manifest 파싱 ────────────────────────────────────────────
# agents 아이템에 manifest 가 있으면 해당 항목은 registry 컨벤션 대신 manifest 값 사용
# agent_manifest_dest <type> <name> <agent>
# → manifest 에서 해당 agent 의 dest override 를 찾아 반환 (없으면 빈 문자열)
# manifest 형식 (agents용, agent 컬럼 포함):
#   <agent>  <source>  <destination>
agent_manifest_dest() {
  local type="$1" name="$2" agent="$3"
  local mf="${REPO_ROOT}/agents/${type}/${name}/manifest"
  [[ -f "$mf" ]] || { echo ""; return; }

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    local ag src dest
    read -r ag src dest <<< "$line"
    if [[ "$ag" == "$agent" ]]; then
      expand_path "$dest"
      return
    fi
  done < "$mf"
  echo ""
}
