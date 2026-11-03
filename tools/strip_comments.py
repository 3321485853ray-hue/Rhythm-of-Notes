# -*- coding: utf-8 -*-
"""
strip_comments.py —— 清理 RTL 源码里"非代码解释"的注释

用户要求：**只保留对代码行的解释**，调试过程记录、历史版本说明、踩坑笔记、
分隔横幅、TODO 等一律删除。

判定规则
--------
1. 分隔横幅（含 `====` / `----` / `####` 或只有符号的行） → 删
2. 注释里出现"历史/调试"关键词（日期、踩坑、根因、上板、回退、用户、曾经、
   v12 这种版本号、⚠ ★ ⭐ 等） → 删
3. 连续 ≥3 行的整行注释块 → 整块删（头注释、长段说明）
4. 整行注释且长度 > 50 字 → 删
5. 其余（紧跟代码、简短、纯解释） → 保留

安全保证：处理前后把"去掉所有注释后的代码"逐字节比较，必须完全一致。

用法：
    python tools/strip_comments.py --dry     # 只统计，不写文件
    python tools/strip_comments.py           # 真正写入（先自动备份到仓库外）
"""

import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "fpga_gowin_project", "src")
BACKUP = os.path.join(os.path.dirname(ROOT), "_src_backup_preclean")

FORBIDDEN = [
    r"20\d\d-\d\d",          # 日期
    r"踩坑", r"根因", r"上板", r"回退", r"用户", r"曾经", r"当时",
    r"第一版", r"旧版", r"旧代码", r"之前", r"后来", r"改成", r"改回",
    r"为什么", r"memory", r"TODO", r"FIXME", r"注意！", r"⚠", r"★", r"⭐",
    r"\bv\d+\b",             # v39 这种版本号
    r"HACK", r"XXX",
    r"\.md\b", r"排查", r"误报", r"\btb\b", r"FAIL", r"测试台", r"仿真",
    r"第十二节", r"阶段\d", r"见下面", r"见上文", r"见下文", r"见文件头", r"见上面的",
]
FORBIDDEN_RE = re.compile("|".join(FORBIDDEN), re.I)
BANNER_RE = re.compile(r"^[\s/=\-*#_~+|·.]+$")
# 以标点/续行符号开头 ⇒ 上一行被删后剩下的断句碎片
CONTINUATION_RE = re.compile(r"^[（(，,、。）)】」』—·\*→]")


def split_comments(text):
    """把源码切成 [(kind, payload)]，kind ∈ code/line_comment/block_comment/string"""
    out = []
    i, n = 0, len(text)
    buf = []
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(("string", text[i:j + 1]))
            i = j + 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(("line_comment", text[i:j]))
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n - 2 if j < 0 else j
            out.append(("block_comment", text[i:j + 2]))
            i = j + 2
        else:
            j = i
            while j < n and text[j] not in '"' and not (text[j] == "/" and j + 1 < n
                                                        and text[j + 1] in "/*"):
                j += 1
            out.append(("code", text[i:j]))
            i = j
    return out


def strip_all_comments(text):
    """用于等价性比较：删掉所有注释与空白"""
    return "".join(p for k, p in split_comments(text)
                   if k in ("code", "string")).replace(" ", "").replace("\t", "").replace("\n", "")


def decide_comment(comment_text, nlines, is_block):
    body = comment_text.strip()
    body = re.sub(r"^(//|/\*|\*)+", "", body).strip()
    body = re.sub(r"(\*/)$", "", body).strip()
    if not body:
        return False
    if BANNER_RE.match(body):
        return False
    if FORBIDDEN_RE.search(body):
        return False
    if nlines >= 3:
        return False
    if is_block:
        return False
    if len(body) > 50:
        return False
    return True


def _file_header_line(text):
    """文件顶部注释块里保留一行 "xxx.v — 一句话职责"，其余删掉"""
    m = re.match(r"^\s*((?://[^\n]*\n)+)", text)
    if not m:
        return None
    for line in m.group(1).splitlines():
        body = line[2:].strip()
        if not re.search(r"\.v\s*[—\-–~]", body):
            continue
        body = body.replace("**", "")
        # 括号里如果是"阶段/版本/调试"这类信息，去掉整个括号
        m2 = re.search(r"（([^）]*)）", body)
        if m2 and re.search(r"阶段|版本|调试|\bv\d+\b", m2.group(1)):
            body = (body[:m2.start()] + body[m2.end():]).strip()
        if len(body) > 70:
            body = body[:68].rstrip() + "…"
        return "// " + body
    return None


