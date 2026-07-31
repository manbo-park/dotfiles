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

# ── Linux(apt) 의존성 확인 ────────────────────────────────────────────────────
apt_ensure() {
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" &>/dev/null && return 0
  if ! command -v apt-get &>/dev/null; then
    die "'$cmd' 가 설치되어 있지 않고, apt-get도 없어 자동 설치할 수 없습니다. 수동으로 설치해주세요."
  fi
  log_info "'$cmd' 가 없어 apt로 설치합니다..."
  local sudo_cmd=()
  [[ "$(id -u)" != "0" ]] && sudo_cmd=(sudo)
  run_or_dry "${sudo_cmd[@]}" apt-get install -y "$pkg"
}

# gem(Ruby) 기반 도구 설치 — tmuxinator 등 apt 패키지가 불안정한 경우
gem_ensure() {
  local cmd="$1" gem_name="${2:-$1}"
  command -v "$cmd" &>/dev/null && return 0
  if ! command -v gem &>/dev/null; then
    die "'$cmd' 설치에 ruby/gem이 필요합니다. 'sudo apt-get install ruby-full' 로 먼저 설치하세요."
  fi
  log_info "'$cmd' 가 없어 gem으로 설치합니다..."
  run_or_dry gem install --user-install "$gem_name"
}

# starship 공식 설치 스크립트 (Linux apt 패키지가 배포판마다 없거나 오래됨)
starship_ensure_linux() {
  command -v starship &>/dev/null && return 0
  command -v curl &>/dev/null || die "'starship' 설치에 curl이 필요합니다."
  log_info "'starship' 이 없어 공식 설치 스크립트로 설치합니다..."
  run_or_dry mkdir -p "${HOME}/.local/bin"
  run_or_dry bash -c 'curl -sS https://starship.rs/install.sh | sh -s -- -b "$HOME/.local/bin" -y'
}

# GitHub CLI 설치 — Ubuntu 기본 저장소의 gh는 버전이 오래되어 공식 apt 저장소를 등록해 설치한다.
gh_ensure_linux() {
  command -v gh &>/dev/null && return 0
  command -v apt-get &>/dev/null || die "'gh' 자동 설치에 apt-get이 필요합니다. https://github.com/cli/cli#installation 를 참고해 수동 설치하세요."
  command -v curl &>/dev/null || die "'gh' 설치에 curl이 필요합니다."
  log_info "'gh' 가 없어 GitHub 공식 apt 저장소를 등록하고 설치합니다..."

  local sudo_s=""
  [[ "$(id -u)" != "0" ]] && sudo_s="sudo"
  local keyring="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
  local arch; arch="$(dpkg --print-architecture)"

  run_or_dry bash -c "${sudo_s} mkdir -p -m 755 /etc/apt/keyrings"
  run_or_dry bash -c "curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | ${sudo_s} tee '${keyring}' >/dev/null"
  run_or_dry bash -c "${sudo_s} chmod go+r '${keyring}'"
  run_or_dry bash -c "echo 'deb [arch=${arch} signed-by=${keyring}] https://cli.github.com/packages stable main' | ${sudo_s} tee /etc/apt/sources.list.d/github-cli.list >/dev/null"
  run_or_dry bash -c "${sudo_s} apt-get update"
  run_or_dry bash -c "${sudo_s} apt-get install -y gh"
}

# zsh 플러그인(git clone 방식) 설치 — apt/brew에 없는 zsh 전용 플러그인용
ZSH_PLUGIN_DIR="${HOME}/.zsh/plugins"
zsh_plugin_ensure() {
  local name="$1" repo="$2"
  local dest="${ZSH_PLUGIN_DIR}/${name}"
  [[ -d "$dest" ]] && return 0
  command -v git &>/dev/null || die "'$name' 설치에 git이 필요합니다."
  log_info "'$name' 플러그인이 없어 git clone으로 설치합니다..."
  run_or_dry mkdir -p "$ZSH_PLUGIN_DIR"
  run_or_dry git clone --depth 1 "$repo" "$dest"
}

check_deps_macos() {
  brew_ensure jq        ""                 jq
  brew_ensure ghostty   ""                 ghostty   cask
  brew_ensure starship  ""                 starship
  brew_ensure tmux      ""                 tmux
  brew_ensure tmuxinator ""               tmuxinator
  brew_ensure zsh       ""                 zsh
  brew_ensure im-select daipeihust/tap     im-select
  brew_ensure fzf       ""                 fzf
  brew_ensure fzf-tab   ""                 fzf-tab   lib
  brew_ensure gh        ""                 gh
  brew_ensure node      ""                 node
}

check_deps_linux() {
  apt_ensure jq
  apt_ensure tmux
  apt_ensure zsh
  apt_ensure fzf
  apt_ensure node nodejs
  gem_ensure tmuxinator
  starship_ensure_linux
  gh_ensure_linux
  zsh_plugin_ensure fzf-tab                https://github.com/Aloxaf/fzf-tab.git
  zsh_plugin_ensure zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions.git
  zsh_plugin_ensure zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git
  log_skip "ghostty: Linux/WSL에서는 자동 설치를 건너뜁니다 (WSL은 보통 Windows 호스트 쪽 터미널을 사용합니다)."
  log_skip "im-select: macOS 전용 도구라 Linux/WSL에서는 건너뜁니다."
}

check_deps() {
  case "$(uname -s)" in
    Darwin) check_deps_macos ;;
    Linux)  check_deps_linux ;;
    *)      die "지원하지 않는 플랫폼입니다: $(uname -s)" ;;
  esac

  # TOML 변환: dasel 또는 python3(tomllib/tomli_w) — 배포판마다 패키지명이 갈려 자동 설치는 하지 않는다.
  if ! command -v dasel &>/dev/null; then
    if ! command -v python3 &>/dev/null; then
      die "TOML 변환을 위해 'dasel' 또는 'python3'(tomllib/tomli_w) 가 필요합니다."
    fi
  fi
}

# ── 플랫폼 판별 ───────────────────────────────────────────────────────────────
is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

# ── PCFG 마커 ─────────────────────────────────────────────────────────────────
# 생성 파일·merge 블록 식별용 마커 문자열
pcfg_marker_begin() { echo "# >>> pcfg:${1} >>>"; }
pcfg_marker_end()   { echo "# <<< pcfg:${1} <<<"; }
