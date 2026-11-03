# -*- coding: utf-8 -*-
"""
draw_circuit_diagram.py —— 生成 图 2-7「系统电路连接示意图」PNG

引脚全部取自 fpga_gowin_project/src/top.cst（不是文档里的表，避免两处不一致）。
输出：doc_figs/图2-7_系统电路连接示意图.png
运行：C:\\Users\\33214\\AppData\\Local\\Programs\\Python\\Python312\\python.exe tools/draw_circuit_diagram.py
"""

import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "doc_figs", "图2-7_系统电路连接示意图.png")

W, H = 2800, 2110
F_TITLE = 44
F_BODY = 34
F_SMALL = 30

FONT = "C:/Windows/Fonts/msyh.ttc"
FONT_B = "C:/Windows/Fonts/msyhbd.ttc"

C_LINE = (90, 90, 90)
C_TEXT = (25, 25, 25)
C_SUB = (80, 80, 80)

# 分组配色： (填充, 描边)
IN = ("#EAF2FA", "#3A6EA5")
FPGA = ("#DCE9F8", "#1F4E79")
AUD = ("#FFF1E6", "#B26A00")
VID = ("#F0E9FA", "#7048A5")
WIR = ("#E9F7EE", "#2E7D4F")
PWR = ("#F2F2F2", "#6E6E6E")

HEAD = 104          # 标题区高度（标题 + 分隔线 + 留白）
PAD = 26            # 底部留白
GAP = 36            # 同列相邻框间距


def font(sz, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, sz)


def text(d, xy, s, f, fill=C_TEXT, anchor="lm"):
    d.text(xy, s, font=f, fill=fill, anchor=anchor)


def panel(d, box, title, lines, color, line_h=46):
    x0, y0, x1, y1 = box
    fill, stroke = color
    d.rounded_rectangle(box, radius=16, fill=fill, outline=stroke, width=3)
    text(d, (x0 + 24, y0 + 38), title, font(F_TITLE, True), stroke)
    d.line([(x0 + 18, y0 + 72), (x1 - 18, y0 + 72)], fill=stroke, width=2)
    y = y0 + HEAD - 6
    for ln in lines:
        if isinstance(ln, tuple):
            s, sz, bold, col = ln
            text(d, (x0 + 24, y), s, font(sz, bold), col)
        else:
            text(d, (x0 + 24, y), ln, font(F_BODY), C_TEXT)
        y += line_h


def stack(d, x0, x1, y, items, gap=GAP):
    """按内容自动排高；返回 {key: box} 和列底 y"""
    boxes = {}
    for key, title, lines, color, lh in items:
        h = HEAD + lh * len(lines) + PAD
        box = (x0, y, x1, y + h)
        panel(d, box, title, lines, color, line_h=lh)
        boxes[key] = box
        y = box[3] + gap
    return boxes, y - gap


def arrow(d, p0, p1, label=None, label_up=True, color=C_LINE, double=False):
    x0, y0 = p0
    x1, y1 = p1
    d.line([p0, p1], fill=color, width=4)
    a = 18
    if abs(x1 - x0) >= abs(y1 - y0):
        s = 1 if x1 > x0 else -1
        d.polygon([(x1, y1), (x1 - s * a, y1 - a * 0.62), (x1 - s * a, y1 + a * 0.62)], fill=color)
        if double:
            d.polygon([(x0, y0), (x0 + s * a, y0 - a * 0.62), (x0 + s * a, y0 + a * 0.62)], fill=color)
    else:
        s = 1 if y1 > y0 else -1
        d.polygon([(x1, y1), (x1 - a * 0.62, y1 - s * a), (x1 + a * 0.62, y1 - s * a)], fill=color)
        if double:
            d.polygon([(x0, y0), (x0 - a * 0.62, y0 + s * a), (x0 + a * 0.62, y0 + s * a)], fill=color)
    if label:
        f = font(F_SMALL)
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2 + (-30 if label_up else 34)
        w = d.textlength(label, font=f)
        d.rectangle([mx - w / 2 - 8, my - 22, mx + w / 2 + 8, my + 22], fill="white")
        text(d, (mx, my), label, f, C_SUB, anchor="mm")


