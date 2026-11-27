#!/usr/bin/env python3
"""문서의 정량 slop 지표를 집계한다. .md / .html 지원.

사용: python3 detect.py 문서경로 [--json]
자체검사: python3 detect.py --selftest
"""
import html
import json
import re
import statistics
import sys

# ── 파싱 ────────────────────────────────────────────────

BOLD_RE = re.compile(r"<(?:strong|b)>|\*\*\S")
EM_RE = re.compile(r"<(?:em|i)>|(?<!\*)\*[^\s*]")


def parse(raw, is_html):
    """(prose_text, full_text, paragraphs, headings, marker_counts, tables) 반환.

    prose_text는 문장 통계용으로 표/코드를 제외한다.
    full_text는 표 안까지 포함한 전체 텍스트로, 수치·hedge 집계에 쓴다.
    """
    markers = {
        "bold": len(BOLD_RE.findall(raw)) if is_html else len(re.findall(r"\*\*[^*\n]+\*\*", raw)),
        "em": len(EM_RE.findall(raw)) if is_html else 0,
    }
    tables = _tables_html(raw) if is_html else _tables_md(raw)

    if is_html:
        body = re.sub(r"<(style|script)\b.*?</\1>", " ", raw, flags=re.S | re.I)
        body = re.sub(r"<!--.*?-->", " ", body, flags=re.S)
        headings = [
            _strip_tags(m.group(1))
            for m in re.finditer(r"<h[1-6][^>]*>(.*?)</h[1-6]>", body, flags=re.S | re.I)
        ]
        # 코드/표/pre는 문장 통계에서 제외한다. 산문만 본다.
        prose = re.sub(r"<(pre|table|code)\b.*?</\1>", " ", body, flags=re.S | re.I)
        blocks = re.findall(
            r"<(?:p|dd|li)[^>]*>(.*?)</(?:p|dd|li)>", prose, flags=re.S | re.I
        )
        paragraphs = [t for t in (_strip_tags(b) for b in blocks) if t]
        text = _strip_tags(prose)
        full = _strip_tags(body)
    else:
        body = re.sub(r"^---\n.*?\n---\n", "", raw, flags=re.S)
        headings = [m.group(1).strip() for m in re.finditer(r"^#{1,6}\s+(.*)$", body, re.M)]
        prose = re.sub(r"```.*?```", " ", body, flags=re.S)
        prose = re.sub(r"^\s*\|.*$", " ", prose, flags=re.M)
        prose = re.sub(r"^#{1,6}\s+.*$", " ", prose, flags=re.M)
        paragraphs = [
            re.sub(r"\s+", " ", p).strip()
            for p in re.split(r"\n\s*\n", prose)
            if p.strip()
        ]
        text = " ".join(paragraphs)
        full = re.sub(r"\s+", " ", re.sub(r"```.*?```", " ", body, flags=re.S))

    return text, full, paragraphs, headings, markers, tables


def _strip_tags(s):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s))).strip()


def _tables_html(raw):
    out = []
    for t in re.findall(r"<table\b.*?</table>", raw, flags=re.S | re.I):
        rows = re.findall(r"<tr\b.*?</tr>", t, flags=re.S | re.I)
        if not rows:
            continue
        cells = [
            [_strip_tags(c) for c in re.findall(r"<t[dh]\b[^>]*>(.*?)</t[dh]>", r, flags=re.S | re.I)]
            for r in rows
        ]
        out.append(cells)
    return out


def _tables_md(raw):
    out, cur = [], []
    for line in raw.splitlines():
        if line.strip().startswith("|"):
            if not re.match(r"^\s*\|[\s|:-]+\|\s*$", line):
                cur.append([c.strip() for c in line.strip().strip("|").split("|")])
        elif cur:
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return out


def sentences(text):
    parts = re.split(r"(?<=[.!?…])\s+|\n+", text)
    return [s.strip() for s in parts if len(s.strip()) >= 5]


# ── 지표 ────────────────────────────────────────────────

