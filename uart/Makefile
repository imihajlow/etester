SRC_UART=testbench.v uart_tx.v uart_rx.v
SRC_FIFO=fifo_testbench.v fifo.v
SRC_BUART=buart_testbench.v buffered_uart.v fifo.v uart_tx.v uart_rx.v

all: uart_testbench fifo_testbench buart_testbench
wave: uart_testbench fifo_testbench buart_testbench
	./uart_testbench
	./buart_testbench
	./fifo_testbench

uart_testbench: $(SRC_UART)
	iverilog -o $@ $^

fifo_testbench: $(SRC_FIFO)
	iverilog -o $@ $^

buart_testbench: $(SRC_BUART)
	iverilog -o $@ $^
