---
name: retitle
description: 현재 대화를 한국어로 요약해 세션 이름을 바꾼다. 플랜·구현 단계에 해당하면 `[plan] 요약`·`[impl] 요약` 형식을 따른다. 사용자가 `/retitle`로만 호출한다.
disable-model-invocation: true
---

세션 이름은 이 플러그인의 `UserPromptSubmit` hook(`hooks/retitle.py`)이 이미 바꿨다. 도구를 호출하지 말고, hook이 넘긴 「retitle 결과」 문장만 한 줄로 그대로 답한다.

`/retitle` 뒤에 인자를 붙여 호출했으면 hook은 처리하지 않는다. 이름을 바꾸려 하지 말고, `/retitle`은 인자 없이 쓰는 명령이며 이름을 직접 지정하려면 `/rename 이름`을 쓰라고 안내한다.

인자 없이 호출했는데 「retitle 결과」가 컨텍스트에 없으면 hook이 동작하지 않은 것이다. 이름을 바꾸려 하지 말고, `/plugin`에서 session-tools 플러그인이 활성화되어 있는지, 설치 후 Claude Code를 재시작했는지 확인하라고 안내한다.
