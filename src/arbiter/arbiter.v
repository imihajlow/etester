module Arbiter(
    input clk,
    input rst,

    input [MASTERS_COUNT-1:0] mCycI,
    input [MASTERS_COUNT-1:0] mStbI,
    input [MASTERS_COUNT-1:0] mWeI,
    output [MASTERS_COUNT-1:0] mAckO,
    input [ADDRESS_WIDTH*MASTERS_COUNT-1:0] mAdrIPacked,
    input [DATA_WIDTH*MASTERS_COUNT-1:0] mDatIPacked,
    output [DATA_WIDTH*MASTERS_COUNT-1:0] mDatOPacked,

    output reg sCycO,
    output reg sStbO,
    output reg sWeO,
    input sAckI,
    output [ADDRESS_WIDTH-1:0] sAdrO,
    input [DATA_WIDTH-1:0] sDatI,
    output [DATA_WIDTH-1:0] sDatO
);
    parameter MASTERS_WIDTH = 1;
    localparam MASTERS_COUNT = 1 << MASTERS_WIDTH;
    parameter ADDRESS_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    
    wire [ADDRESS_WIDTH-1:0] mAdrI [MASTERS_COUNT-1:0];
    wire [DATA_WIDTH-1:0] mDatI [MASTERS_COUNT-1:0];
    wire [DATA_WIDTH-1:0] mDatO [MASTERS_COUNT-1:0];

    genvar i;
    generate
        for(i = 0; i < MASTERS_COUNT; i = i + 1) begin : genblock
            assign mAdrI[i] = mAdrIPacked[ADDRESS_WIDTH*(i+1)-1:ADDRESS_WIDTH*i];
            assign mDatI[i] = mDatIPacked[DATA_WIDTH*(i+1)-1:DATA_WIDTH*i];
            assign mDatOPacked[DATA_WIDTH*(i+1)-1:DATA_WIDTH*i] = mDatO[i];
        end
    endgenerate

    reg [MASTERS_WIDTH-1:0] currentMaster = 0;

    wire currentStb = mStbI[currentMaster];
    wire currentCyc = mCycI[currentMaster];
    wire currentWe = mWeI[currentMaster];
    wire nextCyc = mCycI[currentMaster + {{(MASTERS_WIDTH-1){1'b0}}, 1'b1}];

    localparam STATE_RESET = 0;
    localparam STATE_NEXT = 1;
    localparam STATE_CYCLE = 2;
    reg [1:0] state = STATE_RESET;
    always @(negedge clk) begin
        if(rst) begin
            state <= STATE_RESET;
        end else begin
            case(state)
                STATE_RESET: begin
                    state <= STATE_NEXT;
                end
                STATE_NEXT: begin
                    if(nextCyc)
                        state <= STATE_CYCLE;
                end
                STATE_CYCLE: begin
                    if(!currentCyc)
                        state <= STATE_NEXT;
                end
                default: begin
                    state <= STATE_RESET;
                end
            endcase
        end
    end

    always @(negedge clk) begin
        if(rst) begin
            currentMaster <= 0;
        end else begin
            case(state)
                STATE_RESET: currentMaster <= 0;
                STATE_NEXT: currentMaster <= currentMaster + 1;
            endcase
        end
    end

    reg cycLatch = 1'b0;
    reg stbLatch = 1'b0;
    reg weLatch = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            cycLatch <= 1'b0;
            stbLatch <= 1'b0;
            weLatch <= 1'b0;
        end else begin
            case(state)
                STATE_RESET: begin
                    cycLatch <= 1'b0;
                    stbLatch <= 1'b0;
                    weLatch <= 1'b0;
                end
                STATE_CYCLE: begin
                    cycLatch <= currentCyc;
                    stbLatch <= currentStb;
                end
            endcase
        end
    end
    always @(*) begin
        case(state)
            STATE_CYCLE: begin
                sStbO = stbLatch & currentStb;
                sCycO = cycLatch & currentCyc;
                sWeO = weLatch & currentWe;
            end
            default: begin
                sStbO = 1'b0;
                sCycO = 1'b0;
                sWeO = 1'b0;
            end
        endcase
    end
    
    generate
        for(i = 0; i < MASTERS_COUNT; i = i + 1) begin : genblock1
            assign mAckO[i] = (state == STATE_CYCLE && currentMaster == i) ? sAckI : 1'b0;
            assign mDatO[i] = sDatI;
        end
    endgenerate
    assign sDatO = mDatI[currentMaster];
    assign sAdrO = mAdrI[currentMaster];
endmodule
