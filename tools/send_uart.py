# -*- coding: utf-8 -*-
"""
send_uart.py —— PC 串口直发 / 收状态帧（绕开蓝牙，验 FPGA 侧全部逻辑）

    py -3 tools/send_uart.py COM5 --ping
    py -3 tools/send_uart.py COM5 --smoke
    py -3 tools/send_uart.py COM5 --sps tools/out/twinkle.sps --loop 0
    py -3 tools/send_uart.py COM5 --keymap
    py -3 tools/send_uart.py COM5 --rec 32 --save tools/out/rec.sps

接线：USB-TTL 的 TX → FPGA ble_rx(A14)，RX → FPGA ble_tx(B13)，共地，3.3 V。
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bproto as P

try:
    import serial
except ImportError:
    print("需要 pyserial：py -3 -m pip install pyserial")
    sys.exit(2)


STATUS_NAMES = {
    P.ST_OK: "OK", P.ST_ERR_FRAME_CRC: "ERR_FRAME_CRC", P.ST_ERR_LEN: "ERR_LEN",
    P.ST_ERR_CMD: "ERR_CMD", P.ST_ERR_STATE: "ERR_STATE",
    P.ST_ERR_OVERFLOW: "ERR_OVERFLOW", P.ST_ERR_STREAM_CRC: "ERR_STREAM_CRC",
    P.ST_ERR_COUNT: "ERR_COUNT", P.ST_PLAY_STARTED: "EVT_PLAY_STARTED",
    P.ST_PLAY_DONE: "EVT_PLAY_DONE", P.ST_STOPPED: "EVT_STOPPED",
    P.ST_REC_START: "EVT_REC_START", P.ST_REC_END: "EVT_REC_END",
}


def recv_reader(ser, state, seconds):
    """在 seconds 秒内持续读串口：滑动窗口搜 AA5A、校 CRC16、打印"""
    t_end = time.time() + seconds
    buf = bytearray()
    rec_events = []
    while time.time() < t_end:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            buf.extend(chunk)

        while True:
            i = buf.find(b"\xAA\x5A")
            if i < 0:
                if len(buf) > 1:
                    del buf[:-1]          # 只留最后 1 字节（可能是半个 SOF）
                break
            del buf[:i]
            if len(buf) < 16:
                break
            fr = bytes(buf[:16])
            if P.crc16(fr[2:14]) == (fr[14] | (fr[15] << 8)):
                del buf[:16]
                cmd, pay = fr[3], fr[6:6 + fr[5]]
                if cmd == P.CMD_STATUS:
                    code = pay[0]
                    arg = pay[1] | (pay[2] << 8)
                    echo = pay[3] if len(pay) > 3 else 0
                    print("  ← STATUS %-16s arg=%d echo=%d" %
                          (STATUS_NAMES.get(code, "0x%02X" % code), arg, echo))
                    state["last"] = (code, arg)
                elif cmd == P.CMD_RECDATA:
                    rec_events.append(bytes(pay))
                    d, n, v, du, f = P.unpack_ev(pay)
                    print("  ← RECDATA delta=%d note=%d vel=%d dur=%d" % (d, n, v, du))
                else:
                    print("  ← cmd=0x%02X len=%d" % (cmd, len(pay)))
            else:
                del buf[:1]               # CRC 错：丢 1 字节重新找
    state["rec"] = rec_events


def send_frames(ser, frames, gap):
    for seq, fr in frames:
        ser.write(fr)
        ser.flush()
        time.sleep(gap)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--gap", type=float, default=0.005, help="帧间隔秒（默认 5 ms）")
    ap.add_argument("--ping", action="store_true")
    ap.add_argument("--smoke", action="store_true", help="发 out/smoke_stream.bin（176 B）")
    ap.add_argument("--sps", help="发一份 .sps 曲谱")
    ap.add_argument("--loop", type=int, default=0,
                    help="再重复次数：0=只放一遍（默认），1=放两遍，255=无限循环")
    ap.add_argument("--keymap", nargs="?", const="default", help="发键位表（可给 12 个逗号分隔的 MIDI 值）")
    ap.add_argument("--rec-begin", type=int, nargs="?", const=1, metavar="TICK",
                    help="开始录制（tick_ms，默认 1）。之后弹琴，再用 --rec-stop")
    ap.add_argument("--rec-stop", action="store_true", help="停止录制，打印录到的事件数")
    ap.add_argument("--rec", type=int, default=0, help="读回 N 条录音事件（须先 --rec-begin/--rec-stop）")
    ap.add_argument("--save", help="把读回的事件存成 .sps")
    ap.add_argument("--listen", type=float, default=1.5, help="发完监听几秒")
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    ser = serial.Serial(args.port, args.baud, timeout=0.05)
    time.sleep(0.2)
    ser.reset_input_buffer()

    state = {}
    seq = 0

    if args.ping:
        print("发 PING")
        ser.write(P.frame(P.CMD_PING, 0)); ser.flush()
        recv_reader(ser, state, 1.0)

    if args.smoke:
        path = os.path.join(here, "out", "smoke_stream.bin")
        data = open(path, "rb").read()
        print("发冒烟流 %d B / %d 帧" % (len(data), len(data) // 16))
        for i in range(0, len(data), 16):
            ser.write(data[i:i + 16]); ser.flush(); time.sleep(args.gap)
        recv_reader(ser, state, args.listen)

    if args.sps:
        data = open(args.sps, "rb").read()
        frames = P.frames_for_sps(data, seq, args.loop)
        evs, tick = P.parse_sps(data)
        print("发曲谱 %s：%d 事件，tick=%d ms，共 %d 帧" %
              (os.path.basename(args.sps), len(evs), tick, len(frames)))
        send_frames(ser, frames, args.gap)
        recv_reader(ser, state, args.listen)

    if args.keymap:
        if args.keymap == "default":
            codes = P.DEFAULT_KEYMAP
        else:
            codes = [int(x) & 0xFF for x in args.keymap.split(",")]
            if len(codes) != 12:
                print("键位表要 12 个值"); sys.exit(2)
        frames = P.keymap_frames(codes, seq)
        print("发键位表（整表 CRC32=0x%08X）" % P.crc32(bytes(codes)))
        send_frames(ser, frames, args.gap)
        recv_reader(ser, state, 1.0)

    if args.rec_begin is not None:
        t = args.rec_begin
        print("开始录制（tick=%d ms）——现在弹几个音，然后另开一次 --rec-stop" % t)
        ser.write(P.frame(P.CMD_REC_BEGIN, seq, bytes([t & 0xFF, (t >> 8) & 0xFF])))
        ser.flush()
        recv_reader(ser, state, 1.0)

    if args.rec_stop:
        print("停止录制")
        ser.write(P.frame(P.CMD_REC_STOP, seq))
        ser.flush()
        recv_reader(ser, state, 1.0)
        if "last" in state:
            print("录到 %d 条事件（STATUS arg）" % state["last"][1])

    if args.rec:
        n = args.rec
        ser.write(P.frame(P.CMD_REC_READ, seq, bytes([0, 0, n & 0xFF, (n >> 8) & 0xFF])))
        ser.flush()
        print("读回录音 %d 条" % n)
        recv_reader(ser, state, max(args.listen, 1.0 + n * 0.002))
        got = state.get("rec", [])
        print("收到 %d 条" % len(got))
        if not got:
            print("  ⚠️ 一条都没有：是不是没先 --rec-begin？REC_READ 只读已经录进 RAM 的内容。")
        if args.save and got:
            open(args.save, "wb").write(P.make_sps(got, 1))
            print("已存 %s" % args.save)

    ser.close()


if __name__ == "__main__":
    main()
