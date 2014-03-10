SRC=testbench.v uart_tx.v

all: uart_testbench
wave: uart_testbench
	./uart_testbench

uart_testbench: $(SRC)
	iverilog -o $@ $^