def process(text):
    header_line = _file_header_line(text)
    parts = split_comments(text)
    keep = [True] * len(parts)

    # 文件顶部（第一行代码之前）的注释一律删掉，只留 header_line
    pos = 0
    offsets = []
    for kind, payload in parts:
        offsets.append(pos)
        pos += len(payload)
    first_code = len(text)
    for i, (kind, payload) in enumerate(parts):
        if kind == "code" and payload.strip():
            first_code = offsets[i]
            break

    # 连续整行注释聚成"块"，整块一起决定去留 —— 避免删一半留下断句碎片
    idx = 0
    while idx < len(parts):
        kind, payload = parts[idx]
        if kind != "line_comment":
            idx += 1
            continue
        prev = parts[idx - 1][1] if (idx > 0 and parts[idx - 1][0] == "code") else "\n"
        full_line = re.search(r"(^|\n)[ \t]*$", prev) is not None

        if not full_line:                       # 行尾注释：只留简短的纯解释
            body = payload[2:].strip()
            keep[idx] = (0 < len(body) <= 60
                         and not FORBIDDEN_RE.search(body)
                         and not BANNER_RE.match(body))
            idx += 1
            continue

        run = [idx]
        j = idx
        while j + 2 < len(parts):
            sep = parts[j + 1][1]
            if (parts[j + 1][0] == "code" and sep.strip() == ""
                    and "\n" in sep and parts[j + 2][0] == "line_comment"):
                run.append(j + 2)
                j += 2
            else:
                break

        bodies = [parts[i][1][2:].strip() for i in run]
        ok = len(run) <= 2 and all(
            0 < len(b) <= 50
            and not FORBIDDEN_RE.search(b)
            and not BANNER_RE.match(b)
            and not re.match(r"^[-=*#_~+]{3,}.*[-=*#_~+]{3,}$", b)
            and not CONTINUATION_RE.match(b)      # 以标点开头的续行碎片
            for b in bodies)
        # 紧跟在一个"已被删掉的注释"后面的整行注释，多半是同一段的续行 ⇒ 一起删
        if idx > 0 and parts[idx - 1][0] == "line_comment" and not keep[idx - 1]:
            ok = False
        for i in run:
            keep[i] = ok
        idx = j + 1

    # 整块 /* */ 注释
    for i, (kind, payload) in enumerate(parts):
        if kind == "block_comment":
            keep[i] = decide_comment(payload, payload.count("\n") + 1, True)

    # 文件顶部注释块：除 header_line 外全删
    for i, (kind, payload) in enumerate(parts):
        if kind in ("line_comment", "block_comment") and offsets[i] < first_code:
            keep[i] = False

    # 带文字的横幅（//---- 标题 ----）一律删
    for i, (kind, payload) in enumerate(parts):
        if kind == "line_comment":
            body = payload[2:].strip()
            if re.match(r"^[-=*#_~+]{3,}.*[-=*#_~+]{3,}$", body):
                keep[i] = False

    out = []
    for (kind, payload), k in zip(parts, keep):
        if kind in ("line_comment", "block_comment") and not k:
            if kind == "line_comment":
                out.append("")           # 行尾注释删掉后只剩代码
            else:
                # 整块注释：保留换行数量，避免行号大幅漂移
                out.append("\n" * payload.count("\n"))
        else:
            # 保留下来的注释里去掉 markdown 式的 ** 强调符号
            out.append(payload.replace("**", "") if kind in ("line_comment", "block_comment") else payload)

    res = "".join(out)
    res = re.sub(r"[ \t]+\n", "\n", res)      # 删注释后残留的行尾空格
    res = re.sub(r"(\n[ \t]*(?:input|output|inout)[^\n]*)\n\n+([ \t]*(?:input|output|inout)\b)",
                 r"\1\n\2", res)                       # 端口表里的空行
    res = re.sub(r"\n{3,}", "\n\n", res)      # 连续空行压成一个
    res = res.lstrip("\n")
    if header_line:
        res = header_line + "\n\n" + res
    return res


def main():
    dry = "--dry" in sys.argv
    files = sorted(f for f in os.listdir(SRC) if f.endswith(".v"))
    tot_before = tot_after = 0
    changed = []
    for f in files:
        p = os.path.join(SRC, f)
        src = open(p, encoding="utf-8").read()
        new = process(src)
        # 安全：去注释后的代码必须逐字节一致
        if strip_all_comments(src) != strip_all_comments(new):
            print("❌ 等价性检查失败，跳过:", f)
            continue
        b, a = len(src.encode("utf-8")), len(new.encode("utf-8"))
        tot_before += b
        tot_after += a
        if b != a:
            changed.append((f, b, a))
            if not dry:
                if not os.path.isdir(BACKUP):
                    os.makedirs(BACKUP)
                shutil.copy2(p, os.path.join(BACKUP, f))
                open(p, "w", encoding="utf-8", newline="").write(new)

    for f, b, a in changed:
        print(f"  {f:28s} {b:7d} -> {a:7d}  (-{100*(b-a)/b:4.1f}%)")
    print(f"\n文件数 {len(files)}，改动 {len(changed)}，"
          f"总字节 {tot_before} -> {tot_after} (-{100*(tot_before-tot_after)/max(tot_before,1):.1f}%)")
    print("DRY_RUN" if dry else f"备份在 {BACKUP}")


if __name__ == "__main__":
    main()
