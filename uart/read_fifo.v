module UartReadFifo(
    input clk,
    input rst,
    input rx,

    input [1:0] dataBits, // data bits count = dataBits + 5
    input hasParity,
    input [1:0] parityMode, // 00 - space, 11 - mark, 10 - even, 01 - odd
    input extraStopBit,
    input [CLOCK_DIVISOR_WIDTH-1:0] uartClockDivisor,

    output empty,
    output full,
    input read,
    output data
);
    UartReceiver uartReceiver(
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .dataBits(dataBits),
        .hasParity(hasParity),
        .parityMode(parityMode),
        .extraStopBit(extraStopBit),
        .clockDivisor(clockDivisor),

        .dataOut(dataOut),
        .dataReceived(dataReceived),
        .parityError(parityError),
        .overflow(overflow),
        .break(break),
        .receiveData(receiveData)
    );
endmodule
