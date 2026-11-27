# dotfiles

Claude Code의 rules·skills·hooks·mcps·plugins·settings 설정과
tmux·zsh·ghostty 등 프로그램 설정 파일, 개발 폰트를 한곳에서 버전 관리하는 dotfiles 저장소입니다.

## 의존성

macOS와 Linux(WSL 포함)를 모두 지원합니다. `pcfg install` 실행 시 플랫폼을 자동 감지해
macOS는 Homebrew, Linux/WSL은 apt(+ 일부 gem/git clone/공식 설치 스크립트)로 부족한 도구를
설치합니다.

| 도구 | 용도 | macOS | Linux / WSL |
|------|------|-------|-------------|
| `bash` 4+ | 스크립트 실행 | `brew install bash` | 배포판 기본 포함 |
| `jq` | JSON merge/remove | `brew install jq` | `apt install jq` |
| `curl` | 폰트 zip 다운로드 | 기본 포함 | `apt install curl` |
| `unzip` | 폰트 zip 압축 해제 | 기본 포함 | `apt install unzip` |
| `git` | zsh 플러그인 clone (fzf-tab 등) | 기본 포함 | `apt install git` |
| `gh` | GitHub CLI (PR·이슈 작업) | `brew install gh` | GitHub 공식 apt 저장소 (자동 등록) |
| `node` | 에이전트 플러그인 훅 실행 (ponytail 등) | `brew install node` | `apt install nodejs` |
| `python3` | 로컬 플러그인 훅 실행 (session-tools) | 시스템 python3 | `apt install python3` (기본 포함인 경우 많음) |

### WSL 관련 참고사항

- `ghostty`, `im-select`는 각각 GUI 터미널 앱 / macOS 입력소스 전환 도구라 Linux·WSL에서는
  `check_deps`가 자동 설치를 건너뜁니다. WSL에서 Ghostty를 쓰려면 Windows 호스트 쪽에
  별도로 설치하세요.
- `tmuxinator`는 apt 패키지 대신 `gem install --user-install tmuxinator`로, `starship`은
  공식 설치 스크립트(`https://starship.rs/install.sh`, `~/.local/bin`에 설치)로 설치합니다.
- `gh`는 Ubuntu 기본 저장소 버전이 오래되어(24.04 기준 2.45.0) `apt install gh` 대신 GitHub
  공식 apt 저장소(`https://cli.github.com/packages`)를 등록해 최신 버전을 설치합니다. 저장소
  등록과 설치에 `sudo` 권한이 필요합니다.
- `node`는 Claude Code 플러그인(ponytail 등)의 훅이 Node.js 스크립트라 필요합니다. 없으면
  프롬프트마다 `UserPromptSubmit hook error: node: Permission denied` 류의 에러가 뜹니다.
  Ubuntu 기본 저장소 버전(24.04 기준 18.x)으로 충분하며, 더 최신 버전이 필요하면 NodeSource
  저장소나 nvm으로 별도 설치하세요.
- `fzf-tab`/`zsh-autosuggestions`/`zsh-syntax-highlighting`은 apt 패키지가 불안정하거나 없어
  `~/.zsh/plugins/<name>`에 git clone으로 설치하고, `configs/zsh/zshrc`가 이 경로를 우선
  source합니다(없으면 macOS Homebrew 경로로 폴백).
- 폰트는 WSL 내부 `~/.local/share/fonts`에 설치되므로, Windows Terminal 등 Windows 쪽
  터미널에서 사용하려면 같은 Nerd Font를 Windows에도 별도로 설치해야 합니다.

## 디렉토리 구조

