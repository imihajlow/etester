module UartTransmitter(
    input clk,
    input rst,
    output reg tx,
    input [1:0] dataBits, // data bits count = dataBits + 5
    input hasParity,
    input [1:0] parityMode, // 00 - space, 11 - mark, 10 - even, 01 - odd
    input extraStopBit,
    input [CLOCK_DIVISOR_WIDTH-1:0] clockDivisor, // F_clk = (clockDivisor + 1) * F_uartClk

    input [7:0] dataIn,
    input transmitData,
    output wire ready
);
    parameter CLOCK_DIVISOR_WIDTH=24;

    reg [11:0] dataOut = 12'b0;
    reg [CLOCK_DIVISOR_WIDTH-1:0] latchedClockDivisor = 0;
    reg transmitting = 1'b0;
    reg [3:0] bitsLeft = 4'd0;
    assign ready = ~transmitting;
    
    initial begin
        tx = 1'b1;
    end

    reg [CLOCK_DIVISOR_WIDTH-1:0] clockCounter = 0;
    wire uartClk = clockCounter > (latchedClockDivisor >> 1);
    always @(posedge clk) begin
        if(rst) begin
            clockCounter <= 0;
        end else begin
            if(transmitting) begin
                if(clockCounter != latchedClockDivisor)
                    clockCounter <= clockCounter + 1;
                else
                    clockCounter <= 0;
            end else
                clockCounter <= 0;
        end
    end

    wire parityOut = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            transmitting <= 1'b0;
            bitsLeft <= 4'd0;
            tx <= 1'b1;
        end else begin
            if(transmitting) begin
                if(bitsLeft == 4'd0) begin
                    transmitting <= 1'b0;
                    tx <= 1'b1;
                end else begin
                    bitsLeft <= bitsLeft - 4'b1;
                    tx <= dataOut[0];
                    dataOut <= {1'b0, dataOut[11:1]};
                end
            end else begin
                if(transmitData) begin
                    bitsLeft <= 4'd1 + 4'd5 + dataBits + hasParity + extraStopBit + 1;
                    transmitting <= 1'b1;
                end
                tx <= 1'b1;
            end
        end
    end
endmodule    
