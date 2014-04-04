module Spi(
    input clk,
    input rst,

    input wbCycI,
    input wbStbI,
    input wbWeI,
    output reg wbAckO,
    input [1:0] wbAdrI,
    input [16:0] wbDatI,
    output reg [16:0] wbDatO,

    inout sck,
    input ss,
    input miso,
    output mosi
);
endmodule
