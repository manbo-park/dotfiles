# personal-config

AI 코딩 에이전트(Claude Code / Cursor / Codex)의 rules·skills·hooks·mcps 설정과
tmux·zsh·ghostty 등 프로그램 설정 파일을 한곳에서 버전 관리하는 dotfiles 저장소입니다.

## 의존성

| 도구 | 용도 | 설치 |
|------|------|------|
| `bash` 4+ | 스크립트 실행 | macOS: `brew install bash` |
| `jq` | JSON merge/remove | `brew install jq` |
| `dasel` 또는 `python3` | TOML 변환 (codex mcps) | `brew install dasel` 또는 시스템 python3 |

> python3 사용 시 별도 패키지 설치 없이 내장 방식으로 변환합니다.

## 디렉토리 구조

```
personal-config/
├── bin/
│   ├── pcfg          # 단일 진입 CLI
│   ├── install       # pcfg install 래퍼
│   ├── uninstall     # pcfg uninstall 래퍼
│   └── lib/          # 내부 라이브러리
├── agents/
│   ├── rules/        # <name>.md
│   ├── skills/       # <name>/ (디렉토리)
│   ├── hooks/        # <name>/ (hook.json + scripts)
│   └── mcps/         # <name>.json
├── configs/
│   ├── tmux/         # tmux.conf + manifest
│   ├── zsh/          # zshrc 등 + manifest
│   └── ghostty/      # config + manifest
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
pcfg install   [<type>] [<name>] [--agent <claude|cursor|codex|all>] [--force] [--dry-run]
pcfg uninstall [<type>] [<name>] [--agent ...] [--restore] [--prune] [--dry-run]
pcfg list      [<type>] [--agent ...]
pcfg status
pcfg rename    <type> <old> <new>
pcfg doctor    [--prune]
```

`<type>`: `skills` | `rules` | `hooks` | `mcps` | `configs` | `all` (생략 시 `all`)

### 예시

```bash
# mcps 전체를 Codex에만 설치
pcfg install mcps --agent codex

# 단일 rule을 지원 에이전트 전부에 설치
pcfg install rules my-rule

# 단일 config 설치
pcfg install configs tmux

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
| mcps   | ✓ JSON merge | ✓ JSON merge | ✓ TOML merge |

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

설치 상태는 `~/.local/state/personal-config/state.tsv` 에 기록됩니다.
