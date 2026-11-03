# -*- coding: utf-8 -*-
"""
gen_frames.py —— 生成联调素材（自检 + 落盘）

    py -3 tools/gen_frames.py

产出（out/ 目录）：
    smoke_stream.bin   176 B / 11 帧小星星第一句（= PROTOCOL.md §9 那条流）
    smoke_writes.txt   手机上一条条粘的十六进制（每行一帧）
    twinkle.sps        整首小星星
    ode.sps            整首欢乐颂
    keymap_writes.txt  键位表下发（2 帧 + DONE）
    rec_read.txt       REC_READ 帧

自检：CRC 标准向量、176 B 长度、§9 五条关键帧逐字节相等、.sps 回读一致。
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bproto as P

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

# PROTOCOL.md §9 的关键帧（文档原文十六进制）
DOC = {
    "PING ": "AA 5A 01 01 00 00 00 00 00 00 00 00 00 00 C5 5F",
    "BEGIN": "AA 5A 01 02 01 08 07 00 62 0B D6 E4 01 00 60 5E",
    "EVENT": "AA 5A 01 10 02 08 00 00 3C 64 F4 01 00 00 FD F3",
    "END  ": "AA 5A 01 03 09 06 07 00 62 0B D6 E4 00 00 24 8C",
    "PLAY ": "AA 5A 01 04 0A 01 00 00 00 00 00 00 00 00 29 A9",
    "STAT ": "AA 5A 01 80 00 04 00 00 00 00 00 00 00 00 C9 92",
}

# 小星星第一句：C C G G A A G(2)，500 ms/音，最后一个 1 s
SMOKE = [(60, 1), (60, 1), (67, 1), (67, 1), (69, 1), (69, 1), (67, 2)]

TWINKLE = [(60, 1), (60, 1), (67, 1), (67, 1), (69, 1), (69, 1), (67, 2),
           (65, 1), (65, 1), (64, 1), (64, 1), (62, 1), (62, 1), (60, 2),
           (67, 1), (67, 1), (65, 1), (65, 1), (64, 1), (64, 1), (62, 2),
           (67, 1), (67, 1), (65, 1), (65, 1), (64, 1), (64, 1), (62, 2),
           (60, 1), (60, 1), (67, 1), (67, 1), (69, 1), (69, 1), (67, 2),
           (65, 1), (65, 1), (64, 1), (64, 1), (62, 1), (62, 1), (60, 2)]

# 欢乐颂（贝多芬第九第 4 乐章主题，简版）
ODE = [(64, 1), (64, 1), (65, 1), (67, 1), (67, 1), (65, 1), (64, 1), (62, 1),
       (60, 1), (60, 1), (62, 1), (64, 1), (64, 1.5), (62, 0.5), (62, 2),
       (64, 1), (64, 1), (65, 1), (67, 1), (67, 1), (65, 1), (64, 1), (62, 1),
       (60, 1), (60, 1), (62, 1), (64, 1), (62, 1.5), (60, 0.5), (60, 2)]

BEAT_MS = 500


def melody_to_events(notes, beat_ms=BEAT_MS):
    evs = []
    for note, beats in notes:
        dur = int(round(beats * beat_ms))
        evs.append(P.ev(0, note, 100, dur))
    # 把 dur 变成"起点差"：delta = 上一个音的时长（单音旋律）
    out = []
    prev_dur = 0
    for e in evs:
        _, n, v, du, f = P.unpack_ev(e)
        out.append(P.ev(prev_dur, n, v, du, f))
        prev_dur = du
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    ok = True

    # ---- 1) CRC 标准向量 ----
    assert P.crc16(b"123456789") == 0x29B1, "CRC16 标准向量不对"
    assert P.crc32(b"123456789") == 0xCBF43926, "CRC32 标准向量不对"
    print("[OK] CRC16/CRC32 标准向量")

    # ---- 2) 冒烟流 ----
    evs = melody_to_events(SMOKE)
    blob = b"".join(evs)
    fr = [P.frame(P.CMD_PING, 0),
          P.frame(P.CMD_BEGIN, 1, __import__("struct").pack("<HIH", len(evs), P.crc32(blob), 1))]
    for i, e in enumerate(evs):
        fr.append(P.frame(P.CMD_EVENT, 2 + i, e))
    fr.append(P.frame(P.CMD_END, 9, __import__("struct").pack("<HI", len(evs), P.crc32(blob))))
    fr.append(P.frame(P.CMD_PLAY, 10, bytes([0])))
    stream = b"".join(fr)
    assert len(stream) == 176, "冒烟流长度 %d != 176" % len(stream)

    # ---- 3) 和文档逐字节对比 ----
    checks = [("PING ", stream[0:16]), ("BEGIN", stream[16:32]), ("EVENT", stream[32:48]),
              ("END  ", stream[144:160]), ("PLAY ", stream[160:176]),
              ("STAT ", P.frame(P.CMD_STATUS, 0, bytes([0, 0, 0, 0])))]
    for name, got in checks:
        want = bytes.fromhex(DOC[name].replace(" ", ""))
        if got != want:
            print("[FAIL] %s 与 PROTOCOL.md §9 不一致\n  got  %s\n  want %s" %
                  (name, got.hex().upper(), want.hex().upper()))
            ok = False
    if ok:
        print("[OK] 冒烟流 %d B，6 条关键帧逐字节等于 PROTOCOL.md §9" % len(stream))
    print("     BEGIN 的 stream_crc32 = 0x%08X" % P.crc32(blob))

    # ---- 4) 回读解析 ----
    parsed = P.parse_frames(stream)
    assert len(parsed) == 11, "回读只解出 %d 帧" % len(parsed)
    print("[OK] 回读解析 11 帧，CRC 全对")

    with open(os.path.join(OUT, "smoke_stream.bin"), "wb") as f:
        f.write(stream)
    with open(os.path.join(OUT, "smoke_writes.txt"), "w", encoding="utf-8") as f:
        for i in range(11):
            f.write(stream[i * 16:(i + 1) * 16].hex().upper() + "\n")
    print("     → out/smoke_stream.bin / out/smoke_writes.txt")

    # ---- 5) 两整首 ----
    for name, melody in (("twinkle", TWINKLE), ("ode", ODE)):
        evs = melody_to_events(melody)
        blob = b"".join(evs)
        sps = P.make_sps(evs, 1)
        evs2, tick = P.parse_sps(sps)
        assert b"".join(evs2) == blob and tick == 1
        with open(os.path.join(OUT, name + ".sps"), "wb") as f:
            f.write(sps)
        print("[OK] %-8s %2d 事件  %4d B  crc32=0x%08X  → out/%s.sps" %
              (name, len(evs), len(sps), P.crc32(blob), name))

    # ---- 6) 键位表帧 ----
    km = P.keymap_frames(P.DEFAULT_KEYMAP, 0)
    with open(os.path.join(OUT, "keymap_writes.txt"), "w", encoding="utf-8") as f:
        for _, fr in km:
            f.write(fr.hex().upper() + "\n")
    print("[OK] 键位表 %d 帧 → out/keymap_writes.txt" % len(km))

    # ---- 7) 录音读回 ----
    rec = P.frame(P.CMD_REC_READ, 0, bytes([0, 0, 0x20, 0x00]))   # offset=0, count=32
    with open(os.path.join(OUT, "rec_read.txt"), "w", encoding="utf-8") as f:
        f.write(rec.hex().upper() + "\n")
    print("[OK] REC_READ 帧 → out/rec_read.txt")

    print("\n全部自检通过" if ok else "\n有自检失败")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
