module Port(
    input clk,
    input rst,

    input wbStbI,
    input wbCycI,
    input wbWeI,
    output wbAckO,

    input [DATA_WIDTH-1:0] wbDatI,
    output [DATA_WIDTH-1:0] wbDatO,
    input wbAdrI, // 0 - data, 1 - mode (0 - read, 1 - write)

    inout [DATA_WIDTH-1:0] port
);
    parameter DATA_WIDTH = 16;

    reg wbAckO;
    reg [DATA_WIDTH-1:0] wbDatO = {DATA_WIDTH{1'b0}};
    reg [DATA_WIDTH-1:0] mode = {DATA_WIDTH{1'b0}};
    reg [DATA_WIDTH-1:0] data = {DATA_WIDTH{1'b0}};

    genvar i;
    generate
        for(i = 0; i < DATA_WIDTH; i = i + 1) begin
            assign port[i] = mode[i] ? data[i] : 1'bz;
        end
    endgenerate

    always @(negedge clk) begin
        if(rst) begin
            mode <= {DATA_WIDTH{1'b0}};
            data <= {DATA_WIDTH{1'b0}};
        end else begin
            if(wbStbI && wbCycI) begin
                wbAckO <= 1'b1;
                case(wbAdrI)
                    1'b0: begin
                        if(wbWeI)
                            data <= wbDatI;
                        wbDatO <= port;
                    end
                    1'b1: begin
                        if(wbWeI)
                            mode <= wbDatI;
                        wbDatO <= mode;
                    end
                endcase
            end else begin
                wbAckO <= 1'b0;
            end
        end
    end
endmodule
