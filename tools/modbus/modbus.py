#!/usr/bin/python
import minimalmodbus
import array

def main():
    minimalmodbus.BAUDRATE = 115200
    d = minimalmodbus.Instrument("/dev/ttyUSB1", 0x37)
    #d.write_registers(2, [1,2,3])
    print d.read_registers(1, 5)

if __name__ == "__main__":
    main()
