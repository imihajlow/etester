MODBUS_SRC=modbus_testbench.v modbus.v crc16.v

all: modbus_testbench

wave: modbus_testbench
	./modbus_testbench

modbus_testbench: $(MODBUS_SRC)
	iverilog -o $@ $^
