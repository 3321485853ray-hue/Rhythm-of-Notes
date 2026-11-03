# -*- coding: utf-8 -*-
"""
build_doc_docx.py —— 把 作品文档_音符律动.md 填进官方模板，生成 作品文档_音符律动.docx

设计要点
--------
* **以模板为底**：一级/二级标题是 Word 自动编号（numPr ilvl=1），必须原样保留；
  脚本只删除模板里的"提示文字"段落（如"400字内（可加重要图）；"），再把正文插进去。
* 正文段落**不带 numPr**，否则会接上自动编号、把 1.1/1.2 的编号吃掉。
* 正文字体按模板正文：Times New Roman + 宋体、小四（sz=24 半磅）、行距 1.5、首行缩进 2 字符。

用法：python tools/build_doc_docx.py [md路径] [输出docx路径]
"""

import copy
import os
import re
import sys

import docx
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Pt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "2658aa94-81d0-454c-b2ac-fc040ff2c01a (1).docx")
MD = os.path.join(ROOT, "作品文档_音符律动.md")
OUT = os.path.join(ROOT, "作品文档_音符律动.docx")

BODY_EA = "宋体"          # 正文字体（东亚）
BODY_LATIN = "Times New Roman"


# ----------------------------------------------------------------------------
# 一、解析 Markdown
# ----------------------------------------------------------------------------
def parse_md(path):
    """返回 [{'level':2/3, 'title':str, 'blocks':[(kind, payload), ...]}, ...]"""
    sections = []
    cur = None
    buf = []

    def flush_para():
        if buf:
            text = " ".join(x.strip() for x in buf).strip()
            if text:
                cur["blocks"].append(("p", text))
            buf.clear()

    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()

    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()

        if s.startswith("### "):
            flush_para()
            cur = {"level": 3, "title": s[4:].strip(), "blocks": []}
            sections.append(cur)
        elif s.startswith("## "):
            flush_para()
            cur = {"level": 2, "title": s[3:].strip(), "blocks": []}
            sections.append(cur)
        elif s.startswith("# "):
            flush_para()          # 文档标题：模板里由"作品名称"承载，忽略
        elif s.startswith(">"):
            i += 1
            continue              # 引用块是给编辑者看的，不进正文
        elif s.startswith("|"):
            flush_para()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(lines[i].strip())
                i += 1
            cells = []
            for r in rows:
                if re.match(r"^\|[\s:\-|]+\|$", r):
                    continue      # 分隔行
                cells.append([c.strip() for c in r.strip("|").split("|")])
            cur["blocks"].append(("table", cells))
            continue
        elif s.startswith("【") and s.endswith("】"):
            flush_para()
            cur["blocks"].append(("fig", s))
        elif s.startswith("- "):
            flush_para()
            cur["blocks"].append(("p", "· " + s[2:].strip()))
        elif s == "":
            flush_para()
        else:
            buf.append(line)
        i += 1

    flush_para()
    return [s for s in sections if s["blocks"]]


# ----------------------------------------------------------------------------
# 二、标题归一化与模板定位
# ----------------------------------------------------------------------------
def norm_title(t):
    t = t.replace("　", "").replace(" ", "").replace("\t", "")
    t = t.split("（")[0].split("(")[0]
    t = t.rstrip("；;：:")
    t = re.sub(r"^\d+(\.\d+)*", "", t)
    return t


def is_heading(p):
    """模板里哪些段落算标题（必须保留）"""
    txt = p.text.strip()
    if p.style.name == "Heading 2":
        return True
    if p.runs and p.runs[0].bold and p.runs[0].font.size == Pt(14):
        return True                                   # 摘要 / 第X部分
    ppr = p._p.pPr
    if ppr is not None and ppr.numPr is not None:
        ilvl = ppr.numPr.ilvl
        if ilvl is not None and ilvl.val == 1:
            return True                               # 1.1 / 2.1 / 3.1 …
        if not txt:
            return True                               # 编号占位空段：**不能删**，删了编号会错位
    if re.match(r"^\d\.\d\.\d\s", txt):
        return True                                   # 2.2.1 这种手写编号
    return False


