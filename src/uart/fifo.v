module Fifo(
    input clk,
    input rst,

    output empty,
    output full,
    input readReq,
    output readAck,
    input writeReq,
    output writeAck,
    input [DATA_WIDTH-1:0] dataIn,
    output [DATA_WIDTH-1:0] dataOut
);
    parameter DATA_WIDTH = 16;
    parameter FIFO_LOG_LENGTH = 4;
    localparam FIFO_LENGTH = 1 << FIFO_LOG_LENGTH;

    reg [DATA_WIDTH-1:0] buffer[FIFO_LENGTH-1:0];
    reg [FIFO_LOG_LENGTH-1:0] getPtr = 0;
    reg [FIFO_LOG_LENGTH-1:0] putPtr = 0;
    reg [DATA_WIDTH-1:0] dataOut = 0;
    assign empty = getPtr == putPtr;
    assign full = (putPtr + 1) == getPtr;
    reg readAck = 1'b0;
    reg writeAck = 1'b0;

    always @(posedge clk) begin
        if(rst) begin
            getPtr <= 0;
            putPtr <= 0;
        end else begin
            if(readReq) begin
                if(!empty) begin
                    getPtr <= getPtr + 1;
                    readAck <= 1'b1;
                    dataOut <= buffer[getPtr];
                end else
                    readAck <= 1'b0;
            end else begin
                readAck <= 1'b0;
            end
            if(writeReq) begin
                if(!full) begin
                    buffer[putPtr] <= dataIn;
                    putPtr <= putPtr + 1;
                    writeAck <= 1'b1;
                end else begin
                    writeAck <= 1'b0;
                end
            end else begin
                writeAck <= 1'b0;
            end
        end
    end
endmodule
