`timescale 1ns / 1ps
module Testbench();
	reg clk = 1'b0, rst = 1'b0;
	wire tx;
	reg [1:0] dataBits = 2'd0;
	reg hasParity = 1'b0;
	reg [1:0] parityMode = 2'd0;
	reg extraStopBit = 1'b0;
	reg [23:0] clockDivisor = 24'd10;
	reg [7:0] data = 8'd0;
	reg transmitReq = 1'b0;

    wire [8:0] dataOut;
    wire dataReceived;
    wire parityError;
    wire overflow;
    wire break;
    reg receiveReq = 0;


	UartTransmitter transmitter(
		.clk(clk),
		.rst(rst),
		.tx(tx),
		.dataBits(dataBits), // data bits count = dataBits + 5
		.hasParity(hasParity),
		.parityMode(parityMode), // 00 - space, 11 - mark, 01 - even, 10 - odd
		.extraStopBit(extraStopBit),
		.clockDivisor(clockDivisor),

		.ready(ready),
		.data(data),
		.transmitReq(transmitReq));

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
        .receiveReq(receiveReq)
    );
    assign rx = tx;
	always begin
		clk = 1'b0;
		#0.5;
		clk = 1'b1;
		#0.5;
	end
	initial begin
		$dumpfile("uart.vcd");
		$dumpvars(0);
		rst = 1'b1;
		#5;
		rst = 1'b0;
		dataBits = 2'd3;
		hasParity = 1'b1;
		parityMode = 2'b01;
		extraStopBit = 1'b0;
		clockDivisor = 10;
		data = 8'h60;
		transmitReq = 1'b1;
		#1;
		transmitReq = 1'b0;
		while(!ready) #1;
		data = 8'ha5;
		transmitReq = 1'b1;
		#1;
		transmitReq = 1'b0;
		while(!dataReceived) #1;
		receiveReq = 1'b1;
		#1;
		receiveReq = 1'b0;
		while(!ready) #1;
		while(!dataReceived) #1;
		receiveReq = 1'b1;
		#1;
		receiveReq = 1'b0;
		#20;
		$finish;
	end
endmodule
