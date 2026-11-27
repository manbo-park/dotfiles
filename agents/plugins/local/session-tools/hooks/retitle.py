#!/usr/bin/env python3
"""UserPromptSubmit hook: `/retitle` 입력 시 대화를 한국어로 요약해 세션 제목을 바꾼다.

제목 형식: `[plan] 요약`, `[impl] 요약`, 또는 `요약`(어느 단계에도 해당하지 않을 때).
제목 생성은 `claude -p --model haiku`로 한다.
성공 시에는 프롬프트를 차단하지 않는다. block과 함께 준 sessionTitle은 적용되지 않기 때문이다(2.1.332 실측).
"""
import json
import os
import re
import subprocess
import sys

DONE_PREFIX = "세션 이름을 「"  # 성공 응답 문구. 다음 실행의 요약 입력에서 제외한다

data = json.load(sys.stdin)
# 플러그인 스킬은 `/session-tools:retitle` 형태로도 입력될 수 있다
if not re.match(r"^/(?:[\w-]+:)?retitle\s*$", data.get("prompt", "").strip()):
    sys.exit(0)


def reply(msg, title=None):
    if title:
        out = {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "sessionTitle": title,
                                      "additionalContext": f"retitle 결과: {msg}"}}
    else:
        out = {"decision": "block", "reason": msg,
               "hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "suppressOriginalPrompt": True}}
    print(json.dumps(out, ensure_ascii=False))
    sys.exit(0)


def excerpt(path, limit=12000):
    lines = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            if '"type":"user"' not in raw and '"type":"assistant"' not in raw:  # 대용량 메타 줄은 파싱 생략
                continue
            try:
                e = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(e, dict) or e.get("type") not in ("user", "assistant") \
                    or e.get("isMeta") or e.get("isSidechain"):
                continue
            content = (e.get("message") or {}).get("content")
            if isinstance(content, str):
                texts = [content]
            else:
                texts = [c.get("text", "") for c in content or [] if isinstance(c, dict) and c.get("type") == "text"]
            for t in texts:
                t = t.strip()
                # system-reminder·명령 출력, 이전 /retitle 응답 제외
                if t and not t.startswith(("<", DONE_PREFIX)):
                    lines.append(f"[{e['type']}] {t[:500]}")
    # ponytail: 앞부분(주제 설정)과 뒷부분(최근 진행)만 남김. 긴 세션 요약 품질이 부족하면 구간 샘플링 추가
    text = "\n".join(lines)
    return text if len(text) <= limit else text[: limit // 3] + "\n...\n" + text[-limit * 2 // 3:]


def main():
    convo = excerpt(data.get("transcript_path", ""))
    if not convo:
        reply("요약할 대화가 아직 없어 세션 이름을 바꾸지 않았습니다.")

    # 모델은 값만 고르고, 제목 형식 조립·검증은 코드가 한다 (모델이 대괄호에 주제어를 넣는 문제 방지)
    prompt = f"""아래 Claude Code 대화를 보고 JSON 한 줄만 출력하라. 설명·코드블록 없이.
{{"phase": "...", "summary": "..."}}

- summary: 대화의 주된 작업 주제. 한국어, 명사형으로 끝나는 짧은 구(공백 포함 25자 이내). 코드 식별자·고유명사는 원문 유지. 대괄호를 쓰지 않는다.
- phase: 다음 중 하나.
  - plan: 코드를 바꾸지 않고 설계·플랜 수립이 중심인 대화
  - impl: 코드 수정·구현이 중심인 대화
  - 빈 문자열: 질문·조사·도구 설정 등 위 둘에 해당하지 않거나 판단할 수 없는 경우

<conversation>
{convo}
</conversation>"""

    env = {k: v for k, v in os.environ.items() if not k.startswith(("HERDR_", "TMUX"))}
    try:
        r = subprocess.run(
            ["claude", "-p", "--model", "haiku", "--no-session-persistence", "--safe-mode",
             "--setting-sources", "", "--strict-mcp-config", "--tools", ""],
            input=prompt, capture_output=True, text=True, timeout=60, env=env,
            cwd=os.path.expanduser("~"))
    except subprocess.TimeoutExpired:
        reply("세션 이름 생성이 60초 안에 끝나지 않았습니다.")

    m = re.search(r"\{.*\}", r.stdout, re.S)
    try:
        v = json.loads(m.group(0)) if m else {}
    except ValueError:
        v = {}
    summary = " ".join(str(v.get("summary", "")).split()).strip("[] ")
    if r.returncode != 0 or not summary or len(summary) > 60:
        reply(f"세션 이름 생성에 실패했습니다: {(r.stderr or r.stdout).strip()[:300]}")

    phase = str(v.get("phase", "")).strip().lower()
    title = (f"[{phase}] " if phase in ("plan", "impl") else "") + summary
    reply(f"{DONE_PREFIX}{title}」(으)로 변경했습니다.", title)


try:
    main()
except Exception as ex:  # 크래시로 프롬프트가 스킬에 넘어가 "hook 미등록"으로 잘못 안내되는 것을 막는다
    reply(f"세션 이름 변경 중 오류가 발생했습니다: {type(ex).__name__}: {ex}")
