SRC_UART=testbench.v uart_tx.v uart_rx.v
SRC_FIFO=fifo_testbench.v fifo.v

all: uart_testbench fifo_testbench
wave: uart_testbench fifo_testbench
	./uart_testbench
	./fifo_testbench

uart_testbench: $(SRC_UART)
	iverilog -o $@ $^

fifo_testbench: $(SRC_FIFO)
	iverilog -o $@ $^
