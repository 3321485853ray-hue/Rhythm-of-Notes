# -*- coding: utf-8 -*-
"""
insert_figures.py —— 把图片按图号插回 docx 里的【图 X-Y ...（待插入…）】占位处

为什么要有这个脚本：
    文档正文的真源是 .md，docx 是每次重新生成的 —— **手动插进去的图片会被覆盖掉**。
    把"补图"做成可重复的一步：改完 md → build_doc_docx.py → insert_figures.py，
    图按文件名关键字自动就位。

用法：
    python tools/insert_figures.py [图片目录] [docx路径]
    默认图片目录 = C:/Users/33214/Downloads，docx = 作品文档_音符律动.docx

文件名匹配：按图号到关键字表里找（"设计流程.drawio.png" → 图 1-1）。
插入后：占位段原位置放图片（居中），正文只留"图 X-Y　标题"作为图注。
"""

import os
import re
import shutil
import sys

import docx
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Cm, Pt
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(os.path.expanduser("~"), "Downloads")
DEFAULT_DOCX = os.path.join(ROOT, "作品文档_音符律动.docx")

# 图号 → 文件名候选关键字（按顺序匹配，命中即用）
FIG_KEYWORDS = {
    "1-1":  ["设计流程"],
    "2-1":  ["整体系统框图", "系统整体框图"],
    "2-8":  ["按键与编码器"],
    "2-9":  ["声部分配"],
    "2-10": ["加法合成"],
    "2-11": ["包络"],
    "2-12": ["输出级", "混音"],
    "2-13": ["三效果器"],
    "2-14": ["显示链"],
    "2-15": ["FFT"],
    "2-16": ["BLE"],
    "2-17": ["歌曲指引"],
}

MAX_W = Cm(15.5)     # 版心宽度
MAX_H = Cm(19.0)     # 一页正文高度上限


def find_image(img_dir, fig):
    keys = FIG_KEYWORDS.get(fig, [])
    files = [f for f in os.listdir(img_dir)
             if f.lower().endswith((".png", ".jpg", ".jpeg"))]
    for k in keys:
        for f in files:
            if k in f:
                return os.path.join(img_dir, f)
    return None


def set_caption(p, text):
    for r in list(p.runs):
        r._element.getparent().remove(r._element)
    run = p.add_run(text)
    run.font.size = Pt(9)
    run.font.name = "Times New Roman"
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:eastAsia"), "宋体")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER


def main():
    img_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR
    docx_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_DOCX

    doc = docx.Document(docx_path)
    placed, missing = 0, []

    for p in list(doc.paragraphs):
        t = p.text.strip()
        m = re.match(r"^【图\s*(\d+-\d+)　?(.*?)】?$", t)
        if not m:
            continue
        fig, caption = m.group(1), m.group(2).strip()
        caption = re.sub(r"（待插入[^）]*）", "", caption).strip()

        img = find_image(img_dir, fig)
        if not img:
            missing.append(f"图 {fig}")
            continue

        # 在原占位段之前插一个居中段落放图片
        pic_p = p.insert_paragraph_before()
        pic_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = pic_p.add_run()
        try:
            from PIL import Image
            w, h = Image.open(img).size
            ratio = h / float(w)
            width = MAX_W
            if width * ratio > MAX_H:          # 太高 ⇒ 按高度反算宽度
                width = int(MAX_H / ratio) if ratio else MAX_W
            run.add_picture(img, width=width)
        except Exception:
            run.add_picture(img, width=MAX_W)

        # 占位段本身改成图注
        set_caption(p, f"图 {fig}　{caption}")
        placed += 1

    out = docx_path
    try:
        doc.save(out)
    except PermissionError:
        out = docx_path.replace(".docx", "_补图.docx")
        doc.save(out)
        print("⚠️ 原文件被 Word 占用，已另存为:", out)

    print(f"插入 {placed} 张，缺失 {len(missing)} 张")
    if missing:
        print("  缺：", "、".join(missing))
    print("输出:", out)


if __name__ == "__main__":
    main()
