# Timing constraint: external main clock 50MHz (period = 20ns)
create_clock -name sys_clk -period 20.0 [get_ports {sys_clk}]

# ------------------------------------------------------------------
# 1000. 显示 PLL 与音频 50MHz 是**异步**时钟域，跨域数据用翻转沿 +
#       两级同步（多 bit 总线在两次翻转之间稳定 20.5us / 1ms），
#       因此不做 sys_clk <-> pclk/bclk 的同步时序分析。
# ------------------------------------------------------------------
set_clock_groups -asynchronous -group [get_clocks {sys_clk}]

# ------------------------------------------------------------------
# 1001. 音频链是**采样同步**的：i2s 在 sample_strobe 上锁存，数据在整个
#       1024 拍采样周期内稳定；display_cond 的 disp_ac 也只是每个采样点
#       取一次稳定值。二者不是 50MHz 组合数据路径，设为 false path。
#       （这是既有 `u_i2s/latched_l` 伪违例基线的显式声明。）
# ------------------------------------------------------------------
set_false_path -to [get_regs {u_i2s/latched_l_*}]
set_false_path -to [get_regs {u_disp_cond/*}]

# ------------------------------------------------------------------
# 1002. 混响/延迟线内部寄存器全部在 `if (sample_strobe)` 里更新（每 1024 拍一次），
#       是**多周期路径**。之前它们以 −17 ns 的"伪违例"占满了最差路径表，
#       把 50 MHz 域里真正每拍都要收敛的路径（FFT / voice / mixer）全遮住了，
#       所以 FFT 的时序从来没有被真正验证过。这里显式声明多周期，
#       让报告暴露真实的最差单拍路径。
# ------------------------------------------------------------------
set_multicycle_path -setup 1024 -to [get_regs {u_fx/u_reverb/*}]
# ⚠️ 配对的 hold 必须是 N−1 = 1023：写 0 会把 hold 检查拉到捕获沿之前 1023 拍，
#    报告里出现 −1.5e6 ns 的 hold TNS（2026-10-26 踩过，是写法错，不是设计错）。
set_multicycle_path -hold 1023 -to [get_regs {u_fx/u_reverb/*}]
