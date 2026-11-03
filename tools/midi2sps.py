# -*- coding: utf-8 -*-
"""
midi2sps.py —— MIDI 文件 → .sps 曲谱包（协议 §8.1）

    py -3 tools/midi2sps.py 输入.mid [-o 输出.sps] [--tick 1] [--maxpoly 4]

为什么自己解析 SMF 而不是用 mido：这个环境里没装 mido，而我们要的只是
"note on/off + tempo"，标准 MIDI 文件格式（SMF）那点结构手写 150 行够了，
少一个依赖，换台机器也能跑。

处理规则（和协议一致）：
  · 合并所有轨道，按 (起音时刻, 音高) 排序
  · tick → ms：按 tempo map 逐段换算（多 tempo 也支持）
  · delta = 相对**上一个事件的起音时刻**；同刻和弦 delta = 0
  · 超过 65535 tick 的空档插 NOOP（note=0xFF）
  · ``--maxpoly`` 只保留同时发声数不超过 N 的简化和弦（超出时丢最晚开始的音），
    因为板子上曲谱只有 4 个专用声部
"""

import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bproto as P


def read_varint(data, i):
    v = 0
    while True:
        b = data[i]
        i += 1
        v = (v << 7) | (b & 0x7F)
        if not (b & 0x80):
            return v, i


def parse_smf(data):
    """返回 (division, [(abs_tick, kind, a, b), ...])  kind: 'tempo'/'on'/'off'"""
    if data[:4] != b"MThd":
        raise ValueError("不是 MIDI 文件")
    hdr_len = struct.unpack(">I", data[4:8])[0]
    fmt, ntrks, division = struct.unpack(">HHH", data[8:14])
    if division & 0x8000:
        raise ValueError("不支持 SMPTE 时间格式的 MIDI")
    i = 8 + hdr_len
    events = []
    for _ in range(ntrks):
        if data[i:i + 4] != b"MTrk":
            break
        trk_len = struct.unpack(">I", data[i + 4:i + 8])[0]
        j = i + 8
        end = j + trk_len
        t = 0
        status = 0
        while j < end:
            dt, j = read_varint(data, j)
            t += dt
            b = data[j]
            if b & 0x80:
                status = b
                j += 1
            # running status：沿用上一个 status
            if status == 0xFF:
                mtype = data[j]; j += 1
                ln, j = read_varint(data, j)
                if mtype == 0x51 and ln == 3:
                    us = (data[j] << 16) | (data[j + 1] << 8) | data[j + 2]
                    events.append((t, "tempo", us, 0))
                elif mtype == 0x2F:
                    break
                j += ln
            elif status in (0xF0, 0xF7):
                ln, j = read_varint(data, j)
                j += ln
            else:
                hi = status & 0xF0
                n = 2 if hi in (0x80, 0x90, 0xA0, 0xB0, 0xE0) else 1
                d1 = data[j]
                d2 = data[j + 1] if n == 2 else 0
                j += n
                if hi == 0x90:
                    if d2 > 0:
                        events.append((t, "on", d1, d2))
                    else:
                        events.append((t, "off", d1, 0))
                elif hi == 0x80:
                    events.append((t, "off", d1, 0))
        i = end
    return division, events


def build_tempo_map(events):
    """[(tick, us_per_quarter), ...]，首项为 (0, 500000)"""
    mp = [(0, 500000)]
    for t, k, a, b in sorted(events):
        if k == "tempo" and a > 0:
            mp.append((t, a))
    # 去重（同一 tick 多次改 tempo 取最后一个）
    out = []
    for tick, us in mp:
        if out and out[-1][0] == tick:
            out[-1] = (tick, us)
        else:
            out.append((tick, us))
    return out


def tick_to_ms(tick, division, tmap):
    """按分段 tempo 积分"""
    ms = 0.0
    for k in range(len(tmap)):
        t0, us = tmap[k]
        t1 = tmap[k + 1][0] if k + 1 < len(tmap) else None
        if tick <= t0:
            break
        seg_end = tick if t1 is None else min(tick, t1)
        ms += (seg_end - t0) * us / division / 1000.0
        if t1 is None or tick <= t1:
            break
    return ms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mid")
    ap.add_argument("-o", "--out")
    ap.add_argument("--tick", type=int, default=1, help="tick_ms（1..10）")
    ap.add_argument("--maxpoly", type=int, default=4)
    ap.add_argument("--min-dur", type=int, default=20, help="最短音符 ms（过滤装饰音）")
    args = ap.parse_args()

    data = open(args.mid, "rb").read()
    division, events = parse_smf(data)
    tmap = build_tempo_map(events)

    #---- 配对 note on/off ----
    open_notes = {}
    notes = []
    for t, k, a, b in sorted(events, key=lambda e: (e[0], 0 if e[1] == "off" else 1)):
        if k == "on":
            open_notes.setdefault(a, []).append((t, b))
        elif k == "off":
            st = open_notes.get(a)
            if st:
                t0, vel = st.pop(0)
                notes.append((tick_to_ms(t0, division, tmap),
                              tick_to_ms(t, division, tmap) - tick_to_ms(t0, division, tmap),
                              a, vel))
    if not open_notes and not notes:
        print("没有解析到音符"); return 2

    #---- 声部限制：超过 maxpoly 时丢最晚开始的音 ----
    notes.sort(key=lambda n: (n[0], n[2]))
    if args.maxpoly > 0:
        kept = []
        for n in notes:
            t = n[0]
            active = [k for k in kept if k[0] <= t < k[0] + k[1]]
            if len(active) >= args.maxpoly:
                continue
            kept.append(n)
        dropped = len(notes) - len(kept)
        notes = kept
        if dropped:
            print("  提示：超过 %d 声部，丢了 %d 个音" % (args.maxpoly, dropped))

    notes.sort(key=lambda n: n[0])

    #---- 组事件 ----
    evs = []
    last_start = 0
    for start, dur, note, vel in notes:
        if dur < args.min_dur:
            continue
        delta = int(round(start - last_start))
        if delta < 0:
            delta = 0
        while delta > 65535:
            evs.append(P.ev(65535, 0xFF, 0, 1))     # NOOP 切开
            last_start += 65535
            delta -= 65535
        evs.append(P.ev(delta, note, min(127, max(1, vel)), max(1, int(round(dur)))))
        last_start = start

    tick = max(1, min(10, args.tick))
    sps = P.make_sps(evs, tick)
    out = args.out or (os.path.splitext(args.mid)[0] + ".sps")
    open(out, "wb").write(sps)

    total_ms = last_start
    print("%s → %s" % (os.path.basename(args.mid), out))
    print("  %d 个音符，%.1f 秒，tick=%d ms，文件 %d 字节" %
          (len(evs), total_ms / 1000.0, tick, len(sps)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
