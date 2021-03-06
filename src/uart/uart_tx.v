module UartTransmitter(
    input clk,
    input rst,
    output reg tx,
    input [1:0] dataBits, // data bits count = dataBits + 5
    input hasParity,
    input [1:0] parityMode, // 00 - space, 11 - mark, 10 - even, 01 - odd
    input extraStopBit,
    input [CLOCK_DIVISOR_WIDTH-1:0] clockDivisor,// f_uart = f_clk / (2 * clockDivisor + 2)

    output ready,
    input [7:0] data,
    input transmitReq
);
    parameter CLOCK_DIVISOR_WIDTH=24;
    localparam STATE_IDLE = 3'd0;
    localparam STATE_START = 3'd1;
    localparam STATE_DATA = 3'd2;
    localparam STATE_PAR = 3'd3;
    localparam STATE_STOP = 3'd4;
    localparam STATE_END = 3'd5;
    
    initial tx = 1'b1;
    assign ready = state == STATE_IDLE;

    reg [2:0] state = STATE_IDLE;

    reg [CLOCK_DIVISOR_WIDTH-1:0] clockCounter = 0;
    wire uartClkEnabled = state != STATE_IDLE;
    wire uartClk = (clockCounter == latchedClockDivisor << 1) && uartClkEnabled;
    always @(negedge clk) begin
        if(rst) begin
            clockCounter <= 0;
        end else begin
            if(state == STATE_IDLE) begin
                clockCounter <= 0;
            end else begin
                if(!uartClkEnabled) begin
                    clockCounter <= 0;
                end else begin
                    if(clockCounter != latchedClockDivisor << 1)
                        clockCounter <= clockCounter + 1;
                    else begin
                        clockCounter <= 0;
                    end
                end
            end
        end
    end
    
    wire parity;
    UartTxParity uartTxParity(
        .data(latchedData),
        .dataBits(latchedDataBits),
        .parityMode(latchedParityMode),
        .parity(parity)
    );
    reg [7:0] latchedData = 8'd0;
    reg [1:0] latchedDataBits = 2'd0;
    reg latchedHasParity = 1'b0;
    reg [1:0] latchedParityMode = 2'd0;
    reg latchedExtraStopBit = 1'b0;
    reg [CLOCK_DIVISOR_WIDTH-1:0] latchedClockDivisor = 0;

    reg firstStopBitTransmitted = 1'b0;
    reg [2:0] dataBitsRemaining = 3'd0;
    always @(posedge clk) begin
        if(rst) begin
            tx <= 1'b1;
            state <= STATE_IDLE;
            latchedData <= 8'd0;
        end else begin
            if(state == STATE_IDLE && transmitReq) begin
                state <= STATE_START;
                latchedData <= data;
                latchedDataBits <= dataBits;
                latchedHasParity <= hasParity;
                latchedParityMode <= parityMode;
                latchedExtraStopBit <= extraStopBit;
                latchedClockDivisor <= clockDivisor;
            end
            if(uartClk) begin
                case(state)
                    STATE_IDLE: tx <= 1'b1;
                    STATE_START: begin
                        tx <= 1'b0;
                        state <= STATE_DATA;
                        dataBitsRemaining <= latchedDataBits + 3'd4;
                    end
                    STATE_DATA: begin
                        tx <= latchedData[0];
                        latchedData <= latchedData >> 1;
                        dataBitsRemaining <= dataBitsRemaining - 1;
                        if(dataBitsRemaining == 3'd0) begin
                            if(latchedHasParity)
                                state <= STATE_PAR;
                            else
                                state <= STATE_STOP;
                        end
                    end
                    STATE_PAR: begin
                        tx <= parity;
                        state <= STATE_STOP;
                    end
                    STATE_STOP: begin
                        tx <= 1'b1;
                        firstStopBitTransmitted <= 1'b1;
                        if(firstStopBitTransmitted || !latchedExtraStopBit)
                            state <= STATE_END;
                    end
                    STATE_END: begin
                        tx <= 1'b1;
                        state <= STATE_IDLE;
                    end
                    default: state <= STATE_IDLE;
                endcase
            end // uartClk
        end // rst
    end
endmodule

module UartTxParity(
    input [7:0] data,
    input [1:0] dataBits,
    input [1:0] parityMode,
    output reg parity
);
    wire [7:0] mask = ~((~8'h00) << (dataBits + 5));
    always @(*) begin
        case(parityMode)
            2'b00: parity = 1'b0; // space
            2'b01: parity = ~^(data & mask); // odd
            2'b10: parity = ^(data & mask); // even
            2'b11: parity = 1'b1; // mark
        endcase
    end
endmodule
