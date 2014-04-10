/* Команды:
    - записать значение в регистр:
        [1] [address] [value]
    - ждать значение в регистре и зафейлить тест, если не дождались:
        [2] [address] [bottom] [top] [timeout]
    - выждать паузу:
        [3] [timeout]
    - успешно завершить тест:
        [4]
*/
module Processor(
    input clk,
    input rst,

    // Wishbone
    output reg [ADDRESS_WIDTH-1:0] wbAdrO,
    output reg [15:0] wbDatO,
    input [15:0] wbDatI,
    output reg wbCycO,
    output reg wbStbO,
    output reg wbWeO,
    input wbAckI,
    
    input [15:0] controlReg,
    output [15:0] statusReg
);
    parameter TIMEOUT_CLOCK_DIVISOR = 1;
    parameter ADDRESS_WIDTH = 24;
    parameter PROGMEM_START = 'h10000;
    parameter PROGMEM_END   = 'h1FFFF;
    parameter REGMEM_START  = 'h00000;
    parameter REGMEM_END    = 'h0FFFF;

    localparam OPCODE_SET = 16'h0001;
    localparam OPCODE_WAIT = 16'h0002;
    localparam OPCODE_PAUSE = 16'h0003;
    localparam OPCODE_WIN = 16'h0004;

    function [15:0] instructionLength;
        input [15:0] opcode;
        begin
            case(opcode)
                OPCODE_SET: instructionLength = 16'd3;
                OPCODE_WAIT: instructionLength = 16'd5;
                OPCODE_PAUSE: instructionLength = 16'd2;
                OPCODE_WIN: instructionLength = 16'd1;
                default: instructionLength = 16'd1;
            endcase
        end
    endfunction

    /* controlReg begin */
    wire controlHalt = controlReg[0];
    /* controlReg end */

    /* statusReg begin */
    wire isRunning = state != STATE_HALT && !isFailed && !isSucceeded;
    wire isFailed = state == STATE_FAIL;
    wire isSucceeded = state == STATE_SUCCESS;
    assign statusReg = { 13'd0, isRunning, isFailed, isSucceeded };
    /* statusReg end */

    /* State machine begin */
    localparam STATE_HALT = 0;
    localparam STATE_FETCH_CMD_R = 1;
    localparam STATE_FETCH_CMD_A = 2;
    localparam STATE_FETCH_ADDR_A = 4;
    localparam STATE_FETCH_VAL_BOT_A = 6;
    localparam STATE_FETCH_VAL_TOP_A = 8;
    localparam STATE_FETCH_VAL_A = 9;
    localparam STATE_FETCH_TIME_A = 10;
    localparam STATE_WRITE_REG_A = 12;
    localparam STATE_READ_REG_A = 14;
    localparam STATE_WAIT = 15;
    localparam STATE_FAIL = 16;
    localparam STATE_SUCCESS = 17;

    reg [7:0] state = STATE_HALT;
    reg [7:0] nextState;

    wire [15:0] tempOpcode = wbDatI;
    wire [15:0] tempReg = wbDatI;

    always @(posedge clk) begin
        if(rst || controlHalt) begin
            state <= STATE_HALT;
        end else begin
            state <= nextState;
        end
    end
    always @(*) begin
        if(rst || controlHalt) begin
            nextState = STATE_HALT;
        end else begin
            case(state)
                STATE_HALT: begin
                    nextState = STATE_FETCH_CMD_R;
                end
                STATE_FETCH_CMD_R: begin
                    nextState = STATE_FETCH_CMD_A;
                end
                STATE_FETCH_CMD_A: begin
                    if(wbAckI) begin
                        case(tempOpcode)
                            OPCODE_SET,
                            OPCODE_WAIT: begin
                                nextState = STATE_FETCH_ADDR_A;
                            end
                            OPCODE_PAUSE: begin
                                nextState = STATE_FETCH_TIME_A;
                            end
                            OPCODE_WIN: begin
                                nextState = STATE_SUCCESS;
                            end
                            default: begin
                                nextState = STATE_FETCH_CMD_A;
                            end
                        endcase
                    end else
                        nextState = state;
                end
                STATE_FETCH_ADDR_A: begin
                    if(wbAckI) begin
                        case(opcode)
                            OPCODE_SET: nextState = STATE_FETCH_VAL_A;
                            OPCODE_WAIT: nextState = STATE_FETCH_VAL_BOT_A;
                            default: begin
                                $display("Automata error: bad opcode in STATE_FETCH_ADDR_A");
                                nextState = STATE_HALT;
                            end
                        endcase
                    end else
                        nextState = state;
                end
                STATE_FETCH_VAL_A: begin
                    if(wbAckI) begin
                        nextState = STATE_WRITE_REG_A;
                    end else
                        nextState = state;
                end
                STATE_FETCH_VAL_BOT_A: begin
                    if(wbAckI) begin
                        nextState = STATE_FETCH_VAL_TOP_A;
                    end else
                        nextState = state;
                end
                STATE_FETCH_VAL_TOP_A: begin
                    if(wbAckI) begin
                        nextState = STATE_FETCH_TIME_A;
                    end else
                        nextState = state;
                end
                STATE_FETCH_TIME_A: begin
                    if(wbAckI) begin
                        case(opcode)
                            OPCODE_PAUSE: nextState = STATE_WAIT;
                            OPCODE_WAIT: nextState = STATE_READ_REG_A;
                            default: begin
                                $display("Automata error: bad opcode in STATE_FETCH_TIME_A");
                                nextState = STATE_HALT;
                            end
                        endcase
                    end else
                        nextState = state;
                end
                STATE_WRITE_REG_A: begin
                    if(wbAckI)
                        nextState = STATE_FETCH_CMD_A;
                    else
                        nextState = state;
                end
                STATE_READ_REG_A: begin
                    if(wbAckI) begin
                        if(tempReg >= regBottom && tempReg <= regTop) begin
                            nextState = STATE_FETCH_CMD_A;
                        end else begin
                            if(timeout) begin
                                nextState = STATE_FAIL;
                            end else
                                nextState = state;
                        end
                    end else
                        nextState = state;
                end
            endcase
        end
    end
    /* State machine end */

    /* Wishbone begin */
    initial begin
        wbCycO = 1'b0;
        wbStbO = 1'b0;
        wbWeO = 1'b0;
        wbDatO = 16'd0;
        wbAdrO = 0;
    end
    always @(posedge clk) begin
        if(rst || controlHalt) begin
            wbCycO <= 1'b0;
            wbStbO <= 1'b0;
            wbWeO <= 1'b0;
            wbDatO <= 16'd0;
            wbAdrO <= 0;
        end else begin
            // wbWeO begin
            case(state)
                STATE_FETCH_VAL_A: begin
                    if(wbAckI) begin
                        wbWeO <= 1'b1;
                    end
                end
                STATE_WRITE_REG_A: begin
                    wbWeO <= ~wbAckI;
                end
                default: wbWeO <= 1'b0;
            endcase
            // wbWeO end

            // wbCycO and wbStbO begin
            case(state)
                STATE_HALT,
                STATE_WAIT,
                STATE_FAIL,
                STATE_SUCCESS: begin
                    wbCycO <= 1'b0;
                    wbStbO <= 1'b0;
                end

                STATE_FETCH_CMD_R,
                STATE_FETCH_ADDR_A,
                STATE_FETCH_VAL_A,
                STATE_FETCH_VAL_TOP_A,
                STATE_WRITE_REG_A,
                STATE_FETCH_VAL_BOT_A: begin
                    wbCycO <= 1'b1;
                    wbStbO <= 1'b1;
                end
                STATE_FETCH_TIME_A: begin
                    if(wbAckI) begin
                        if(opcode == OPCODE_PAUSE) begin
                            wbCycO <= 1'b0;
                            wbStbO <= 1'b0;
                        end else begin
                            wbCycO <= 1'b1;
                            wbStbO <= 1'b1;
                        end
                    end
                end
                STATE_FETCH_CMD_A: begin
                    if(wbAckI) begin
                        case(tempOpcode)
                            OPCODE_WIN: begin
                                wbCycO <= 1'b0;
                                wbStbO <= 1'b0;
                            end
                            default: begin
                                wbCycO <= 1'b1;
                                wbStbO <= 1'b1;
                            end
                        endcase
                    end
                end
                STATE_READ_REG_A: begin
                    if(wbAckI) begin
                        if(tempReg >= regBottom && tempReg <= regTop) begin
                            wbCycO <= 1'b1;
                            wbStbO <= 1'b1;
                        end else begin
                            if(timeout) begin
                                wbCycO <= 1'b0;
                                wbStbO <= 1'b0;
                            end
                        end
                    end
                end
                default: begin
                    wbCycO <= 1'b0;
                    wbStbO <= 1'b0;
                end
            endcase
            // wbCycO and wbStbO end

            // wbAdrO and wbDatO begin
            case(state)
                STATE_FETCH_CMD_R: begin
                    wbAdrO <= instructionPointer;
                end
                STATE_FETCH_CMD_A: begin
                    if(wbAckI) begin
                        wbAdrO <= instructionPointer + 1;
                    end
                end
                STATE_FETCH_ADDR_A: begin
                    if(wbAckI) begin
                        wbAdrO <= currentInstructionPointer + 2;
                    end
                end
                STATE_FETCH_VAL_A: begin
                    if(wbAckI) begin
                        wbAdrO <= regAddress;
                        wbDatO <= wbDatI;
                    end
                end
                STATE_FETCH_VAL_BOT_A: begin
                    if(wbAckI) begin
                        wbAdrO <= currentInstructionPointer + 3;
                    end
                end
                STATE_FETCH_VAL_TOP_A: begin
                    if(wbAckI) begin
                        wbAdrO <= currentInstructionPointer + 4;
                    end
                end
                STATE_FETCH_TIME_A: begin
                    if(wbAckI) begin
                        if(opcode == OPCODE_WAIT)
                            wbAdrO <= regAddress;
                    end
                end
                STATE_WRITE_REG_A: begin
                    if(wbAckI)
                        wbAdrO <= instructionPointer;
                end
                STATE_READ_REG_A: begin
                    if(wbAckI) begin
                        if(tempReg >= regBottom && tempReg <= regTop) begin
                            wbAdrO <= instructionPointer;
                        end
                    end
                end
            endcase
            // wbAdrO and wbDatO end
        end
    end
    /* Wishbone end */

    /* instructionPointer begin */
    reg [ADDRESS_WIDTH-1:0] instructionPointer = PROGMEM_START;
    reg [ADDRESS_WIDTH-1:0] currentInstructionPointer = PROGMEM_START;
    always @(posedge clk) begin
        if(rst || controlHalt) begin
            instructionPointer <= PROGMEM_START;
            currentInstructionPointer <= PROGMEM_START;
        end else begin
            case(state)
                STATE_HALT: begin
                    instructionPointer <= PROGMEM_START;
                end
                STATE_FETCH_CMD_A: begin
                    if(wbAckI) begin
                        instructionPointer <= instructionPointer + instructionLength(tempOpcode);
                        currentInstructionPointer <= instructionPointer;
                    end
                end
            endcase
        end
    end
    /* instructionPointer end */

    /* opcode begin */
    reg [15:0] opcode = 16'd0;
    always @(posedge clk) begin
        if(rst || controlHalt) begin
            opcode <= 16'd0;
        end else begin
            if(state == STATE_FETCH_CMD_A)
                opcode <= tempOpcode;
        end
    end
    /* opcode end */

    /* timeoutValue, regAddress, regBottom and regTop begin */
    reg [15:0] regBottom = 16'd0;
    reg [15:0] regTop = 16'd0;
    reg [15:0] regAddress = 16'd0;
    reg [15:0] timeoutValue = 16'd0;
    always @(posedge clk) begin
        if(rst || controlHalt) begin
            regBottom <= 16'd0;
            regTop <= 16'd0;
            regAddress <= 16'd0;
            timeoutValue <= 16'd0;
        end else begin
            if(state == STATE_FETCH_VAL_BOT_A && wbAckI)
                regBottom <= wbDatI;
            if(state == STATE_FETCH_VAL_TOP_A && wbAckI)
                regTop <= wbDatI;
            if(state == STATE_FETCH_ADDR_A && wbAckI)
                regAddress <= wbDatI;
            if(state == STATE_FETCH_TIME_A && wbAckI)
                timeoutValue <= wbDatI;
        end
    end
    /* timeoutValue, regAddress, regBottom and regTop end */

    /* timeout begin */
    wire timeout = timeoutCounter >= timeoutValue;
    reg [15:0] slowClockCounter = 16'd0;
    reg [15:0] timeoutCounter = 16'd0;
    always @(posedge clk) begin
        if(rst || controlHalt) begin
            slowClockCounter <= 16'd0;
        end else begin
            case(state)
                STATE_READ_REG_A,
                STATE_WAIT: begin
                    if(slowClockCounter == TIMEOUT_CLOCK_DIVISOR) begin
                        slowClockCounter <= 16'd0;
                        timeoutCounter <= timeoutCounter + 16'd1;
                    end else
                        slowClockCounter <= slowClockCounter + 16'd1;
                end
                default: begin
                    slowClockCounter <= 16'd0;
                    timeoutCounter <= 16'd0;
                end
            endcase
        end
    end
    /* timeout end */
endmodule