```
dotfiles/
├── bin/
│   ├── pcfg          # 단일 진입 CLI
│   ├── install       # pcfg install 래퍼
│   ├── uninstall     # pcfg uninstall 래퍼
│   └── lib/          # 내부 라이브러리
├── agents/
│   ├── rules/        # <name>.md
│   ├── skills/       # <name>/ (디렉토리)
│   ├── hooks/        # <name>/ (hook.json + scripts)
│   ├── mcps/         # <name>.json
│   ├── plugins/      # <name>.json (마켓플레이스 정의), local/ (로컬 마켓플레이스)
│   └── settings/     # <key>.json (settings.json 최상위 키 = 파일명, 값 = 내용)
├── configs/
│   ├── tmux/         # tmux.conf + manifest
│   ├── tmuxinator/   # default.yml + manifest
│   ├── zsh/          # zshrc 등 + manifest, zshenv.local.example
│   └── ghostty/      # config + manifest
├── fonts/
│   ├── firacode/     # source.json (FiraCode Nerd Font)
│   └── departure-mono/ # source.json (DepartureMono Nerd Font)
└── renames.tsv       # 이름 변경 원장
```

## 빠른 시작

```bash
# PATH에 bin/ 추가
export PATH="$PWD/bin:$PATH"

# 전체 설치 (dry-run으로 먼저 확인)
pcfg install --dry-run

# 전체 설치
pcfg install

# 설치 상태 확인
pcfg list
```

## CLI 사용법

```
pcfg install   [<type>] [<name>] [--force] [--dry-run]
pcfg uninstall [<type>] [<name>] [--restore] [--prune] [--dry-run]
pcfg list      [<type>]
pcfg status
pcfg rename    <type> <old> <new>
pcfg doctor    [--prune]
```

`<type>`: `skills` | `rules` | `hooks` | `mcps` | `plugins` | `settings` | `configs` | `fonts` | `all` (생략 시 `all`)

### 예시

```bash
# 단일 rule 설치
pcfg install rules my-rule

# 단일 config 설치
pcfg install configs tmux

# 플러그인 전체 설치 (Claude Code 마켓플레이스 등록 + 설치)
pcfg install plugins

# 폰트 전체 설치 (다운로드 → ~/Library/Fonts/)
pcfg install fonts

# 단일 폰트 패밀리 설치
pcfg install fonts firacode

# 전체 제거 + 이름변경 잔재 정리 + 백업 복원
pcfg uninstall all --prune --restore

# 이름 변경 (git mv + renames.tsv 기록)
pcfg rename skills old-skill new-skill

# 끊어진 링크 점검 및 정리
pcfg doctor --prune
```

## 설치 방식

| type | 방식 | 대상 |
|------|------|------|
| rules | symlink | `~/.claude/rules/<name>.md` |
| skills | symlink | `~/.claude/skills/<name>` |
| hooks | JSON merge | `~/.claude/settings.json` 의 `hooks` 키 |
| mcps | JSON merge | `~/.claude.json` 의 `mcpServers` 키 |
| plugins | `claude plugin install` | — |
| settings | JSON merge | `~/.claude/settings.json` 최상위 키 |

## settings JSON 형식

`agents/settings/<key>.json` 의 **파일명이 `~/.claude/settings.json` 의 최상위 키**, **파일 내용이 그 값**입니다.
기존 사용자 설정과 `hooks`/`mcps` merge 결과는 그대로 보존됩니다.

```
agents/settings/includeCoAuthoredBy.json   # 내용: false
→ ~/.claude/settings.json 에 "includeCoAuthoredBy": false 삽입
```

`includeCoAuthoredBy: false` 는 Claude Code가 커밋 메시지에 붙이는 `Co-Authored-By` 꼬리말과
PR 본문의 생성 안내 문구를 제거합니다.

## mcps JSON 형식

각 `agents/mcps/<name>.json` 파일에 MCP 서버 정의를 작성합니다.

**원격 http 방식** (Claude Code 권장):

```json
{
  "type": "http",
  "url": "https://example.com/mcp/",
  "headers": {
    "Authorization": "Bearer ${MY_API_KEY}"
  }
}
```

**로컬 stdio 방식**:

