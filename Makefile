SRC = rtl/uart_tx.v rtl/uart_rx.v rtl/uart_top.v tb/tb_uart.v

.PHONY: sim waves clean

sim:
	mkdir -p build
	iverilog -g2012 -Wall -o build/sim $(SRC)
	cd build && vvp sim | tee sim.log | grep -E "FAIL|ALL TESTS|TESTS FAILED|TIMEOUT"

waves: sim
	python3 docs/make_waveforms.py build/uart_wave.vcd

clean:
	rm -rf build
