`timescale 1ns / 1ps
module FifoTestbench();
    reg clk = 1'b0;
    reg rst = 1'b0;
    reg readReq = 1'b0;
    reg writeReq = 1'b0;
    reg [15:0] dataIn = 16'h0;

    wire [15:0] dataOut;
    wire empty, full;
    wire readAck, writeAck;

    Fifo fifo(
        .clk(clk),
        .rst(rst),

        .empty(empty),
        .full(full),
        .readReq(readReq),
        .readAck(readAck),
        .writeReq(writeReq),
        .writeAck(writeAck),
        .dataIn(dataIn),
        .dataOut(dataOut)
    );
    always begin
        clk = 1'b0;
        #0.5;
        clk = 1'b1;
        #0.5;
    end
    initial begin
		$dumpfile("fifo.vcd");
		$dumpvars(0);
		rst = 1'b1;
		#5;
		rst = 1'b0;
		dataIn = 16'ha5;
		writeReq = 1'b1;
		while(!writeAck) #1;
		writeReq = 1'b0;
		readReq = 1'b1;
		while(!readAck) #1;
		readReq = 1'b0;
		$finish;
    end
endmodule
