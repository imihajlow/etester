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
            if(receiveData) begin
                dataReceived <= 1'b0;
                overflow <= 1'b0;
                break <= 1'b0;
            end
        end
    end

    wire [3:0] totalDataBits = 4'd5 + dataBits + hasParity - 1'd5;
    reg [3:0] dataCounter = 4'd0;
    reg [8:0] currentData = 9'd0;

    reg firstStopBitReceived = 1'b0;
    wire currentParityError = 1'b0;

    always @(posedge uartClk) begin
        case(state)
            STATE_START:
                if(rx == 1'b1)
                    state <= STATE_IDLE;
                else begin
                    state <= STATE_DATA;
                    dataCounter <= 0;
                end
            STATE_DATA:
                currentData[dataCounter] <= rx;
                if(dataCounter < totalDataBits) begin
                    dataCounter <= dataCounter + 4'd1;
                end else begin
                    state <= STATE_STOP;
                    firstStopBitReceived <= 1'b0;
                end
            STATE_STOP:
                if(rx == 1'b1) begin
                    if(!extraStopBit || firstStopBitReceived) begin
                        state <= STATE_IDLE;
                        if(dataReceived)
                            overflow <= 1'b1;
                        dataReceived <= 1'b1;
                        dataOut <= currentData;
                        parityError <= currentParityError;
                        break <= 1'b0;
                    end
                    firstStopBitReceived <= 1'b1;
                end else begin
                    break <= 1'b1;
                    state <= STATE_IDLE;
                end
        endcase
    end

    // TODO add parity
endmodule
