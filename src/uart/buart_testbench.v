`timescale 1ns / 1ps
module FifoTestbench();
    reg clk = 1'b0;
    reg rst = 1'b0;
    wire empty;
    reg readReq = 1'b0;
    wire readAck;
    wire [10:0] dataOut;
    wire rx; // = 1'b1;

    wire full;
    reg writeReq = 1'b0;
    wire writeAck;
    reg [10:0] dataIn = 0;
    wire tx;
    
    BufferedUart buart(
        .clk(clk),
        .rst(rst),

        .clockDivisor(5),
        .dataBits(2'd3),
        .hasParity(1'b1),
        .parityMode(2'b10), // 00 - space, 11 - mark, 10 - even, 01 - odd
        .extraStopBit(1'b0),
        
        .empty(empty),
        .readReq(readReq),
        .readAck(readAck),
        .dataOut(dataOut),
        .rx(rx),

        .full(full),
        .writeReq(writeReq),
        .writeAck(writeAck),
        .dataIn(dataIn),
        .tx(tx)
    );
	always begin
		clk = 1'b0;
		#0.5;
		clk = 1'b1;
		#0.5;
	end
	assign rx = tx;
    initial begin
		$dumpfile("uart_fifo.vcd");
		$dumpvars(0);
		rst = 1'b1;
		#5;
		rst = 1'b0;
		dataIn = 10'ha5;
		writeReq = 1'b1;
		while(!writeAck) #1;
		dataIn = 10'h33;
		#1;
		writeReq = 1'b0;

		readReq = 1'b1;
		while(!readAck) #1;
		while(readAck) #1;
		while(!readAck) #1;
		while(readAck) #1;
		readReq = 1'b0;
		$finish;
	end
endmodule
