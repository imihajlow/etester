`timescale 1ns / 1ps
module Testbench();

reg clk = 1'b0;
reg rst = 1'b1;
wire [1:0] mCycI;
wire [1:0] mStbI;
wire [1:0] mWeI;
wire [1:0] mAckO;
wire [31:0] mAdrO[1:0];
wire [31:0] mDatO[1:0];
wire [31:0] mDatI[1:0];

wire [32*2-1:0] mAdrOPacked = { mAdrO[1], mAdrO[0] };
wire [32*2-1:0] mDatOPacked = { mDatO[1], mDatO[0] };
wire [32*2-1:0] mDatIPacked;
assign mDatI[0] = mDatIPacked[31:0];
assign mDatI[1] = mDatIPacked[63:32];

wire sCycO;
wire sStbO;
wire sWeO;
reg sAckI = 1'b0;
wire [31:0] sAdrO;
wire [31:0] sDatI;
wire [31:0] sDatO;
Arbiter _a(
    .clk(clk),
    .rst(rst),

    .mCycI(mCycI),
    .mStbI(mStbI),
    .mWeI(mWeI),
    .mAckO(mAckO),
    .mAdrIPacked(mAdrOPacked),
    .mDatIPacked(mDatOPacked),
    .mDatOPacked(mDatIPacked),

    .sCycO(sCycO),
    .sStbO(sStbO),
    .sWeO(sWeO),
    .sAckI(sAckI),
    .sAdrO(sAdrO),
    .sDatI(sDatI),
    .sDatO(sDatO)
);
FakeMaster #(5) _m1(
    .clk(clk),
    .rst(rst),
    .cycI(mCycI[0]),
    .stbI(mStbI[0]),
    .weI(mWeI[0]),
    .ackI(mAckO[0]),
    .adrO(mAdrO[0]),
    .datO(mDatO[0]),
    .datI(mDatI[0])
);
FakeMaster #(7,3) _m2(
    .clk(clk),
    .rst(rst),
    .cycI(mCycI[1]),
    .stbI(mStbI[1]),
    .weI(mWeI[1]),
    .ackI(mAckO[1]),
    .adrO(mAdrO[1]),
    .datO(mDatO[1]),
    .datI(mDatI[1])
);

always @(negedge clk) sAckI <= sCycO & sStbO;
always begin
    clk = 1'b1;
    #0.5;
    clk = 1'b0;
    #0.5;
end
initial begin
    $dumpfile("arbiter.vcd");
    $dumpvars(0);
    #3;
    rst = 1'b0;
    #1000;
    $finish;
end

endmodule

module FakeMaster(
    input clk,
    input rst,
    output cycI,
    output stbI,
    output weI,
    input ackI,
    output [31:0] adrO,
    output [31:0] datO,
    input [31:0] datI
);
    parameter PAUSE = 5;
    parameter PACKET = 1;
    reg stbI = 1'b0;
    assign cycI = stbI;
    reg weI = 1'b0;
    assign adrO = PAUSE;
    assign datO = PAUSE;
    integer i;
    always begin
        if(rst)
            stbI = 1'b0;
        else begin
            #PAUSE;
            stbI = 1'b1;
            while(!ackI) #1;
            for(i = 0; i < PACKET-1; i = i + 1) begin
                #1;
                while(!ackI) #1;
            end
            stbI = 1'b0;
        end
    end
endmodule
