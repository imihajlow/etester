module ClockDivisor(
    input clkIn,
    input rst,
    output reg clkOut,
    input [CLOCK_DIVISOR_WIDTH-1:0] clockDivisor,
);
    parameter CLOCK_DIVISOR_WIDTH=24;
    reg [CLOCK_DIVISOR_WIDTH-1:0] counter;
    initial begin
        counter = 0;
        clkOut = 0;
    end
    always @(posedge clkIn) begin
        if(rst) begin
            counter <= 0;
            clkOut <= 0;
        end else begin
            if(counter == clockDivisor) begin
                clkOut <= ~clkOut;
            end else begin
                counter <= counter + 1;
            end
        end
    end
endmodule
