# -*- coding: utf-8 -*-
"""
at_config.py —— ATK-BLE02 一次性 AT 配置（USB-TTL 接**模块**，不含 FPGA）

    py -3 tools/at_config.py COM5              # 全流程：进 AT → 写入 → 回读 → ENTM
    py -3 tools/at_config.py COM5 --query      # 只读不写（先确认进得去 AT 模式）
    py -3 tools/at_config.py COM5 --raw        # 每个回包额外打印十六进制

接线（此时 FPGA 不参与、板子可以不开）：
    USB-TTL TXD → 模块 RXD        （交叉）
    USB-TTL RXD → 模块 TXD
    USB-TTL GND → 模块 GND
    USB-TTL 3V3 → 模块 VCC        ← 小板跳线必须选 3.3 V，不要 5 V

为什么要配：
    AT+UARTTIM 出厂 10 = 模块攒 100 ms 才把 UART 数据往外送 ⇒ 每个状态回包晚 0.1 s。
    改成 1（10 ms）后回包延迟可以忽略。其余（115200 8N1、透传）出厂就是对的。

⚠️ 进 AT 模式用**手册的方法 2**：先静默 > 打包时间（出厂 100 ms），再发 `+++a`，
   模块回 `a+ok` 才算进去（只发 `+++` 只会得到确认码 `a`，还得再补一个小写 `a`）。
   进去之后 **3 s 内**必须发命令，否则自动退回透传。
⚠️ `AT+ENTM` 之后模块回到透传模式，配置才真正生效（有的模块改 UART 后需要重新上电）。
"""

import argparse
import re
import sys
import time

try:
    import serial
except ImportError:
    print("需要 pyserial：py -3 -m pip install pyserial")
    sys.exit(2)


UUID_RE = re.compile(rb"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
                     rb"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")


def show(tag, resp, raw):
    text = resp.decode("ascii", "replace").replace("\r", "").strip()
    print("  %-8s %s" % (tag, text if text else "(无回包)"))
    if raw and resp:
        print("           hex: " + resp.hex(" "))


def read_until(ser, tokens, timeout):
    """读到任一 token 出现或超时；返回全部原始字节"""
    if isinstance(tokens, bytes):
        tokens = [tokens]
    end = time.time() + timeout
    buf = bytearray()
    while time.time() < end:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            buf.extend(chunk)
            if any(t in buf for t in tokens):
                break
    return bytes(buf)


def enter_at(ser, raw):
    """进 AT 模式。

    手册给了两种方法（AT 指令集 1.配置模式说明）：
      方法1：发 `+++` → 模块回确认码 `a` → **再发一个小写 `a`** → 回 `+ok`
      方法2：直接发 `+++a` → 回 `a+ok`（手册推荐）
    时序要求：发 `+++` 之前静默 > 串口打包时间（出厂 100 ms），
             `+++` 与确认码之间 ≤300 ms，进入后 3 s 内要发命令。
    先试方法2；不成就退回方法1。
    """
    ser.reset_input_buffer()
    time.sleep(0.35)                     # 前置静默 > 打包时间
    ser.write(b"+++a")
    ser.flush()
    resp = read_until(ser, (b"ok", b"ERROR", b"ERR"), 1.0)
    if b"ok" in resp:
        show("[+++a]", resp, raw)
        return True
    show("[+++a]", resp, raw)

    # 退回方法1：+++ → a → a
    ser.reset_input_buffer()
    time.sleep(0.35)
    ser.write(b"+++")
    ser.flush()
    r1 = read_until(ser, (b"a",), 0.4)
    show("[+++]", r1, raw)
    ser.write(b"a")
    ser.flush()
    r2 = read_until(ser, (b"ok", b"ERROR"), 1.0)
    show("[a]", r2, raw)
    return b"ok" in r2


def send_at(ser, cmd, timeout=1.5, raw=False):
    ser.reset_input_buffer()
    ser.write((cmd + "\r\n").encode("ascii"))
    ser.flush()
    resp = read_until(ser, (b"OK", b"ERROR", b"ERR"), timeout)
    ok = b"OK" in resp and b"ERROR" not in resp
    show("[" + cmd.split("=")[0] + "]", resp, raw)
    return ok, resp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--query", action="store_true", help="只读配置，不写入")
    ap.add_argument("--raw", action="store_true", help="打印回包十六进制")
    args = ap.parse_args()

    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.05)
    except Exception as e:
        print("打不开串口 %s：%s" % (args.port, e))
        print("  查端口：py -3 -c \"import serial.tools.list_ports as p;print([x.device for x in p.comports()])\"")
        sys.exit(2)
    time.sleep(0.2)

    print("== 进入 AT 模式 ==")
    if not enter_at(ser, args.raw):
        print("\n[失败] 没有收到 OK。按顺序检查：")
        print("  1) 模块是否上电（指示灯亮）；VCC 用 3.3 V")
        print("  2) TXD/RXD 是否**交叉**（小板 TXD → 模块 RXD）")
        print("  3) 串口是否被串口助手/Arduino IDE 占用")
        print("  4) 模块是否已经处在透传模式且刚从数据流中退出——断电重上电再试")
        ser.close()
        sys.exit(2)

    failures = []

    def step(cmd, expect_ok=True, soft=False):
        ok, resp = send_at(ser, cmd, raw=args.raw)
        if not ok and expect_ok and not soft:
            failures.append(cmd)
        return ok

    if args.query:
        print("\n== 读配置（不写入）==")
        for c in ("AT+NAME?", "AT+UART?", "AT+UARTTIM?", "AT+UUID?"):
            step(c)
    else:
        print("\n== 写入 ==")
        step("AT")
        step("AT+NAME=BLE-PIANO-01")
        step("AT+UART=115200,8,0,1")
        step("AT+UARTTIM=1")
        # ⚠️ 空参数 `AT+HELLO=` 会被拒（ERROR）；参数长度 0-20 但至少要有一个字符。
        #    设成一个空格 = 上电只吐 1 个 0x20，最接近"关掉欢迎语"。
        step("AT+HELLO= ", soft=True)

        print("\n== 回读确认 ==")
        for c in ("AT+NAME?", "AT+UART?", "AT+UARTTIM?"):
            step(c)

    print("\n== UUID（照抄进文档核对）==")
    _, resp = send_at(ser, "AT+UUID?", raw=args.raw)
    for u in UUID_RE.findall(resp):
        print("    " + u.decode("ascii"))

    print("\n== 退出 AT 模式 ==")
    step("AT+ENTM")

    ser.close()

    if failures:
        print("\n[失败] 这些命令没拿到 OK： " + ", ".join(failures))
        sys.exit(1)
    if not args.query:
        print("\n[完成] 已写入。用 AT+UARTTIM? 回读的值应为 1；")
        print("       若仍显示 10，断电重上电后再跑一次 --query 确认。")
        print("       ⚠️ 现在把 TXD/RXD 从模块换到 FPGA（A14/B13），模块 VCC 改由板子 3.3 V 供。")


if __name__ == "__main__":
    main()
