SRC=testbench.v uart_tx.v uart_rx.v

all: uart_testbench
wave: uart_testbench
	./uart_testbench

uart_testbench: $(SRC)
	iverilog -o $@ $^
