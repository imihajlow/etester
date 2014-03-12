module BufferedUart(
    input clk,
    input rst,

    input [CLOCK_DIVISOR_WIDTH-1:0] clockDivisor,
    input [1:0] dataBits, // data bits count = dataBits + 5
    input hasParity,
    input [1:0] parityMode, // 00 - space, 11 - mark, 10 - even, 01 - odd
    input extraStopBit,
    
    output empty,
    input readReq,
    output readAck,
    output [10:0] dataOut,
    input rx,

    output full,
    input writeReq,
    output writeAck,
    input [10:0] dataIn,
    output tx
);
    parameter CLOCK_DIVISOR_WIDTH=24;
    wire readFifoFull;
    wire readFifoWriteReq;
    wire readFifoWriteAck;
    wire [10:0] readFifoDataIn;
    Fifo #(
        .DATA_WIDTH(11)
        ) readFifo(
        .clk(clk),
        .rst(rst),

        .empty(empty),
        .full(readFifoFull),
        .readReq(readReq),
        .readAck(readAck),
        .writeReq(readFifoWriteReq),
        .writeAck(readFifoWriteAck),
        .dataIn(readFifoDataIn),
        .dataOut(dataOut)
    );

    wire writeFifoEmpty;
    wire writeFifoReadReq;
    wire writeFifoReadAck;
    wire [10:0] writeFifoDataOut;
    Fifo #(
        .DATA_WIDTH(11)
        ) writeFifo(
        .clk(clk),
        .rst(rst),

        .empty(writeFifoEmpty),
        .full(full),
        .readReq(writeFifoReadReq),
        .readAck(writeFifoReadAck),
        .writeReq(writeReq),
        .writeAck(writeAck),
        .dataIn(dataIn),
        .dataOut(writeFifoDataOut)
    );

    wire txReady;
    wire [7:0] txData;
    wire transmitReq;
	UartTransmitter #(
	    .CLOCK_DIVISOR_WIDTH(CLOCK_DIVISOR_WIDTH)
	    ) transmitter(
		.clk(~clk),
		.rst(rst),
		.tx(tx),
		.dataBits(dataBits), // data bits count = dataBits + 5
		.hasParity(hasParity),
		.parityMode(parityMode), // 00 - space, 11 - mark, 01 - even, 10 - odd
		.extraStopBit(extraStopBit),
		.clockDivisor(clockDivisor),

		.ready(txReady),
		.data(txData),
		.transmitReq(transmitReq));

    wire [7:0] rxDataOut;
    wire rxDataReceived;
    wire parityError, overflow, break;
    wire receiveReq;
    UartReceiver #(
	    .CLOCK_DIVISOR_WIDTH(CLOCK_DIVISOR_WIDTH)
	    ) receiver(
        .clk(~clk),
        .rst(rst),
        .rx(rx),
        .dataBits(dataBits),
        .hasParity(hasParity),
        .parityMode(parityMode),
        .extraStopBit(extraStopBit),
        .clockDivisor(clockDivisor),

        .dataOut(rxDataOut),
        .dataReceived(rxDataReceived),
        .parityError(parityError),
        .overflow(overflow),
        .break(break),
        .receiveReq(receiveReq)
    );

    assign txData = writeFifoDataOut[7:0];
    assign transmitReq = writeFifoReadAck;
    assign writeFifoReadReq = txReady;

    assign readFifoDataIn = { overflow, parityError, rxDataOut };
    assign readFifoWriteReq = rxDataReceived;
    assign receiveReq = readFifoWriteAck;
endmodule
