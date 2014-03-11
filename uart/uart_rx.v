module UartReceiver(
    input clk,
    input rst,
    input rx,
    input [1:0] dataBits, // data bits count = dataBits + 5
    input hasParity,
    input [1:0] parityMode, // 00 - space, 11 - mark, 10 - even, 01 - odd
    input extraStopBit,
    input [CLOCK_DIVISOR_WIDTH-1:0] clockDivisor,

    output reg [8:0] dataOut,
    output reg dataReceived,
    output reg parityError,
    output reg overflow,
    output reg break,
    input receiveData
);
    parameter CLOCK_DIVISOR_WIDTH=24;
    localparam STATE_IDLE = 3'd0;
    localparam STATE_START = 3'd1;
    localparam STATE_DATA = 3'd2;
    localparam STATE_STOP = 3'd3;

    reg [2:0] state = STATE_IDLE;

    reg [1:0] latchedDataBits = 0;
    reg latchedHasParity = 0;
    reg [1:0] latchedParityMode = 0;
    reg latchedExtraStopBit = 0;
    reg [CLOCK_DIVISOR_WIDTH-1:0] latchedClockDivisor = 0;

    /* Slow clock begin */
    reg [CLOCK_DIVISOR_WIDTH-1:0] clockCounter = 0;
    wire uartClkEnabled = state != STATE_IDLE;
    reg uartClk = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            clockCounter <= 0;
        end else begin
            if(state == STATE_IDLE) begin
                clockCounter <= 0;
                uartClk <= 1'b0;
            end else begin
                if(!uartClkEnabled) begin
                    clockCounter <= 0;
                    uartClk <= 1'b0;
                end else begin
                    if(clockCounter != latchedClockDivisor)
                        clockCounter <= clockCounter + 1;
                    else begin
                        clockCounter <= 0;
                        uartClk <= ~uartClk;
                    end
                end
            end
        end
    end
    /* Slow clock end */

    always @(posedge clk) begin
        if(rst) begin
            dataOut <= 9'b0;
            dataReceived <= 1'b0;
            parityError <= 1'b0;
            overflow <= 1'b0;
            break <= 1'b0;
            state <= STATE_IDLE;
        end else begin
            if(state == STATE_IDLE) begin
                if(rx == 1'b0) begin
                    state <= STATE_START;
                    latchedDataBits <= dataBits;
                    latchedHasParity <= hasParity;
                    latchedParityMode <= parityMode;
                    latchedExtraStopBit <= extraStopBit;
                    latchedClockDivisor <= clockDivisor;
                end
            end
            if(receiveData) begin
                dataReceived <= 1'b0;
                overflow <= 1'b0;
                break <= 1'b0;
            end
        end
    end

    wire [3:0] totalDataBits = 4'd5 + latchedDataBits + latchedHasParity - 4'd1;
    reg [3:0] dataCounter = 4'd0;
    reg [8:0] currentData = 9'd0;

    reg firstStopBitReceived = 1'b0;
    wire currentParityError;

    always @(posedge uartClk) begin
        case(state)
            STATE_START:
                if(rx)
                    state <= STATE_IDLE;
                else begin
                    state <= STATE_DATA;
                    dataCounter <= 0;
                end
            STATE_DATA: begin
                    currentData[dataCounter] <= rx;
                    $display("@%t got bit %b", $time, rx);
                    if(dataCounter < totalDataBits) begin
                        dataCounter <= dataCounter + 4'd1;
                    end else begin
                        state <= STATE_STOP;
                        firstStopBitReceived <= 1'b0;
                    end
                end
            STATE_STOP:
                if(rx) begin
                    if(!latchedExtraStopBit || firstStopBitReceived) begin
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

    ParityChecker parityChecker(
        .data(currentData),
        .dataBits(latchedDataBits),
        .hasParity(latchedHasParity),
        .parityMode(latchedParityMode),
        .parityError(currentParityError)
    );
endmodule

module ParityChecker(
    input [8:0] data,
    input [1:0] dataBits, // data bits count = dataBits + 5
    input hasParity,
    input [1:0] parityMode,

    output reg parityError
);
    localparam PARITY_SPACE = 2'b00;
    localparam PARITY_ODD = 2'b01;
    localparam PARITY_EVEN = 2'b10;
    localparam PARITY_MARK = 2'b11;
    wire [8:0] dataMask = ~(~9'h0 << 5 + dataBits + hasParity);
    always @(data, dataBits, hasParity, parityMode, dataMask) begin
        if(!hasParity)
            parityError = 1'b0;
        else begin
            case(parityMode)
                PARITY_SPACE: parityError = data[5 + dataBits] == 1'b1;
                PARITY_MARK: parityError = data[5 + dataBits] == 1'b0;
                PARITY_EVEN: parityError = ^(data & dataMask);
                PARITY_ODD: parityError = ~^(data & dataMask);
            endcase
        end
    end
endmodule
