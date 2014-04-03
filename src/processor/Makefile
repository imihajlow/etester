all: testbench
wave: testbench
	./testbench
testbench: processor.v testbench.v
	iverilog -o $@ $^
