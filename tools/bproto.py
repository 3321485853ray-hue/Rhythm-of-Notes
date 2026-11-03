# -*- coding: utf-8 -*-
"""
bproto.py —— 蓝牙曲谱协议（PROTOCOL.md v1.0 + 本工程扩展）的 Python 实现

帧：AA 5A VER CMD SEQ LEN PAYLOAD[8] CRC16[2]，CRC16 覆盖字节 2..13。
事件记录 8 字节（小端）：delta u16, note u8, vel u8, dur u16, flags u8, rsv u8。

⚠️ **载荷在总线上是"第 0 字节在前"**：拼帧时 payload 就是按这个顺序给出的 bytes。
⚠️ 所有多字节字段都是**小端**。
"""

import struct
import zlib

CAPACITY = 8192
TICK_MS = 1

# 指令码
CMD_PING        = 0x01
CMD_BEGIN       = 0x02
CMD_EVENT       = 0x10
CMD_END         = 0x03
CMD_PLAY        = 0x04
CMD_STOP        = 0x05
CMD_GET_STATUS  = 0x0A
CMD_KEYMAP      = 0x20
CMD_KEYMAP_DONE = 0x21
CMD_KEY         = 0x30
CMD_REC_BEGIN   = 0x40
CMD_REC_STOP    = 0x41
CMD_REC_READ    = 0x42

CMD_STATUS      = 0x80
CMD_RECDATA     = 0x81

# 状态码
ST_OK            = 0x00
ST_ERR_FRAME_CRC = 0x01
ST_ERR_LEN       = 0x02
ST_ERR_CMD       = 0x03
ST_ERR_STATE     = 0x04
ST_ERR_OVERFLOW  = 0x05
ST_ERR_STREAM_CRC= 0x06
ST_ERR_COUNT     = 0x07
ST_PLAY_STARTED  = 0x10
ST_PLAY_DONE     = 0x11
ST_STOPPED       = 0x12
ST_REC_START     = 0x13
ST_REC_END       = 0x14

STATE_NAMES = {0: "IDLE", 1: "LOADING", 2: "READY", 3: "PLAYING", 4: "ERROR", 5: "REC"}


def crc16(data: bytes) -> int:
    """CRC-16/CCITT-FALSE：poly 0x1021, init 0xFFFF, 不反射, xorout 0"""
    c = 0xFFFF
    for b in data:
        c ^= b << 8
        for _ in range(8):
            c = ((c << 1) ^ 0x1021) & 0xFFFF if c & 0x8000 else (c << 1) & 0xFFFF
    return c


def crc32(data: bytes) -> int:
    """CRC-32/ISO-HDLC（zlib 同款）"""
    return zlib.crc32(data) & 0xFFFFFFFF


def frame(cmd: int, seq: int, payload: bytes = b"") -> bytes:
    """组一条 16 字节帧"""
    if len(payload) > 8:
        raise ValueError("payload 最多 8 字节")
    body = bytes([0x01, cmd & 0xFF, seq & 0xFF, len(payload)]) + payload + bytes(8 - len(payload))
    c = crc16(body)
    return b"\xAA\x5A" + body + bytes([c & 0xFF, c >> 8])


def parse_frames(buf: bytes):
    """从字节流里解析出所有合法帧，返回 [(cmd, seq, payload, raw), ...]"""
    out = []
    i = 0
    while i + 16 <= len(buf):
        if buf[i] == 0xAA and buf[i + 1] == 0x5A:
            fr = buf[i:i + 16]
            c = crc16(fr[2:14])
            if c == fr[14] | (fr[15] << 8):
                out.append((fr[3], fr[4], fr[6:6 + fr[5]], fr))
                i += 16
                continue
        i += 1
    return out


def ev(delta: int, note: int, vel: int, dur: int, flags: int = 0) -> bytes:
    """一条事件记录（8 字节，小端）"""
    return struct.pack("<HBBHB", delta, note, vel, dur, flags) + b"\x00"


def unpack_ev(b: bytes):
    d, n, v, du, f = struct.unpack("<HBBHB", b[:7])
    return d, n, v, du, f


def make_sps(events, tick_ms: int = TICK_MS) -> bytes:
    """`.sps` 曲谱包：16 B 头 + N×8 B 事件"""
    blob = b"".join(events)
    if len(blob) % 8:
        raise ValueError("事件长度必须是 8 的倍数")
    n = len(blob) // 8
    head = b"SPS1" + bytes([1, 0]) + struct.pack("<HH", n, tick_ms) + struct.pack("<HI", 0, crc32(blob))
    #  head: "SPS1"(4) ver(1) rsv(1) total(2) tick(2) rsv(2) crc32(4)
    return head + blob


def parse_sps(data: bytes):
    """返回 (events_bytes_list, tick_ms)"""
    if data[:4] != b"SPS1":
        raise ValueError("不是 .sps 文件")
    ver = data[4]
    if ver != 1:
        raise ValueError("不支持的 .sps 版本 %d" % ver)
    total, tick = struct.unpack("<HH", data[6:10])
    crc_hdr = struct.unpack("<I", data[12:16])[0]
    blob = data[16:]
    if len(blob) != total * 8:
        raise ValueError("长度不符：头里 %d 条，实际 %d 字节" % (total, len(blob)))
    if crc32(blob) != crc_hdr:
        raise ValueError("CRC32 不符")
    return [blob[i * 8:(i + 1) * 8] for i in range(total)], tick


def frames_for_sps(data: bytes, seq0: int = 0, loop: int = 0):
    """把一份 .sps 变成 BEGIN/EVENT…/END/PLAY 的帧列表（含各自 SEQ）"""
    evs, tick = parse_sps(data)
    blob = b"".join(evs)
    out = []
    s = seq0
    out.append((s, frame(CMD_BEGIN, s & 0xFF, struct.pack("<HIH", len(evs), crc32(blob), tick)))); s += 1
    for e in evs:
        out.append((s, frame(CMD_EVENT, s & 0xFF, e))); s += 1
    out.append((s, frame(CMD_END, s & 0xFF, struct.pack("<HI", len(evs), crc32(blob))))); s += 1
    out.append((s, frame(CMD_PLAY, s & 0xFF, bytes([loop & 0xFF])))); s += 1
    return out


def keymap_frames(codes, seq0: int = 0, chunk: int = 6):
    """12 项键位表 → KEYMAP 帧 + KEYMAP_DONE（整表 CRC32）"""
    if len(codes) != 12:
        raise ValueError("需要 12 个码值")
    out = []
    s = seq0
    for off in range(0, 12, chunk):
        part = list(codes[off:off + chunk])
        cnt = len(part)
        part += [0] * (6 - cnt)
        pay = bytes([off, cnt] + part)
        out.append((s, frame(CMD_KEYMAP, s & 0xFF, pay))); s += 1
    out.append((s, frame(CMD_KEYMAP_DONE, s & 0xFF, struct.pack("<I", crc32(bytes(codes)))))); s += 1
    return out


# 默认键位表（= 现在的钢琴布局：C4 D4 E4 F4 G4 A4 B4 | C#4 D#4 F#4 G#4 A#4）
DEFAULT_KEYMAP = [60, 62, 64, 65, 67, 69, 71, 61, 63, 66, 68, 70]
