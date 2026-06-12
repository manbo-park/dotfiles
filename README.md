# dotfiles

AI 코딩 에이전트(Claude Code / Cursor / Codex)의 rules·skills·hooks·mcps 설정과
tmux·zsh·ghostty 등 프로그램 설정 파일, 개발 폰트를 한곳에서 버전 관리하는 dotfiles 저장소입니다.

## 의존성

| 도구 | 용도 | 설치 |
|------|------|------|
| `bash` 4+ | 스크립트 실행 | macOS: `brew install bash` |
| `jq` | JSON merge/remove | `brew install jq` |
| `dasel` 또는 `python3` | TOML 변환 (codex mcps) | `brew install dasel` 또는 시스템 python3 |
| `curl` | 폰트 zip 다운로드 | macOS 기본 포함 |
| `unzip` | 폰트 zip 압축 해제 | macOS 기본 포함 |

> python3 사용 시 별도 패키지 설치 없이 내장 방식으로 변환합니다.

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
│   └── mcps/         # <name>.json [, <name>.skip]
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
# 의존성 설치 (Homebrew 필요)
brew bundle

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
pcfg install   [<type>] [<name>] [--agent <claude|cursor|codex|all>] [--force] [--dry-run]
pcfg uninstall [<type>] [<name>] [--agent ...] [--restore] [--prune] [--dry-run]
pcfg list      [<type>] [--agent ...]
pcfg status
pcfg rename    <type> <old> <new>
pcfg doctor    [--prune]
```

`<type>`: `skills` | `rules` | `hooks` | `mcps` | `configs` | `fonts` | `all` (생략 시 `all`)

### 예시

```bash
# mcps 전체를 Codex에만 설치
pcfg install mcps --agent codex

# 단일 rule을 지원 에이전트 전부에 설치
pcfg install rules my-rule

# 단일 config 설치
pcfg install configs tmux

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

## 지원 매트릭스

| type   | Claude Code | Cursor | Codex |
|--------|-------------|--------|-------|
| rules  | ✓ symlink   | ✓ .mdc 변환 | ✓ AGENTS.md 섹션 |
| skills | ✓ symlink   | ✓ symlink   | ✗ 미지원 |
| hooks  | ✓ JSON merge | ✓ JSON merge | ✗ 미지원 |
| mcps   | ✓ JSON merge (`~/.claude.json`) | ✓ JSON merge (`~/.cursor/mcp.json`) | ✓ TOML merge¹ |

> ¹ Codex는 stdio 방식(`command`/`args`)만 지원합니다. 원격 http 방식의 MCP는 `<name>.skip` 파일에 `codex`를 명시해 제외하세요.

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

### 에이전트 제외 (.skip)

특정 MCP를 일부 에이전트에서 제외하려면 같은 이름의 `.skip` 파일을 추가합니다:

```
agents/mcps/github.skip   # 내용: codex
```

`.skip` 파일에는 제외할 에이전트 이름을 한 줄에 하나씩 작성합니다 (`claude` / `cursor` / `codex`).

### GitHub MCP 설정

`agents/mcps/github.json`은 GitHub 공식 원격 MCP 서버를 설정합니다.
Claude Code와 Cursor에 설치되며, Codex는 stdio 미지원으로 자동 제외됩니다.

**사전 준비 — GitHub PAT 발급 및 설정:**

1. [GitHub 토큰 설정 페이지](https://github.com/settings/personal-access-tokens)에서 fine-grained token 생성
2. 접근할 저장소에 대한 권한 부여
3. `~/.zshenv.local` 생성 후 토큰 입력:

```bash
cp configs/zsh/zshenv.local.example ~/.zshenv.local
# ~/.zshenv.local 열어서 GITHUB_PAT 값 입력
```

`~/.zshenv.local`은 버전 관리에서 제외되는 머신별 파일이며, `~/.zshenv`에서 자동으로 source됩니다. `bin/install` 재실행 시에도 덮어써지지 않습니다.

설치 후 Claude Code에서 `/mcp`로 연결 상태를 확인할 수 있습니다.

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
- **변환(rules-cursor)**: `.md` → frontmatter 래핑 `.mdc` 생성. pcfg 마커로 식별.
- **merge**: `jq` 로 해당 키만 삽입. 제거 시 그 키만 삭제.
- **merge-section(rules-codex)**: `# >>> pcfg:<name> >>>` ~ `# <<< pcfg:<name> <<<` 마커 블록.
- **merge-toml(mcps-codex)**: `[mcp_servers.<name>]` 섹션 삽입.
- **font(fonts)**: 이미 설치된 경우 no-op(멱등). 캐시된 zip이 있으면 재사용, 없으면 다운로드 후 패턴 매칭된 파일을 시스템 폰트 디렉토리에 복사.

설치 상태는 `~/.local/state/dotfiles/state.tsv` 에 기록됩니다.
