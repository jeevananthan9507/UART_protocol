#!/usr/bin/env python3
"""Render waveform PNGs from the testbench VCD (uart_wave.vcd).

Usage:  python3 docs/make_waveforms.py path/to/uart_wave.vcd
Needs:  pip install vcdvcd matplotlib
These images come straight from the simulation data (not hand-drawn).
"""
import sys
import vcdvcd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

vcd_path = sys.argv[1] if len(sys.argv) > 1 else "uart_wave.vcd"
v = vcdvcd.VCDVCD(vcd_path)
PS = 1000.0                     # VCD time unit is ps -> convert to ns for plots
CLK_NS, CPB = 10.0, 10          # testbench: 10 ns clock, 10 clocks per bit
BIT_NS = CLK_NS * CPB


def sig(name):
    return v[name].tv           # list of (time_ps, value_string)


def at(tv, t_ps):
    val = tv[0][1]
    for t, x in tv:
        if t > t_ps:
            break
        val = x
    return val


def rises(tv):
    return [t for (t, x), (_, p) in zip(tv[1:], tv[:-1]) if x == "1" and p != "1"]


def falls(tv):
    return [t for (t, x), (_, p) in zip(tv[1:], tv[:-1]) if x == "0" and p != "0"]


def to_hex(s):
    return "x" if "x" in s or "z" in s else "%02X" % int(s, 2)


def draw(ax, tv, t0, t1, y, h=0.6, bus=False):
    """Draw one signal row between t0..t1 (ps) at height offset y."""
    pts = [(t0, at(tv, t0))] + [(t, x) for t, x in tv if t0 < t <= t1] + [(t1, None)]
    for (ta, xa), (tb, _) in zip(pts[:-1], pts[1:]):
        xs, xe = ta / PS, tb / PS
        if bus:
            ax.plot([xs, xe], [y, y], color="#1F3A5F", lw=1.4)
            ax.plot([xs, xe], [y + h, y + h], color="#1F3A5F", lw=1.4)
            ax.plot([xs, xs], [y, y + h], color="#1F3A5F", lw=1.4)
            if xe - xs > 25:
                ax.text((xs + xe) / 2, y + h / 2, to_hex(xa), ha="center", va="center",
                        fontsize=8, family="monospace")
        else:
            lvl = y + h if xa == "1" else y
            ax.plot([xs, xe], [lvl, lvl], color="#1F3A5F", lw=1.6)
            if tb < t1:
                nxt = pts[pts.index((ta, xa)) + 1][1]
                if nxt is not None and nxt != xa:
                    ax.plot([xe, xe], [y, y + h], color="#1F3A5F", lw=1.6)


def setup(ax, rows, t0, t1, title):
    ax.set_xlim(t0 / PS, t1 / PS)
    ax.set_ylim(-0.4, len(rows) * 1.0 + 0.9)
    ax.set_yticks([(len(rows) - 1 - i) + 0.3 for i in range(len(rows))])
    ax.set_yticklabels(rows, fontsize=9, family="monospace")
    ax.set_xlabel("time (ns)")
    ax.set_title(title, fontsize=11, loc="left")
    ax.grid(axis="x", ls=":", lw=0.4, color="#999")
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)


# ---------- Figure 1: one 8E1 frame (0xA5) in loopback ----------
base = "tb_uart.t1.dut."
start = sig(base + "tx_start")
t_start = rises(start)[0]
tx = sig(base + "tx")
t_low = [t for t in falls(tx) if t > t_start][0]            # start bit begins
rxv = sig(base + "rx_valid")
t_val = [t for t in rises(rxv) if t > t_low][0]
t0, t1 = t_start - 3 * CLK_NS * PS, t_val + 12 * CLK_NS * PS
names = ["tx_start", "tx_busy", "tx", "rx_valid", "rx_data[7:0]", "parity_err", "frame_err"]
fig, ax = plt.subplots(figsize=(12, 4.8))
setup(ax, names, t0, t1, "UART loopback, 8E1, byte 0xA5: transmit and receive")
spec = [("tx_start", False), ("tx_busy", False), ("tx", False), ("rx_valid", False),
        ("rx_data[7:0]", True), ("parity_err", False), ("frame_err", False)]
for i, (n, bus) in enumerate(spec):
    draw(ax, sig(base + n), t0, t1, len(spec) - 1 - i, bus=bus)
labels = ["Start"] + ["D%d" % k for k in range(8)] + ["Parity", "Stop"]
cols = ["#F8D0D0"] + ["#D5E6F7"] * 8 + ["#FBEAB5", "#CDEBCF"]
for k, (lb, c) in enumerate(zip(labels, cols)):
    xs = t_low / PS + k * BIT_NS
    ax.axvspan(xs, xs + BIT_NS, color=c, alpha=0.55, lw=0, zorder=0)
    ax.axvline(xs, color="#888", ls=":", lw=0.5)
    ax.text(xs + BIT_NS / 2, 7.05, lb, ha="center", va="bottom", fontsize=8)
ax.axvline(t_low / PS + 11 * BIT_NS, color="#888", ls=":", lw=0.5)
ax.set_ylim(-0.4, 7.7)
fig.tight_layout()
fig.savefig("docs/waveform_8E1_frame.png", dpi=150)
print("wrote docs/waveform_8E1_frame.png")

# ---------- Figure 2: error injection on the receiver (8E1) ----------
base = "tb_uart.t4."
rxv = sig(base + "rx_valid")
ev = rises(rxv)
t0 = ev[0] - 11.5 * BIT_NS * PS * 1.0 / 1.0 if False else ev[0] - 11 * BIT_NS * PS
t1 = ev[2] + 5 * BIT_NS * PS
names = ["rx", "rx_valid", "rx_data[7:0]", "frame_err", "parity_err"]
fig, ax = plt.subplots(figsize=(12, 3.8))
setup(ax, names, t0, t1, "Receiver error injection (8E1): good frame, bad stop bit, bad parity")
spec = [("rx", False), ("rx_valid", False), ("rx_data[7:0]", True),
        ("frame_err", False), ("parity_err", False)]
for i, (n, bus) in enumerate(spec):
    draw(ax, sig(base + n), t0, t1, len(spec) - 1 - i, bus=bus)
notes = ["good frame\n(no flags)", "bad stop bit\n-> frame_err = 1", "bad parity bit\n-> parity_err = 1"]
for e, txt in zip(ev[:3], notes):
    ax.axvline(e / PS, color="#C0392B", ls="--", lw=1)
    ax.text(e / PS + 8, 5.15, txt, fontsize=8, color="#C0392B", va="bottom")
ax.set_ylim(-0.4, 6.4)
fig.tight_layout()
fig.savefig("docs/waveform_error_injection.png", dpi=150)
print("wrote docs/waveform_error_injection.png")
