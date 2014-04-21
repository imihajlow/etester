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
    wire [15:0] wbAdrO;
    wire [15:0] wbDatO;
    wire [15:0] wbDatI;
    wire wbCycO;
    wire wbStbO;
    wire wbAckI;
    wire wbWeO;
	ModbusToWishbone #(
	    .ADDRESS_WIDTH(16),
	    .OFFSET_INPUT_REGISTERS(0),
	    .OFFSET_HOLDING_REGISTERS(0),
	    .QUANTITY_INPUT_REGISTERS('hffff),
	    .QUANTITY_HOLDING_REGISTERS('hffff)
	) _m(
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
		.uartDataIn(dataIn),
		.uartDataReceived(dataReceived),
		.parityError(parityError),
		.overflow(overflow),
		.silence(silence),
		.uartReceiveReq(receiveReq),

		// Output FIFO
		.fifoClk(fifoClk),
		.full(full),
		.fifoWriteReq(writeReq),
		.fifoWriteAck(writeAck),
		.fifoDataOut(dataOut)
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
	reg [8:0] data [31:0];
	reg [4:0] dataIndex = 5'h0;
	reg dataReceived = 1'b0;
	initial begin
		/*data[0] = 9'h37; // address
		data[1] = 9'h03; // function
		data[2] = 9'h00; // starting address hi
		data[3] = 9'h05; // starting address lo
		data[4] = 9'h00; // quantity hi
		data[5] = 9'h02; // quantity lo
		data[6] = 9'hD1; // crc lo
		data[7] = 9'h9C; // crc hi
		data[8] = 9'h100; */
		data[0] = 9'h37; // address
		data[1] = 9'h10; // function
		data[2] = 9'h01; // starting address hi
		data[3] = 9'h05; // starting address lo
		data[4] = 9'h00; // quantity hi
		data[5] = 9'h02; // quantity lo
		data[6] = 9'h04; // byte count
		data[7] = 9'ha5; // data[0] hi
		data[8] = 9'h33; // data[0] lo
		data[9] = 9'h00; // data[0] hi
		data[10] = 9'hFF; // data[0] lo
		data[11] = 9'h4d; // crc lo
		data[12] = 9'h0b; // crc hi
		// Read
		data[13] = 9'h37; // address
		data[14] = 9'h03; // function
		data[15] = 9'h01; // starting address hi
		data[16] = 9'h03; // starting address lo
		data[17] = 9'h00; // quantity hi
		data[18] = 9'h08; // quantity lo
		data[19] = 9'hb0; // crc lo
		data[20] = 9'h66; // crc hi
		// Error
		data[21] = 9'h37; // address
		data[22] = 9'h03; // function
		data[23] = 9'h01; // starting address hi
		data[24] = 9'h03; // starting address lo
		data[25] = 9'h08; // quantity hi
		data[26] = 9'h08; // quantity lo
		data[27] = 9'hb7; // crc lo
		data[28] = 9'ha6; // crc hi
		data[29] = 9'h100; 
	end
	assign dataOut = {1'b0, data[dataIndex][7:0]};
	reg silence = 1'b0;
	initial begin
		dataIndex = 0;
		for(dataIndex = 0; dataIndex <= 31; dataIndex = dataIndex + 1) begin
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
    input [15:0] adr_i
);
    parameter DATA_OFFSET = 16'h0;
    reg ack_o = 1'b0;
    reg [15:0] dat_o = 16'd0;

    reg [15:0] data[1023:0];
    integer i;
    initial begin
        for(i = 0; i < 1024; i = i + 1)
            data[i] = i * 3;
    end

    reg waitState = 1'b0;
    always @(negedge clk) begin
        if(rst) begin
            ack_o <= 1'b0;
            dat_o <= 16'd0;
            waitState <= 1'b0;
        end else begin
            waitState <= stb_i & cyc_i;
            if(stb_i & cyc_i)
                ack_o <= waitState;
            else
                ack_o <= 1'b0;
            if(waitState) begin
                if(adr_i - DATA_OFFSET >= 1024) begin
                    $display("Invalid address: %h", adr_i);
                end
                if(we_i) begin
                    data[adr_i - DATA_OFFSET] <= dat_i;
                    $display("Write %h at %h", dat_i, adr_i);
                end
                dat_o <= data[adr_i - DATA_OFFSET];
            end
        end
    end
endmodule
