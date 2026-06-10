#!/usr/bin/env bash
# bin/lib/common.sh — 로깅·색상·에러, 경로 확장, dry-run 플래그, 의존성 확인

set -euo pipefail

# ── 색상 ──────────────────────────────────────────────────────────────────────
if [[ -t 2 ]]; then
  _RED=$'\033[0;31m'; _YEL=$'\033[0;33m'; _GRN=$'\033[0;32m'
  _CYN=$'\033[0;36m'; _BLD=$'\033[1m';    _RST=$'\033[0m'
else
  _RED=''; _YEL=''; _GRN=''; _CYN=''; _BLD=''; _RST=''
fi

# ── 로깅 ──────────────────────────────────────────────────────────────────────
log_info()  { printf '%s[info]%s  %s\n'  "$_CYN" "$_RST" "$*" >&2; }
log_ok()    { printf '%s[ok]%s    %s\n'  "$_GRN" "$_RST" "$*" >&2; }
log_warn()  { printf '%s[warn]%s  %s\n'  "$_YEL" "$_RST" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n'  "$_RED" "$_RST" "$*" >&2; }
log_dry()   { printf '%s[dry]%s   %s\n'  "$_BLD" "$_RST" "$*" >&2; }
log_skip()  { printf '%s[skip]%s  %s\n'  "$_BLD" "$_RST" "$*" >&2; }

die() { log_error "$*"; exit 1; }

# ── dry-run ───────────────────────────────────────────────────────────────────
# 사용: PCFG_DRY_RUN=1 pcfg install ...  또는 --dry-run 플래그로 설정
PCFG_DRY_RUN="${PCFG_DRY_RUN:-0}"

is_dry() { [[ "$PCFG_DRY_RUN" == "1" ]]; }

# 실제 실행 또는 dry-run 로그 출력
run_or_dry() {
  if is_dry; then
    log_dry "would run: $*"
  else
    "$@"
  fi
}

# ── 경로 확장 (~ / $VAR) ──────────────────────────────────────────────────────
expand_path() {
  local p="$1"
  # $VAR 확장
  p="${p/\$HOME/$HOME}"
  p="$(eval echo "${p/\~/~}")"   # ~ 확장은 eval로 처리
  echo "$p"
}

# ── 부모 디렉토리 생성 ────────────────────────────────────────────────────────
ensure_parent() {
  local dest="$1"
  local parent; parent="$(dirname "$dest")"
  if [[ ! -d "$parent" ]]; then
    run_or_dry mkdir -p "$parent"
  fi
}

# ── 타임스탬프 ────────────────────────────────────────────────────────────────
timestamp() { date +%Y%m%d%H%M%S; }

# ── 백업 ─────────────────────────────────────────────────────────────────────
# 기존 파일/링크를 .pcfg-bak.<ts> 로 이동. 백업 경로를 stdout으로 반환.
backup_if_exists() {
  local dest="$1"
  if [[ -e "$dest" || -L "$dest" ]]; then
    local bak; bak="${dest}.pcfg-bak.$(timestamp)"
    run_or_dry mv "$dest" "$bak"
    if ! is_dry; then
      echo "$bak"
    else
      echo ""
    fi
  else
    echo ""
  fi
}

# ── 의존성 확인 ───────────────────────────────────────────────────────────────
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    die "'$cmd' 가 설치되어 있지 않습니다. README의 의존성 항목을 확인하세요."
  fi
}

brew_ensure() {
  local cmd="$1" tap="${2:-}" pkg="${3:-$1}" type="${4:-brew}"
  case "$type" in
    cask) brew list --cask "$pkg" &>/dev/null && return 0 ;;
    # lib: CLI 바이너리가 없는 formula (zsh 플러그인 등) — formula 설치 여부로 판별
    lib)  brew list "$pkg" &>/dev/null && return 0 ;;
    *)    command -v "$cmd" &>/dev/null && return 0 ;;
  esac
  if ! command -v brew &>/dev/null; then
    die "'$cmd' 설치에 Homebrew가 필요합니다. https://brew.sh 를 참고하세요."
  fi
  log_info "'$cmd' 가 없어 Homebrew로 설치합니다..."
  if [[ -n "$tap" ]]; then
    run_or_dry brew tap "$tap"
  fi
  if [[ "$type" == "cask" ]]; then
    run_or_dry brew install --cask "$pkg"
  else
    run_or_dry brew install "$pkg"
  fi
}

check_deps() {
  require_cmd jq
  # TOML 변환: dasel 또는 python3(tomllib/tomli_w)
  if ! command -v dasel &>/dev/null; then
    if ! command -v python3 &>/dev/null; then
      die "TOML 변환을 위해 'dasel' 또는 'python3'(tomllib/tomli_w) 가 필요합니다."
    fi
  fi
  brew_ensure ghostty   ""                 ghostty   cask
  brew_ensure starship  ""                 starship
  brew_ensure tmux      ""                 tmux
  brew_ensure zsh       ""                 zsh
  brew_ensure im-select daipeihust/tap     im-select
  brew_ensure fzf       ""                 fzf
  brew_ensure fzf-tab   ""                 fzf-tab   lib
}

# ── PCFG 마커 ─────────────────────────────────────────────────────────────────
# 생성 파일·merge 블록 식별용 마커 문자열
pcfg_marker_begin() { echo "# >>> pcfg:${1} >>>"; }
pcfg_marker_end()   { echo "# <<< pcfg:${1} <<<"; }