def clean_heading(p):
    """去掉标题里的模板说明尾巴：' 整体介绍（整个系统实物的正面…）' → '整体介绍'"""
    txt = p.text.strip()
    if not txt:
        return
    new = txt.split("（")[0].strip().rstrip("；;")
    if new and new != txt:
        # 保留第一个 run 的格式，其余 run 删掉
        p.runs[0].text = new
        for r in p.runs[1:]:
            r._element.getparent().remove(r._element)


# ----------------------------------------------------------------------------
# 三、正文排版
# ----------------------------------------------------------------------------
def _set_run_font(run, size_pt=12, bold=None):
    run.font.name = BODY_LATIN
    run.font.size = Pt(size_pt)
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:ascii"), BODY_LATIN)
    rfonts.set(qn("w:hAnsi"), BODY_LATIN)
    rfonts.set(qn("w:eastAsia"), BODY_EA)
    if bold is not None:
        run.font.bold = bold


def _new_para(doc, text="", size=12, bold=False, indent=True,
              align=None, space_before=0, space_after=0):
    p = doc.add_paragraph()
    ppr = p._p.get_or_add_pPr()
    # 行距 1.5（模板正文为 360 twips，auto）
    spacing = OxmlElement("w:spacing")
    spacing.set(qn("w:line"), "360")
    spacing.set(qn("w:lineRule"), "auto")
    if space_before:
        spacing.set(qn("w:before"), str(int(space_before * 20)))
    if space_after:
        spacing.set(qn("w:after"), str(int(space_after * 20)))
    ppr.append(spacing)
    if indent:
        ind = OxmlElement("w:ind")
        ind.set(qn("w:firstLineChars"), "200")
        ind.set(qn("w:firstLine"), "480")
        ppr.append(ind)
    if align is not None:
        p.alignment = align
    if text:
        add_rich_text(p, text, size=size, bold=bold)
    return p


def add_rich_text(p, text, size=12, bold=False):
    """支持 **粗体** 与 `等宽`"""
    for seg in re.split(r"(\*\*.+?\*\*|`.+?`)", text):
        if not seg:
            continue
        if seg.startswith("**") and seg.endswith("**"):
            r = p.add_run(seg[2:-2])
            _set_run_font(r, size, bold=True)
        elif seg.startswith("`") and seg.endswith("`"):
            r = p.add_run(seg[1:-1])
            _set_run_font(r, size, bold=bold or None)
        else:
            r = p.add_run(seg)
            _set_run_font(r, size, bold=(True if bold else None))


def _set_cell_borders(table):
    tbl = table._tbl
    tblPr = tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement("w:%s" % edge)
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), "4")
        el.set(qn("w:space"), "0")
        el.set(qn("w:color"), "000000")
        borders.append(el)
    tblPr.append(borders)


def _new_table(doc, rows):
    ncol = max(len(r) for r in rows)
    table = doc.add_table(rows=len(rows), cols=ncol)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = True
    _set_cell_borders(table)
    for ri, row in enumerate(rows):
        for ci in range(ncol):
            cell = table.cell(ri, ci)
            cell.text = ""
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER if (ri == 0 or ci > 0) else WD_ALIGN_PARAGRAPH.LEFT
            txt = row[ci] if ci < len(row) else ""
            add_rich_text(p, txt, size=9, bold=(ri == 0))
            # 表内段落不要首行缩进
            ppr = p._p.get_or_add_pPr()
            ind = OxmlElement("w:ind")
            ind.set(qn("w:firstLine"), "0")
            ind.set(qn("w:firstLineChars"), "0")
            ppr.append(ind)
            # 单元格垂直居中
            tcPr = cell._tc.get_or_add_tcPr()
            va = OxmlElement("w:vAlign")
            va.set(qn("w:val"), "center")
            tcPr.append(va)
    return table


def _fig_text(raw):
    """【图 2-1　系统整体框图（源文件：doc_figs/02_xx.mmd）】 → 【图 2-1　系统整体框图（待插入：doc_figs/02_xx.mmd）】"""
    m = re.match(r"^【(.*?)（源文件：(.*?)）】$", raw)
    if m:
        return "【%s（待插入：%s）】" % (m.group(1).rstrip("　 "), m.group(2))
    return raw