# "X가 아니라 Y" 계열 대조 구문. 영어 not-X-but-Y 번역체의 흔적.
CONTRAST = re.compile(r"이 아니라|가 아니라|(?:일|할|들) 뿐|뿐이|뿐입|것만|만 남|않고 |대신 ")
# 불확실성 표지. 하나도 없으면 오히려 비현실적이다.
HEDGE = re.compile(
    r"확인 ?필요|미확인|아직|추정|임시|가능성|것 같|보인다|보입니다|TODO|미정|검토 ?필요|모릅|불확실"
)
# "약 2.6KB" 같은 신뢰감 연출용 정밀 수치. 표 안에도 들어가므로 full_text에서 센다.
PRECISE_NUM = re.compile(r"약 ?\d+(?:\.\d+)?|\d+\.\d+ ?(?:KB|MB|GB|%|배|초|ms)|\d+ ?KB")
# 격언식 마무리로 쓰이는 단정 종결.
ASSERTIVE_END = re.compile(r"(?:입니다|이다|합니다|한다|출발점|기준|원칙|전부|하나)[.]?$")


def measure(path):
    raw = open(path, encoding="utf-8").read()
    is_html = path.lower().endswith((".html", ".htm")) or "<html" in raw[:400].lower() or "<style" in raw[:2000].lower()
    text, full, paragraphs, headings, markers, tables = parse(raw, is_html)
    sents = sentences(text)
    n = max(len(sents), 1)
    per100 = lambda c: round(c * 100 / n, 1)

    lens = [len(s) for s in sents] or [0]
    mean = statistics.mean(lens)
    cv = (statistics.pstdev(lens) / mean) if mean else 0

    endings = {}
    for s in sents:
        key = _ending(s)
        endings[key] = endings.get(key, 0) + 1
    top_end, top_cnt = max(endings.items(), key=lambda kv: kv[1]) if endings else ("", 0)

    bold_paras = sum(1 for p in paragraphs if BOLD_RE.search(p) or "**" in p) if not is_html else None
    if is_html:  # 태그가 제거된 문단에서는 원문 블록으로 다시 센다
        blocks = re.findall(r"<(?:p|dd|li)[^>]*>(.*?)</(?:p|dd|li)>", raw, flags=re.S | re.I)
        blocks = [b for b in blocks if _strip_tags(b)]
        bold_paras = sum(1 for b in blocks if BOLD_RE.search(b))
        paragraphs_n = len(blocks)
    else:
        paragraphs_n = len(paragraphs)

    # 문단 마지막 문장이 짧고 단정형이면 격언식 마무리로 본다
    aph = 0
    for p in paragraphs:
        ps = sentences(p)
        if ps and len(ps[-1]) <= 35 and ASSERTIVE_END.search(ps[-1]):
            aph += 1

    two_col = [t for t in tables if t and statistics.median(len(r) for r in t) == 2]
    long_cells = 0
    for t in tables:
        for r in t:
            for c in r:
                if len(c) > 30:
                    long_cells += 1

    # 3-gram shingle 중복률 = 같은 내용을 섹션마다 다시 쓴 흔적
    shingles = {}
    for s in sents:
        toks = re.findall(r"[\w가-힣/.{}-]+", s)
        for i in range(len(toks) - 2):
            g = " ".join(toks[i : i + 3])
            shingles[g] = shingles.get(g, 0) + 1
    dup_items = sorted(
        ((g, v) for g, v in shingles.items() if v >= 3), key=lambda kv: -kv[1]
    )

    m = {
        "is_html": is_html,
        "sentences": len(sents),
        "paragraphs": paragraphs_n,
        "bold_per_100_sent": per100(markers["bold"]),
        "bold_paragraph_ratio": round(bold_paras / max(paragraphs_n, 1), 2),
        "dash_dot_per_100_sent": per100(text.count("—") + text.count("·") + text.count("–")),
        "arrow_per_100_sent": per100(text.count("→")),
        "paren_per_100_sent": per100(len(re.findall(r"\([^)]{2,}\)", text))),
        "top_ending": top_end,
        "top_ending_share": round(top_cnt / n, 2),
        "sent_len_mean": round(mean, 1),
        "sent_len_cv": round(cv, 2),
        "contrast_per_100_sent": per100(len(CONTRAST.findall(text))),
        "aphorism_ratio": round(aph / max(paragraphs_n, 1), 2),
        "precise_numbers": len(PRECISE_NUM.findall(full)),
        "hedge_per_100_sent": per100(len(HEDGE.findall(full))),
        "tables": len(tables),
        "two_col_tables": len(two_col),
        "long_table_cells": long_cells,
        "dup_3gram": len(dup_items),
        "dup_samples": [f"{g} (x{v})" for g, v in dup_items[:5]],
        "english_only_headings": sum(
            1 for h in headings if h and not re.search(r"[가-힣]", h) and re.search(r"[A-Za-z]", h)
        ),
        "numbered_headings": sum(1 for h in headings if re.match(r"^\d{2}\s*[/.]", h)),
        "repeated_label_sets": _repeated_labels(raw, is_html),
    }
    m["flags"] = evaluate(m)
    return m


