`timescale 1ns / 1ps
module Testbench();
	reg clk = 1'b0, rst = 1'b0;
	reg rx = 1'b1;
	reg [1:0] dataBits = 2'd0;
	reg hasParity = 1'b0;
	reg [1:0] parityMode = 2'd0;
	reg extraStopBit = 1'b0;
	reg [23:0] clockDivisor = 24'd2;
    wire [8:0] dataOut;
    wire dataReceived;
    wire parityError;
    wire overflow;
    wire break;
    reg receiveReq = 0;
    wire silence;
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
        .silence(silence),
        .receiveReq(receiveReq)
    );
	always begin
	    clk = 1'b1;
	    #0.5;
	    clk = 1'b0;
	    #0.5;
	end
	initial begin
		$dumpfile("silence.vcd");
		$dumpvars(0);
		rst = 1'b1;
		#5;
		rst = 1'b0;
		#300;
		rx = 1'b0;
		#30;
		rx = 1'b1;
		#200;
		$finish;
	end
endmodule
