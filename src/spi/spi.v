module Spi(
    input clk,
    input rst,

    input wbCycI,
    input wbStbI,
    input wbWeI,
    output reg wbAckO,
    input [1:0] wbAdrI,
    input [15:0] wbDatI,
    output reg [15:0] wbDatO,

    inout sck,
    input ss,
    input miso,
    output mosi
);

    localparam ADDR_DATA = 2'd0;
    localparam ADDR_DIVISOR = 2'd1;
    localparam ADDR_STATUS = 2'd2;
    localparam ADDR_CONFIG = 2'd3;

    reg [15:0] regData = 16'd0;
    reg [15:0] regStatus = 16'd0;
    reg [15:0] regConfig = 16'd0;
    reg [15:0] regDivisor = 16'd0;

    /* Wishbone begin */
    always @(negedge clk) begin
        if(rst) begin
            wbAckO <= 1'b0;
        end else begin
            if(wbCycI && wbStbI) begin
                if(wbWeI) begin
                    case(wbAdrI)
                        ADDR_DATA: regData <= wbDatI;
                        ADDR_DIVISOR: regDivisor <= wbDatI;
                        ADDR_STATUS: regStatus <= wbDatI;
                        ADDR_CONFIG: regConfig <= wbDatI;
                    endcase
                end else begin
                    case(wbAdrI)
                        ADDR_DATA: wbDatO <= regData;
                        ADDR_DIVISOR: wbDatO <= regDivisor;
                        ADDR_STATUS: wbDatO <= regStatus;
                        ADDR_CONFIG: wbDatO <= regConfig;
                    endcase
                end
            end
            wbAckO <= wbCycI && wbStbI;
        end
    end
    /* Wishbone end */

    /* Transmission flag begin */
    reg transmissionFlag = 1'b0;
    always @(negedge clk) begin
        if(rst) begin
            transmissionFlag = 1'b0;
        end else begin
            if(wbCycI && wbStbI) begin
                if(wbWeI && wbAdrI == ADDR_DATA)
                    transmissionFlag <= 1'b1;
            end
        end
    end
    /* Transmission flag end */

    /* Slow clock begin */
    /* Slow clock end */
endmodule
