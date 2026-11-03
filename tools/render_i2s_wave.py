# -*- coding: utf-8 -*-
"""
render_i2s_wave.py —— 把 ModelSim 导出的 i2s.vcd 画成逻辑分析仪风格的时序图
输出：doc_figs/图3-12_I2S时序波形.png
用法：python tools/render_i2s_wave.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VCD = os.path.join(ROOT, "_lab", "i2s_wave", "i2s.vcd")
OUT = os.path.join(ROOT, "doc_figs", "图3-12_I2S时序波形.png")

W, H = 2800, 1500
FONT = "C:/Windows/Fonts/msyh.ttc"
FONT_B = "C:/Windows/Fonts/msyhbd.ttc"
C_TRACE = (28, 78, 140)
C_GRID = (225, 228, 232)
C_TEXT = (25, 25, 25)
C_SUB = (95, 95, 95)
C_ANNO = (176, 106, 0)


def font(sz, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, sz)


def parse_vcd(path):
    """返回 {'bck': [(t_ps, 0/1), ...], ...}"""
    ids, names = {}, {}
    sig = {}
    t = 0
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            s = line.strip()
            if s.startswith("$var"):
                p = s.split()
                if len(p) >= 5:
                    ids[p[3]] = p[4]
                    names[p[4]] = p[3]
                    sig[p[4]] = []
            elif s.startswith("#"):
                t = int(s[1:])
            elif s and s[0] in "01xz":
                vid = s[1:].strip()
                if vid in ids:
                    sig[ids[vid]].append((t, int(s[0]) if s[0] in "01" else 0))
    return sig


def level_at(changes, t):
    v = 0
    for tt, vv in changes:
        if tt <= t:
            v = vv
        else:
            break
    return v


def draw_trace(d, changes, x0, x1, t0, t1, y_hi, y_lo, color=C_TRACE, width=4):
    """按"先水平、后竖直"画数字波形"""
    cur = level_at(changes, t0)
    x_prev = x0
    pts = [(x0, y_hi if cur else y_lo)]
    for t, v in changes:
        if t <= t0:
            continue
        if t > t1:
            break
        x = x0 + (t - t0) * (x1 - x0) / (t1 - t0)
        pts.append((x, y_hi if cur else y_lo))     # 水平到跳变点
        cur = v
        pts.append((x, y_hi if cur else y_lo))     # 竖直跳变
        x_prev = x
    pts.append((x1, y_hi if cur else y_lo))
    d.line(pts, fill=color, width=width, joint="curve")


def main():
    sig = parse_vcd(VCD)
    bck, lrck, din = sig["bck"], sig["lrck"], sig["din"]

    # 取 20 µs 之后第一个 WS 上升沿作为窗口起点
    edges = [t for i, (t, v) in enumerate(lrck) if v == 1 and i > 0 and lrck[i - 1][1] == 0 and t > 10_000_000]
    t0 = float(edges[0])
    frame = 20_480_000.0            # 20.48 µs（VCD 时间单位是 ps）
    t1 = t0 + frame

    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)

    X0, X1 = 470, 2720
    rows = [("HP_WS", lrck, 330), ("HP_BCK", bck, 640), ("HP_DIN", din, 950)]
    AMP = 105

    # 背景网格：每 5 µs
    for k in range(5):
        x = X0 + k * (X1 - X0) / 4
        d.line([(x, 210), (x, 1120)], fill=C_GRID, width=2)
        us = k * frame / 4 / 1e6
        d.text((x, 1148), "%.2f µs" % us, font=font(30), fill=C_SUB, anchor="mm")

    for name, ch, y in rows:
        d.text((60, y), name, font=font(38, True), fill=C_TEXT, anchor="lm")
        d.line([(X0, y - AMP), (X0, y + AMP)], fill=C_GRID, width=2)
        draw_trace(d, ch, X0, X1, t0, t1, y - AMP + 12, y + AMP - 12)

    # 帧边界
    for x in (X0, X1):
        d.line([(x, 200), (x, 1120)], fill=(200, 60, 60), width=3)
    # 左右声道分界
    xm = X0 + (X1 - X0) / 2
    d.line([(xm, 200), (xm, 1120)], fill=(200, 60, 60), width=2)

    # 标题与标注
    d.text((60, 60), "I2S 输出时序（BCK / WS / DIN）", font=font(52, True), fill=C_TEXT)
    d.text((60, 130), "RTL 仿真波形（ModelSim，sys_clk = 50 MHz）", font=font(34), fill=C_SUB)
    d.text((X1, 60), "1 帧 = 64 × BCK", font=font(34, True), fill=C_ANNO, anchor="ra")

    # 时长箭头
    ay = 1195
    d.line([(X0, ay), (X1, ay)], fill=C_ANNO, width=3)
    for x in (X0, X1):
        d.line([(x, ay - 14), (x, ay + 14)], fill=C_ANNO, width=3)
    d.text(((X0 + X1) / 2, ay + 40), "WS 周期 20.48 µs（48.828 kHz）", font=font(34, True), fill=C_ANNO, anchor="mm")

    # 说明
    notes = [
        "BCK = 3.125 MHz（周期 320 ns），每个 WS 半周期 32 个 BCK，整帧 64 个",
        "DIN 在每个半帧的前 16 个 BCK 保持 0、后 16 个 BCK 依次送出 16 位数据 → 右对齐（Right-Justified），MSB 先出",
        "图中样本 0xA55A 为交替位型，便于逐位核对",
    ]
    y = 1300
    for n in notes:
        d.text((70, y), "· " + n, font=font(31), fill=C_TEXT)
        y += 50

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, dpi=(200, 200))
    print("输出:", OUT, img.size, "| 窗口起点 %.3f µs" % (t0 / 1000))

    # 自检：数窗口内的 BCK 上升沿
    n = sum(1 for i, (t, v) in enumerate(bck) if v == 1 and i > 0 and bck[i - 1][1] == 0 and t0 <= t < t1)
    print("窗口内 BCK 上升沿数 =", n, "（应为 64）")


if __name__ == "__main__":
    main()
