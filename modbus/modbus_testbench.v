`timescale 1ns / 1ps
module ModbusTestbench();
	reg clk = 1'b0;
	reg rst = 1'b0;

	wire uartClk;
	wire[8:0] dataIn;
	wire dataReceived;
	wire parityError = 1'b0;
	wire overflow = 1'b0;
	wire silence, receiveReq;
	wire fifoClk, full, writeReq;
	wire [7:0] dataOut;
	ModbusToWishbone _m(
		.clk(clk),
		.rst(rst),
		/*output [ADDRESS_WIDTH-1:0] adr_o,
		output [DATA_WIDTH-1:0] dat_o,
		input [DATA_WIDTH-1:0] dat_i,
		output cyc_o,
		output stb_o,
		input ack_i,
		output we_o,*/

		// Input UART
		.uartClk(uartClk),
		.dataIn(dataIn),
		.dataReceived(dataReceived),
		.parityError(parityError),
		.overflow(overflow),
		.silence(silence),
		.receiveReq(receiveReq),

		// Output FIFO
		.fifoClk(fifoClk),
		.full(full),
		.writeReq(writeReq),
		.writeAck(writeAck),
		.dataOut(dataOut)
	);
	FakeUartRx _uart(
		.clk(uartClk),
		.rst(rst),
		.dataReceived(dataReceived),
		.receiveReq(receiveReq),
		.dataOut(dataIn),
		.silence(silence)
	);
	reg writeAck = 1'b0;
	always begin
		clk = 1'b0;
		#0.5;
		clk = 1'b1;
		#0.5;
	end
	always @(posedge fifoClk) begin
		writeAck <= writeReq;
		if(writeReq) begin
			$display("Got: %h", dataOut);
		end
	end
	initial begin
		$dumpfile("modbus.vcd");
		$dumpvars(0);
		rst = 1'b1;
		#10;
		rst = 1'b0;
		#1000;
		$finish;
	end
endmodule

module FakeUartRx(
	input clk,
	input rst,
	output dataReceived,
	input receiveReq,
	output [8:0] dataOut,
	output silence
);
	reg [8:0] data [15:0];
	reg [3:0] dataIndex = 4'h0;
	reg dataReceived = 1'b0;
	initial begin
		data[0] = 9'h37;
		data[1] = 9'h01;
		data[2] = 9'h00;
		data[3] = 9'h00;
		data[4] = 9'ha5;
		data[5] = 9'hff;
		data[6] = 9'h02;
		data[7] = 9'h8c;
		data[8] = 9'h100;
	end
	assign dataOut = {1'b0, data[dataIndex][7:0]};
	reg silence = 1'b0;
	initial begin
		dataIndex = 0;
		for(dataIndex = 0; dataIndex < 15; dataIndex = dataIndex + 1) begin
			if(data[dataIndex][8]) begin
				dataReceived = 1'b0;
				silence = 1'b1;
				#5;
				silence = 1'b0;
			end else begin
				#5;
				dataReceived = 1'b1;
				while(~receiveReq) begin
					#0.5;
				end
				dataReceived = 1'b0;
			end
		end
	end
endmodule
