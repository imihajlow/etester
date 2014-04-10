module Port(
    input clk,
    input rst,

    input wbStbI,
    input wbCycI,
    input wbWeI,
    output reg wbAckO,

    input [DATA_WIDTH-1:0] wbDatI,
    output reg [DATA_WIDTH-1:0] wbDatO,
    input wbAdrI, // 0 - data, 1 - mode (0 - read, 1 - write)

    inout [DATA_WIDTH-1:0] port
);
    parameter DATA_WIDTH = 16;

    initial wbAckO = 1'b0;
    initial wbDatO = {DATA_WIDTH{1'b0}};
    reg [DATA_WIDTH-1:0] mode = {DATA_WIDTH{1'b0}};
    reg [DATA_WIDTH-1:0] data = {DATA_WIDTH{1'b0}};

    genvar i;
    generate
        for(i = 0; i < DATA_WIDTH; i = i + 1) begin : genblock
            assign port[i] = mode[i] ? data[i] : 1'bz;
        end
    endgenerate

    wire portIn = port;

    always @(negedge clk) begin
        if(rst) begin
            wbAckO <= 1'b0;
            mode <= {DATA_WIDTH{1'b0}};
            data <= {DATA_WIDTH{1'b0}};
            wbDatO <= {DATA_WIDTH{1'b0}};
        end else begin
            if(wbStbI && wbCycI) begin
                wbAckO <= 1'b1;
                case(wbAdrI)
                    1'b0: begin
                        if(wbWeI)
                            data <= wbDatI;
                        wbDatO <= portIn;
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

module InPort(
    input clk,
    input rst,

    input wbStbI,
    input wbCycI,
    input wbWeI,
    output reg wbAckO,

    output reg [DATA_WIDTH-1:0] wbDatO,
    
    input [DATA_WIDTH-1:0] port
);
    parameter DATA_WIDTH = 16;
    
    initial begin
        wbAckO = 1'b0;
        wbDatO = {DATA_WIDTH{1'b0}};
    end
    always @(negedge clk) begin
        if(rst) begin
            wbAckO <= 1'b0;
            wbDatO <= {DATA_WIDTH{1'b0}};
        end else begin
            wbAckO <= wbStbI & wbCycI;
            wbDatO <= port;
        end
    end
endmodule

module OutPort(
    input clk,
    input rst,

    input wbStbI,
    input wbCycI,
    input wbWeI,
    output reg wbAckO,

    output [DATA_WIDTH-1:0] wbDatO,
    input [DATA_WIDTH-1:0] wbDatI,
    
    output reg [DATA_WIDTH-1:0] port
);
    parameter DATA_WIDTH = 16;
    
    assign wbDatO = wbDatI;
    initial begin
        wbAckO = 1'b0;
        port = {DATA_WIDTH{1'b0}};
    end
    always @(negedge clk) begin
        if(rst) begin
            wbAckO <= 1'b0;
            port <= {DATA_WIDTH{1'b0}};
        end else begin
            wbAckO <= wbStbI & wbCycI;
            if(wbStbI & wbCycI & wbWeI)
                port <= wbDatI;
        end
    end
endmodule
