#!/usr/bin/env bash
# bin/lib/fonts.sh — 폰트 다운로드·설치·제거
#
# 의존: common.sh, state.sh (REPO_ROOT, ensure_parent, is_dry, run_or_dry, log_*, state_*)
#
# 폰트 정의:  fonts/<family>/source.json
#   { "url": "...", "version": "x.y.z", "files": ["glob", ...] }
#   files 생략 시 zip 내 모든 .ttf/.otf 설치
#
# 캐시:       ~/.cache/pcfg/fonts/<family>/<version>/font.zip
# 설치 경로:  macOS → ~/Library/Fonts/   Linux → ~/.local/share/fonts/

FONTS_DIR="${REPO_ROOT}/fonts"
FONTS_CACHE_DIR="${HOME}/.cache/pcfg/fonts"

_fonts_install_dir() {
  case "$(uname -s)" in
    Darwin) echo "${HOME}/Library/Fonts" ;;
    Linux)  echo "${HOME}/.local/share/fonts" ;;
    *)      die "지원하지 않는 플랫폼입니다: $(uname -s)" ;;
  esac
}

list_font_families() {
  [[ -d "$FONTS_DIR" ]] || return 0
  find "$FONTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort | xargs -I{} basename {}
}

# source.json 필드 읽기
_font_field() { jq -r "${2} // empty" "${FONTS_DIR}/${1}/source.json" 2>/dev/null; }

_font_url()      { _font_field "$1" '.url'; }
_font_version()  { _font_field "$1" '.version // "latest"'; }
_font_patterns() { _font_field "$1" '.files[]?'; }

# zip 다운로드 (캐시 적중 시 재사용)
_download_font_zip() {
  local family="$1" url="$2" version="$3"
  local cache_dir="${FONTS_CACHE_DIR}/${family}/${version}"
  local zip_file="${cache_dir}/font.zip"

  if [[ -f "$zip_file" ]]; then
    log_info "${family} v${version} 캐시 사용: ${zip_file}"
    echo "$zip_file"
    return
  fi

  log_info "${family} 다운로드 중: ${url}"
  mkdir -p "$cache_dir"
  if ! curl -fsSL --progress-bar -o "$zip_file" "$url"; then
    rm -f "$zip_file"
    die "${family} 다운로드 실패: ${url}"
  fi
  log_ok "다운로드 완료: ${zip_file}"
  echo "$zip_file"
}

# glob 패턴 매칭 (파일명 단위)
_font_matches_patterns() {
  local fname="$1" patterns="$2"
  [[ -z "$patterns" ]] && return 0
  local pattern
  while IFS= read -r pattern; do
    # shellcheck disable=SC2254
    case "$fname" in $pattern) return 0 ;; esac
  done <<< "$patterns"
  return 1
}

_install_fonts() {
  local family_arg="$1"
  local families

  if [[ -n "$family_arg" ]]; then
    families="$family_arg"
  else
    families="$(list_font_families)"
  fi

  [[ -z "$families" ]] && { log_info "설치할 폰트가 없습니다."; return; }

  local dest_dir; dest_dir="$(_fonts_install_dir)"

  for family in $families; do
    local src_dir="${FONTS_DIR}/${family}"
    local source_json="${src_dir}/source.json"

    [[ -d "$src_dir" ]] || { log_warn "폰트 디렉토리가 없습니다: ${src_dir}"; continue; }
    [[ -f "$source_json" ]] || { log_warn "${family}/source.json 이 없습니다. 건너뜁니다."; continue; }

    local url version patterns
    url="$(_font_url "$family")"
    version="$(_font_version "$family")"
    patterns="$(_font_patterns "$family")"

    [[ -z "$url" ]] && { log_warn "${family}/source.json 에 url 이 없습니다."; continue; }

    if is_dry; then
      log_dry "${family}: would download ${url} → ${dest_dir}/"
      continue
    fi

    ensure_parent "${dest_dir}/.keep"

    local zip_file; zip_file="$(_download_font_zip "$family" "$url" "$version")"
    local tmp_dir; tmp_dir="$(mktemp -d)"

    if ! unzip -q "$zip_file" -d "$tmp_dir"; then
      rm -rf "$tmp_dir"
      die "${family} 압축 해제 실패"
    fi

    local count=0
    while IFS= read -r font_file; do
      local fname; fname="$(basename "$font_file")"
      _font_matches_patterns "$fname" "$patterns" || continue
      if [[ -f "${dest_dir}/${fname}" ]]; then
        log_skip "폰트 이미 설치됨: ${dest_dir}/${fname}"
        ((count++)) || true
        continue
      fi
      cp "$font_file" "${dest_dir}/${fname}"
      state_record "fonts" "_" "${family}/${fname}" "${dest_dir}/${fname}" "font" ""
      log_ok "폰트 설치: ${dest_dir}/${fname}"
      ((count++)) || true
    done < <(find "$tmp_dir" -type f \( -name "*.ttf" -o -name "*.otf" \) | sort)

    rm -rf "$tmp_dir"
    [[ "$count" -eq 0 ]] && log_warn "${family}: 매칭되는 폰트 파일이 없습니다. (files 패턴을 확인하세요)"
  done
}

_uninstall_fonts() {
  local family_arg="$1" restore_flag="$2"
  local families

  if [[ -n "$family_arg" ]]; then
    families="$family_arg"
  else
    families="$(list_font_families)"
  fi

  [[ -z "$families" ]] && return

  for family in $families; do
    # state 읽기와 수정이 겹치지 않도록 먼저 수집
    local names=() dests=()
    while IFS=$'\t' read -r _t _a name dest _m _b _ts; do
      [[ "$_t" =~ ^# || -z "$_t" ]] && continue
      [[ "$name" == "${family}/"* ]] || continue
      names+=("$name")
      dests+=("$dest")
    done < <(state_query "fonts" "_" 2>/dev/null || true)

    if [[ ${#names[@]} -eq 0 ]]; then
      log_info "${family}: 설치 기록이 없습니다."
      continue
    fi

    local i
    for ((i = 0; i < ${#names[@]}; i++)); do
      local name="${names[$i]}" dest="${dests[$i]}"
      if [[ ! -f "$dest" ]]; then
        log_skip "${dest} — 파일 없음"
        state_remove "fonts" "_" "$name" "$dest" 2>/dev/null || true
        continue
      fi
      if ! is_dry; then
        rm "$dest"
        state_remove "fonts" "_" "$name" "$dest"
        log_ok "폰트 제거: ${dest}"
      else
        log_dry "rm: ${dest}"
      fi
    done
  done
}
