module UartReceiver(
    input clk,
    input rst,
    input rx,
    input [1:0] dataBits, // data bits count = dataBits + 5
    input hasParity,
    input [1:0] parityMode, // 00 - space, 11 - mark, 01 - even, 10 - odd
    input extraStopBit,
    input [CLOCK_DIVISOR_WIDTH-1:0] clockDivisor,

    output reg [8:0] dataOut,
    output reg dataReceived,
    output reg parityError,
    output reg overflow,
    output reg break,
    input receiveData;
);
    parameter CLOCK_DIVISOR_WIDTH=24;
    localparam STATE_IDLE = 3'd0;
    localparam STATE_START = 3'd1;
    localparam STATE_DATA = 3'd2;
    localparam STATE_STOP = 3'd3;
    reg [2:0] state;
    reg [CLOCK_DIVISOR_WIDTH-1:0] clkCounter;
    wire uartClk = clkCounter[CLOCK_DIVISOR_WIDTH-1];

    always @(posedge clk) begin
        if(rst) begin
            dataOut <= 9'b0;
            dataReceived <= 1'b0;
            parityError <= 1'b0;
            overflow <= 1'b0;
            break <= 1'b0;
            clkCounter <= 0;
        end else begin
            if(state == STATE_IDLE) begin
                if(rx == 1'b0) begin
                    state <= STATE_START;
                end
                clkCounter <= 0;
            end else begin
                clkCounter <= clkCounter + 1;
            end
        end
    end
endmodule