# ----------------------------------------------------------------------------
# 四、主流程
# ----------------------------------------------------------------------------
def backup_existing(path):
    """覆盖前先把旧 docx 备份到 _docx_backups/ —— 用户手动插进去的图不能被无声吞掉"""
    if not os.path.exists(path):
        return None
    import datetime
    import shutil
    bak_dir = os.path.join(ROOT, "_docx_backups")
    os.makedirs(bak_dir, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dst = os.path.join(bak_dir, "%s-%s.docx" % (os.path.splitext(os.path.basename(path))[0], ts))
    shutil.copy2(path, dst)
    return dst


def count_images(path):
    try:
        return len(docx.Document(path).inline_shapes)
    except Exception:
        return 0


def main():
    md_path = sys.argv[1] if len(sys.argv) > 1 else MD
    out_path = sys.argv[2] if len(sys.argv) > 2 else OUT

    n_img = count_images(out_path)
    bak = backup_existing(out_path)
    if bak:
        print("旧文件已备份:", bak)
        if n_img:
            print("⚠️ 旧文件里有 %d 张图片，重建后需运行 tools/insert_figures.py 自动补回" % n_img)

    sections = parse_md(md_path)
    doc = docx.Document(TEMPLATE)

    # ---- 4.1 保留标题、删除模板提示文字 ----
    anchors = {}          # norm_title -> [paragraph, ...]（按出现顺序）
    for p in list(doc.paragraphs):
        if is_heading(p):
            clean_heading(p)
            key = norm_title(p.text)
            if key:
                anchors.setdefault(key, []).append(p)
        else:
            if p.text.strip():                       # 有文字的都不是标题 ⇒ 提示文字
                p._element.getparent().remove(p._element)

    # ---- 4.2 逐节插入正文 ----
    inserted_blocks = 0
    missing = []
    used = {}
    for sec in sections:
        key = norm_title(sec["title"])
        lst = anchors.get(key, [])
        idx = used.get(key, 0)
        if idx >= len(lst):
            missing.append(sec["title"])
            continue
        anchor = lst[idx]
        used[key] = idx + 1

        prev_el = anchor._p
        for kind, payload in sec["blocks"]:
            if kind == "p":
                el = _new_para(doc, payload)._p
            elif kind == "fig":
                el = _new_para(doc, _fig_text(payload), size=10.5, indent=False,
                               align=WD_ALIGN_PARAGRAPH.CENTER,
                               space_before=3, space_after=3)._p
            elif kind == "table":
                # ⚠️ 两张表紧挨着会被 Word 合并成一张 ⇒ 中间垫一个空段
                if prev_el.tag == qn("w:tbl"):
                    spacer = _new_para(doc, "", size=6, indent=False)._p
                    prev_el.addnext(spacer)
                    prev_el = spacer
                el = _new_table(doc, payload)._tbl
            else:
                continue
            prev_el.addnext(el)
            prev_el = el
            inserted_blocks += 1

    doc.save(out_path)

    # ---- 4.3 自检 ----
    chk = docx.Document(out_path)
    txts = [p.text for p in chk.paragraphs]
    joined = "\n".join(txts)
    residue = re.findall(r"字数内|（可加重要图）|逐级给出|从顶层到底层|不要出现任何涉及学校名称", joined)
    figs = [t for t in txts if t.strip().startswith("【图")]
    print("输出:", out_path)
    print("模板标题数:", sum(1 for p in docx.Document(TEMPLATE).paragraphs if is_heading(p)))
    print("保留标题数:", sum(1 for p in chk.paragraphs if is_heading(p)))
    print("插入块数:", inserted_blocks, " 表格数:", len(chk.tables), " 图占位数:", len(figs))
    print("残留模板提示语:", len(residue))
    if missing:
        print("⚠️ 未匹配到的 Markdown 小节:", missing)
    ok = (not residue) and (not missing)
    print("BUILD_DOCX_OK" if ok else "BUILD_DOCX_WARN")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