def main():
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)

    # ---------------- 左列：输入 ----------------
    left, left_bottom = stack(d, 40, 700, 60, [
        ("keys", "12 键机械琴键阵列", [
            ("白键 C4 D4 E4 F4 G4 A4 B4", F_BODY, True, C_TEXT),
            "C18 D20 F16 F13 D14",
            "D17 B20",
            ("黑键 C#4 D#4 F#4 G#4 A#4", F_BODY, True, C_TEXT),
            "E19 F15 E16 A18 B21",
            "另一端接 GND · FPGA 内部上拉",
        ], IN, 52),
        ("enc", "5 只 EC11 旋转编码器", [
            ("A 相 / B 相 / 按键　公共端接 GND", F_SMALL, False, C_SUB),
            ("主编码器 A13 · C13 · C14　音量 / 音色", 32, False, C_TEXT),
            ("表情　　C17 · B18 · A21　三维表情", 32, False, C_TEXT),
            ("延迟　　C19 · D19 · C20　开关 + 4 档", 32, False, C_TEXT),
            ("混响　　F19 · E17 · F14　开关 + 4 档", 32, False, C_TEXT),
            ("合唱　　D16 · D15 · A19　开关 + 4 档", 32, False, C_TEXT),
        ], IN, 46),
        ("btn", "板载用户按键", [
            "KEY0 AA13　八度循环",
            "KEY1 AB13　进入 / 退出歌曲指引",
            "KEY2 Y12　选歌确认",
        ], IN, 46),
        ("ble", "蓝牙模块 ATK-BLE02", [
            "5 V 供电 · 与 FPGA 共地",
            "TXD → A14（FPGA 接收）",
            "RXD ← B13（FPGA 发送）",
            "115200 8N1，与手机浏览器通信",
        ], WIR, 46),
    ])

    # ---------------- 右列：输出 ----------------
    right, right_bottom = stack(d, 1940, 2760, 60, [
        ("hdmi", "HDMI 连接器", [
            "4 对 TMDS 差分 · 不经外部编码芯片",
            "clk G15/G16　d0 J14/H14",
            "d1 J15/H15　d2 K17/J17",
        ], VID, 46),
        ("disp", "HDMI 显示器", [
            "1280×720 @ 60.6 Hz 实时界面",
        ], VID, 46),
        ("pt", "PT8211-S", [
            "16 bit 右对齐立体声 DAC",
            "BCK 3.125 MHz · WS 48.828 kHz",
        ], AUD, 46),
        ("lmv", "LMV321", [
            "单电源低通滤波",
        ], AUD, 46),
        ("ns", "NS4263 功放", [
            "固定增益 · 由 PA_EN 使能",
            "上电延时约 0.17 s，抑制爆音",
        ], AUD, 46),
        ("hp", "3.5 mm 耳机座", [
            "模拟音频输出",
        ], AUD, 46),
        ("led", "板载 8 位 LED", [
            "音色 / 八度 / 表情维度 / 档位",
        ], VID, 46),
    ])

    # ---------------- 中间：FPGA ----------------
    top, bot = 60, max(left_bottom, right_bottom)
    fill, stroke = FPGA
    d.rounded_rectangle((940, top, 1700, bot), radius=18, fill=fill, outline=stroke, width=4)
    text(d, (970, top + 50), "FPGA 核心板 GW5AST-138C", font(48, True), stroke)
    text(d, (970, top + 100), "Tang Mega 138K Dock · I/O 全为 LVCMOS33", font(F_BODY), C_SUB)
    d.line([(956, top + 136), (1684, top + 136)], fill=stroke, width=2)

    sections = [
        ("① 时钟", [
            "sys_clk V22 ← 50 MHz 有源晶振",
            "内部 PLL → pclk 75 MHz / bclk 375 MHz",
        ]),
        ("② 演奏输入（内部上拉，3 ms 消抖）", [
            "12 音符键 + 5 编码器（A/B/SW 共 15 脚）",
            "板载 KEY0 / KEY1 / KEY2",
        ]),
        ("③ 音频输出", [
            "HP_BCK Y17 · HP_WS AB17 · HP_DIN AA16",
            "PA_EN AB16 → 功放使能（低有效）",
        ]),
        ("④ 视频输出（TMDS 原生直驱）", [
            "clk G15/G16　d0 J14/H14",
            "d1 J15/H15　d2 K17/J17",
        ]),
        ("⑤ 无线通信", [
            "ble_rx A14 ← 模块 TXD",
            "ble_tx B13 → 模块 RXD",
        ]),
        ("⑥ 运行指示", [
            "LEDs[7:0]：T18 R18 R17 P16 / U21 T21 R19 P19",
        ]),
        ("⑦ 内部音频链路（48.828 kHz）", [
            "12 声部 × 32 谐波加法合成（时分复用）",
            "ADSR 包络 → 混音 ÷16 → 延迟 / 混响 / 合唱",
        ]),
        ("⑧ 显示与界面（75 MHz）", [
            "2048 点 FFT → 128 根频谱柱",
            "波形 / 李萨如 / 键盘 / 文字图层合成",
        ]),
    ]
    y = top + 180
    for head, body in sections:
        text(d, (970, y), head, font(F_BODY, True), stroke)
        y += 48
        for ln in body:
            text(d, (992, y), ln, font(F_SMALL), C_TEXT)
            y += 42
        y += 18

    # 底部说明（利用 FPGA 框下的空白）
    y = max(y + 16, bot - 120)
    d.line([(970, y - 26), (1670, y - 26)], fill=stroke, width=2)
    text(d, (970, y), "工程规模：40 余个功能模块 · 约 5.1 万逻辑单元", font(F_SMALL), C_TEXT)
    text(d, (970, y + 42), "三个时钟域：控制 / 音频 50 MHz · 像素 75 MHz", font(F_SMALL), C_TEXT)

    # ---------------- 连线 ----------------
    def mid(k):
        b = {**left, **right}[k]
        return (b[1] + b[3]) / 2

    arrow(d, (700, mid("keys")), (940, mid("keys")), "12 根 · 低有效")
    arrow(d, (700, mid("enc")), (940, mid("enc")), "15 根 A/B/SW")
    arrow(d, (700, mid("btn")), (940, mid("btn")), "板载")
    arrow(d, (700, mid("ble")), (940, mid("ble")), "UART 115200", double=True)

    arrow(d, (1700, mid("hdmi")), (1940, mid("hdmi")), "4 对差分")
    arrow(d, (1700, mid("pt")), (1940, mid("pt")), "I²S 3 线")
    arrow(d, (1700, mid("ns")), (1940, mid("ns")), "PA_EN")
    arrow(d, (1700, mid("led")), (1940, mid("led")), "8 bit")

    ax = 2350
    arrow(d, (ax, right["hdmi"][3]), (ax, right["disp"][1]))
    arrow(d, (ax, right["pt"][3]), (ax, right["lmv"][1]))
    arrow(d, (ax, right["lmv"][3]), (ax, right["ns"][1]))
    arrow(d, (ax, right["ns"][3]), (ax, right["hp"][1]))

    # ---------------- 底部：供电与时钟 ----------------
    b0 = right_bottom + 42
    b1 = b0 + 320
    d.rounded_rectangle((40, b0, 2760, b1), radius=14, fill=PWR[0], outline=PWR[1], width=3)
    text(d, (70, b0 + 40), "供电与时钟", font(F_TITLE, True), PWR[1])

    bh = 64
    y1 = b0 + 122          # 供电主链
    y2 = b0 + 238          # 5 V 分支 / 时钟链

    def chip(x0, x1, y, s, sz=F_SMALL):
        d.rounded_rectangle((x0, y - bh / 2, x1, y + bh / 2), radius=10,
                            fill="white", outline=PWR[1], width=2)
        text(d, ((x0 + x1) / 2, y), s, font(sz), C_TEXT, anchor="mm")

    chip(60, 350, y1, "12 V 1 A 电源适配器")
    arrow(d, (350, y1), (430, y1), color=PWR[1])
    chip(430, 900, y1, "板载 DC-DC 5 V / 3.3 V")
    arrow(d, (900, y1), (980, y1), color=PWR[1])
    chip(980, 1650, y1, "3.3 V 轨：FPGA I/O Bank · DAC · 功放")

    # 5 V 分支：从 DC-DC 给蓝牙模块
    bx = 665
    d.line([(bx, y1 + bh / 2), (bx, y2 - bh / 2)], fill=PWR[1], width=4)
    d.polygon([(bx, y2 - bh / 2), (bx - 11, y2 - bh / 2 - 18), (bx + 11, y2 - bh / 2 - 18)], fill=PWR[1])
    chip(470, 860, y2, "蓝牙模块 5 V")
    text(d, (bx + 20, (y1 + y2) / 2), "5 V", font(F_SMALL), C_SUB)

    chip(1740, 2100, y2, "50 MHz 有源晶振 V22")
    arrow(d, (2100, y2), (2180, y2), color=PWR[1])
    chip(2180, 2740, y2, "sys_clk → PLL（75 / 375 MHz）", 28)

    text(d, (70, b1 - 34),
         "注：12 键、5 编码器与蓝牙串口均取自 J13（SDRAM 扩展座）引脚，该座不插 SDRAM 子板；"
         "按键与编码器公共端接 GND，蓝牙模块由板载 5 V 供电并共地。",
         font(F_SMALL), C_SUB)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, dpi=(200, 200))
    print("输出:", OUT, img.size)


if __name__ == "__main__":
    main()
