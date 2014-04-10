`timescale 1ns / 1ps
module Testbench();

reg clk = 1'b0;
reg rst = 1'b0;
wire [23:0] wbAdrO;
wire [15:0] wbDatO;
wire [15:0] wbDatI;
wire wbCycO, wbStbO, wbAckI, wbWeO;

reg [15:0] controlReg = 16'h0;
wire [15:0] statusReg;

wire [15:0] prDatI;
wire prAckI;

Processor _p(
    .clk(clk),
    .rst(rst),

    // Wishbone
    .wbAdrO(wbAdrO),
    .wbDatO(wbDatO),
    .wbDatI(prDatI),
    .wbCycO(wbCycO),
    .wbStbO(wbStbO),
    .wbWeO(wbWeO),
    .wbAckI(prAckI),
    
    .controlReg(controlReg),
    .statusReg(statusReg)
);

assign prDatI = pmSel ? pmDatO : (rmSel ? rmDatO : 16'h0);
assign prAckI = pmSel ? pmAckO : (rmSel ? rmAckO : 1'b0);

wire pmSel = wbAdrO[23:16] == 8'h01;

wire pmStbI = pmSel ? wbStbO : 1'b0;
wire pmCycI = pmSel ? wbCycO : 1'b0;
wire pmWeI = pmSel ? wbWeO : 1'b0;
wire [15:0] pmDatO;
wire pmAckO;

Progmem _pm(
    .clk(clk),
    .rst(rst),
    .stb_i(pmStbI),
    .cyc_i(pmCycI),
    .we_i(pmWeI),
    .ack_o(pmAckO),
    .dat_i(wbDatO),
    .dat_o(pmDatO),
    .adr_i(wbAdrO[15:0])
);

wire rmSel = wbAdrO[23:16] == 8'h00;

wire rmStbI = rmSel ? wbStbO : 1'b0;
wire rmCycI = rmSel ? wbCycO : 1'b0;
wire rmWeI = rmSel ? wbWeO : 1'b0;
wire [15:0] rmDatO;
wire rmAckO;

Progmem #(1) _rm(
    .clk(clk),
    .rst(rst),
    .stb_i(rmStbI),
    .cyc_i(rmCycI),
    .we_i(rmWeI),
    .ack_o(rmAckO),
    .dat_i(wbDatO),
    .dat_o(rmDatO),
    .adr_i(wbAdrO[15:0])
);

always begin
    clk = 1'b0;
    #0.5;
    clk = 1'b1;
    #0.5;
end

initial begin
    $dumpfile("processor.vcd");
    $dumpvars(0);
    rst = 1'b1;
    #5;
    rst = 1'b0;
    #1000;
    $finish;
end

endmodule

module Progmem(
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
    parameter IS_REGMEM = 0;
    reg ack_o = 1'b0;
    reg [15:0] dat_o = 16'd0;

    reg [15:0] data[1023:0];
    integer i;
    initial begin
        if(IS_REGMEM) begin
            for(i = 0; i < 1024; i = i + 1)
                data[i] = 16'd0;
        end else begin
            // Записать
            data[0] = 16'd1;
            data[1] = 16'd5;
            data[2] = 16'd239;
            // Проверить
            data[3] = 16'd2;
            data[4] = 16'd5;
            data[5] = 16'd200;
            data[6] = 16'd300;
            data[7] = 16'd5;
            // Ждать
            data[8] = 16'd3;
            data[9] = 16'd5;
            // Еще проверить
            data[10] = 16'd2;
            data[11] = 16'd5;
            data[12] = 16'd300;
            data[13] = 16'd400;
            data[14] = 16'd5;
            // Победить
            data[15] = 16'd4;
        end
    end

    reg waitState = 1'b0;
    always @(negedge clk) begin
        if(rst) begin
            ack_o <= 1'b0;
            dat_o <= 16'd0;
            waitState <= 1'b0;
        end else begin
            if(IS_REGMEM) begin
                waitState <= stb_i & cyc_i;
                ack_o <= waitState;
                if(waitState) begin
                    if(adr_i >= 1024) begin
                        $display("Invalid address: %h", adr_i);
                    end
                    if(we_i) begin
                        data[adr_i] <= dat_i;
                        $display("Write %h at %h", dat_i, adr_i);
                    end
                    dat_o <= data[adr_i];
                end
            end else begin
                ack_o <= stb_i & cyc_i;
                if(stb_i & cyc_i) begin
                    if(adr_i >= 1024) begin
                        $display("Invalid address: %h", adr_i);
                    end
                    if(we_i) begin
                        data[adr_i] <= dat_i;
                        $display("Write %h at %h", dat_i, adr_i);
                    end
                    dat_o <= data[adr_i];
                end
            end
        end
    end
endmodule