def _ending(s):
    core = re.sub(r"[^\w가-힣]+$", "", s)
    if not core:
        return "?"
    if core.endswith("니다"):
        return "~니다"
    if core.endswith(("요", "죠")):
        return "~요"
    if core.endswith(("다", "함", "음", "됨", "임")):
        return "~다/명사형"
    return core[-2:] if re.search(r"[가-힣]", core[-2:]) else "기타"


def _repeated_labels(raw, is_html):
    """'문제/선택/효과'처럼 같은 라벨 세트가 3회 이상 반복되는 템플릿 수."""
    labels = (
        [_strip_tags(m) for m in re.findall(r"<dt[^>]*>(.*?)</dt>", raw, flags=re.S | re.I)]
        if is_html
        else re.findall(r"^\s*(?:\*\*|###+\s*)([^*\n:]{1,12})(?:\*\*|)\s*[:：]?\s*$", raw, re.M)
    )
    counts = {}
    for l in labels:
        l = l.strip()
        if l:
            counts[l] = counts.get(l, 0) + 1
    return sum(1 for v in counts.values() if v >= 3)


# 임계값은 예시 문서(app-order-workspace.html) 실측을 기준으로 잡았다.
# 지표는 신호일 뿐 판정이 아니다. 원인이 있어 넘긴 값은 그대로 두는 것이 맞다.
# rate=True 지표는 산문 문장 수를 분모로 쓰므로 문장이 적으면 신뢰할 수 없다.
MIN_SENTENCES = 20
RULES = [
    ("bold_per_100_sent", ">", 10, "bold 과다", True),
    ("bold_paragraph_ratio", ">", 0.3, "문단마다 bold가 하나씩 균일 분포", True),
    ("dash_dot_per_100_sent", ">", 15, "— / · 과다", True),
    ("arrow_per_100_sent", ">", 15, "→ 장식 과다", True),
    ("paren_per_100_sent", ">", 20, "괄호 삽입구로 부연 밀어넣기", True),
    ("top_ending_share", ">", 0.6, "종결어미 단일화 (리듬 균일)", True),
    ("sent_len_cv", "<", 0.45, "문장 길이 편차 부족 (기계적 리듬)", True),
    ("contrast_per_100_sent", ">", 8, "'X가 아니라 Y' 대조 구문 반복", True),
    ("aphorism_ratio", ">", 0.2, "격언식 마무리 문장", True),
    ("hedge_per_100_sent", "<", 1.5, "불확실성 표지 전무 (미해결 항목 없는 문서)", True),
    ("precise_numbers", ">", 2, "근거 없는 정밀 수치 장식", False),
    ("long_table_cells", ">", 5, "표 셀에 완전한 문장 (불릿이 적합)", False),
    ("dup_3gram", ">", 3, "같은 내용을 여러 섹션에서 재서술", False),
    ("english_only_headings", ">=", 3, "한국어 본문에 영어 전용 제목", False),
    ("numbered_headings", ">", 0, "제로패딩 번호 제목 (01 / Layout)", False),
    ("repeated_label_sets", ">", 0, "완전 대칭 템플릿 반복", False),
]


def evaluate(m):
    out = []
    thin = m["sentences"] < MIN_SENTENCES
    for key, op, thr, label, rate in RULES:
        if rate and thin:
            continue  # 산문이 적어 비율 지표를 신뢰할 수 없다
        v = m[key]
        if (op == ">" and v > thr) or (op == ">=" and v >= thr) or (op == "<" and v < thr):
            out.append({"metric": key, "value": v, "threshold": f"{op}{thr}", "label": label})
    return out


