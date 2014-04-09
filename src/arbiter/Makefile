SRC=testbench.v arbiter.v

all: testbench

wave: testbench
	./testbench

testbench: $(SRC)
	iverilog -o $@ $^
