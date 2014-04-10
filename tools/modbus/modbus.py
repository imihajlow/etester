#!/usr/bin/python
import minimalmodbus
import array

def main():
    minimalmodbus.BAUDRATE = 115200
    d = minimalmodbus.Instrument("/dev/ttyUSB1", 0x37)
    for i in xrange(1, 10000):
        try:
            d.write_registers(1, [1,2,i])
        except ValueError as e:
            print "Fuck it! Value error", i, str(e)
        except IOError as e:
            print "Fuck it! IO error", i, str(e)
    print d.read_registers(256, 5)

if __name__ == "__main__":
    main()
