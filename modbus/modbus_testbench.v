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
    wire wbAdrO;
    wire [DATA_WIDTH-1:0] wbDatO;
    wire [DATA_WIDTH-1:0] wbDatI;
    wire wbCycO;
    wire wbStbO;
    wire wbAckI;
    wire wbWeO;
	ModbusToWishbone _m(
		.clk(clk),
		.rst(rst),
        .wbAdrO(wbAdrO),
        .wbDatO(wbDatO),
        .wbDatI(wbDatI),
        .wbCycO(wbCycO),
        .wbStbO(wbStbO),
        .wbAckI(wbAckI),
        .wbWeO(wbWeO),
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
    FakeWishboneSlave _slave(
        .clk(clk),
        .rst(rst),
        .stb_i(wbStbO),
        .cyc_i(wbCycO),
        .we_i(wbWeO),
        .ack_o(wbAckI),
        .dat_i(wbDatO),
        .dat_o(wbDatI),
        .adr_i(wbAdrO)
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

module FakeWishboneSlave(
    input clk,
    input rst,
    input stb_i,
    input cyc_i,
    input we_i,
    output ack_o,
    input [15:0] dat_i,
    output [15:0] dat_o,
    input [23:0] adr_i
);
    parameter DATA_OFFSET = 24'hA00000;
    reg ack_o = 1'b0;
    reg [15:0] dat_o = 16'd0;

    reg [15:0] data[1023:0];
    integer i;
    initial begin
        for(i = 0; i < 1024; ++i)
            data[i] = i * 3;
    end

    always @(negedge clk) begin
        if(rst) begin
            ack_o <= 1'b0;
            dat_o <= 16'd0;
        end else begin
            ack_o <= stb_i & cyc_i;
            if(addr_i - DATA_OFFSET >= 1024) begin
                $display("Invalid address: %h", adr_i);
            end
            if(we_i)
                data[adr_i - DATA_OFFSET] <= dat_i;
            dat_o <= data[adr_i - DATA_OFFSET];
        end
    end
endmodule