def report(m):
    thin = m["sentences"] < MIN_SENTENCES
    lines = [
        f"문장 {m['sentences']}개 / 문단 {m['paragraphs']}개 / 표 {m['tables']}개",
    ]
    if thin:
        lines.append(
            f"※ 산문 문장이 {MIN_SENTENCES}개 미만이라 비율 지표(rate)는 판정에서 제외했다."
        )
    lines += ["", "지표:"]
    for key, op, thr, _, rate in RULES:
        hit = any(f["metric"] == key for f in m["flags"])
        mark = "-" if (rate and thin) else ("!" if hit else " ")
        lines.append(f"  {mark} {key:<24} {m[key]!s:>8}  (기준 {op}{thr})")
    lines += ["", f"최다 종결어미: {m['top_ending']} ({m['top_ending_share']})"]
    if m["dup_samples"]:
        lines.append("반복 표현: " + " / ".join(m["dup_samples"]))
    lines.append("")
    if m["flags"]:
        lines.append(f"플래그 {len(m['flags'])}건:")
        lines += [f"  - {f['label']} ({f['metric']}={f['value']})" for f in m["flags"]]
    else:
        lines.append("플래그 없음")
    return "\n".join(lines)


def selftest():
    import tempfile, os

    # 두 픽스처 모두 MIN_SENTENCES를 넘겨야 비율 지표가 판정에 들어간다.
    slop = """# 문서

## 01 / Overview

**핵심**은 여기입니다. 이것은 매우 중요한 설계 원칙입니다.
구조는 그렇게 되어 있습니다. 이유는 명확합니다.
전체 분량은 약 2.6KB입니다. 상세 가이드는 8.7KB입니다.
합산하면 약 20.8KB입니다. 수치는 실측입니다.
성실함이 아니라 위치에 맡깁니다. 포인터일 뿐입니다.
편의가 아니라 안전을 택했습니다. 이것이 출발점입니다.

## 02 / Rationale

**중요**한 내용을 다시 정리합니다. 같은 원칙이 다시 적용됩니다.
같은 원칙이 다시 적용됩니다. 같은 원칙이 다시 적용됩니다.
격리는 비용을 줄입니다. 비용은 분량에서 나옵니다.
분량은 컨텍스트를 차지합니다. 차지한 만큼 비중이 낮아집니다.
그래서 계층을 나눴습니다. 계층은 세 개입니다.
정본은 항상 코드와 같은 곳에 둡니다. 원칙은 하나입니다.
"""
    clean = """# 로그 파서

파서는 라인 단위로 읽는다. 실패하면 그 라인만 버리고 넘어간다.
전체를 중단시키지 않는 게 목적.

타임스탬프 형식이 두 종류 섞여 있어서 둘 다 시도한다. 예전 배치가 남긴
포맷인데 언제부터인지는 확인 필요. 정리하려면 원본 배치를 봐야 하는데,
그 배치를 관리하는 팀이 어디인지도 아직 모릅니다.

성능은 아직 측정 안 함. 하루 30만 라인 정도라 문제될 거 같지는 않다.
느려지면 그때 프로파일링하면 된다.

인코딩은 UTF-8 가정. EUC-KR 로그가 들어오면 깨진다.
실제로 한 번 깨진 적 있어서 임시로 예외 처리만 넣어 뒀다.
근본 해결은 로그 생산 쪽에서 해야 한다.

재시도는 없다. 파일이 없으면 그냥 종료.
크론이 5분마다 돌리니까 다음 턴에 잡힌다.
멱등성은 파일명 기준으로만 보장된다. 같은 파일을 두 번 넣으면 두 번 처리된다.
이건 개선 여지가 있다고 본다.
"""
    with tempfile.TemporaryDirectory() as d:
        a, b = os.path.join(d, "slop.md"), os.path.join(d, "clean.md")
        open(a, "w").write(slop)
        open(b, "w").write(clean)
        ms, mc = measure(a), measure(b)

    got = {f["metric"] for f in ms["flags"]}
    for expect in ("precise_numbers", "numbered_headings", "hedge_per_100_sent", "contrast_per_100_sent"):
        assert expect in got, f"slop 문서에서 {expect} 미검출: {sorted(got)}"
    assert ms["dup_3gram"] > 0, "반복 서술 미집계"
    assert "hedge_per_100_sent" not in {f["metric"] for f in mc["flags"]}, "clean 문서 hedge 오탐"
    assert len(mc["flags"]) < len(ms["flags"]), f"clean({len(mc['flags'])}) >= slop({len(ms['flags'])})"
    print(f"selftest OK  (slop {len(ms['flags'])}건 / clean {len(mc['flags'])}건)")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)
    if args[0] == "--selftest":
        selftest()
        sys.exit(0)
    m = measure(args[0])
    print(json.dumps(m, ensure_ascii=False, indent=2) if "--json" in args else report(m))