```json
{
  "command": "npx",
  "args": ["-y", "@example/mcp-server"],
  "env": {
    "EXAMPLE_API_KEY": "${EXAMPLE_API_KEY}"
  }
}
```

`${VAR}` 형식으로 환경변수를 참조하면, 설치 시 미설정 변수에 대해 경고가 출력됩니다.
현재 환경 또는 `~/.zshenv.local` 중 하나에 정의되어 있으면 경고는 생략됩니다.
실제 값은 파일에 포함하지 않습니다.

## plugins JSON 형식

각 `agents/plugins/<plugin>.json` 파일에 플러그인의 마켓플레이스 정보를 작성합니다.
파일명이 플러그인 ID이며, `claude` 키 아래에 설치 정보를 둡니다.

```json
{
  "claude": {
    "marketplace": "claude-plugins-official",
    "source": "anthropics/claude-plugins-official"
  }
}
```

| 필드 | 설명 |
|------|------|
| `marketplace` | `plugin@marketplace` 형식에 쓰는 마켓플레이스 이름 |
| `source` | 마켓플레이스를 등록할 GitHub repo 또는 URL (`claude plugin marketplace add <source>`). `./`로 시작하면 저장소 루트 기준 로컬 경로 |

### 로컬 플러그인

직접 만든 플러그인은 `agents/plugins/local/`(마켓플레이스 `dotfiles-local`)에 두고, 정의 파일의
`source`를 `"./agents/plugins/local"`로 적습니다. 훅·스크립트와 묶여 동작하는 것만 플러그인으로
만들고, 단독으로 동작하는 스킬은 `agents/skills/`에 둡니다(symlink라 수정이 즉시 반영됨).

원본을 고친 뒤에는 `/plugin marketplace update dotfiles-local` 후
`/plugin update <plugin>@dotfiles-local`로 반영합니다.

설치 시 마켓플레이스가 없으면 자동 등록한 뒤 플러그인을 설치하며, 이미 설치돼 있으면
건너뜁니다(멱등). 설치 상태의 진실원은 에이전트 CLI가 보유하므로 `state.tsv`에는 기록하지
않습니다.

## fonts source.json 형식

각 `fonts/<family>/` 디렉토리에 `source.json` 파일 필수:

```json
{
  "url": "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/FiraCode.zip",
  "version": "3.3.0",
  "files": ["FiraCodeNerdFont-*.ttf"]
}
```

| 필드 | 필수 | 설명 |
|------|------|------|
| `url` | ✓ | 폰트 zip 다운로드 URL |
| `version` | ✓ | 캐시 디렉토리 구분용 버전 문자열 |
| `files` | — | 설치할 파일의 glob 패턴 목록. 생략 시 zip 내 모든 `.ttf`/`.otf` 설치 |

다운로드된 zip은 `~/.cache/pcfg/fonts/<family>/<version>/font.zip`에 캐시됩니다.
버전을 올리면 새 zip을 다운로드하고, 이전 캐시는 그대로 유지됩니다.

설치 경로: macOS → `~/Library/Fonts/`, Linux → `~/.local/share/fonts/`

## configs manifest 형식

각 `configs/<prog>/` 디렉토리에 `manifest` 파일 필수:

```
# source(프로그램 디렉토리 기준 상대경로)   destination
tmux.conf        ~/.config/tmux/tmux.conf
```

## 설치 동작

- **symlink**: 이미 올바른 symlink면 no-op(멱등). 기존 파일은 `.pcfg-bak.<ts>` 백업.
- **merge**: `jq` 로 해당 키만 삽입. 제거 시 그 키만 삭제.
- **font(fonts)**: 이미 설치된 경우 no-op(멱등). 캐시된 zip이 있으면 재사용, 없으면 다운로드 후 패턴 매칭된 파일을 시스템 폰트 디렉토리에 복사.

설치 상태는 `~/.local/state/dotfiles/state.tsv` 에 기록됩니다.
