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
    localparam STATE_HALT = 'h0;
    localparam STATE_FETCH_CMD_R = 'h1;
    localparam STATE_FETCH_CMD_A = 'h2;
    localparam STATE_FETCH_ADDR_A = 'h3;
    localparam STATE_FETCH_VAL_BOT_A = 'h4;
    localparam STATE_FETCH_VAL_TOP_A = 'h5;
    localparam STATE_FETCH_VAL_A = 'h6;
    localparam STATE_FETCH_TIME_A = 'h7;
    localparam STATE_WRITE_REG_A = 'h8;
    localparam STATE_READ_REG_A = 'h9;
    localparam STATE_WAIT = 'ha;
    localparam STATE_FAIL = 'hb;
    localparam STATE_SUCCESS = 'hc;
    localparam STATE_READ_REG_R = 'hd;

    reg [7:0] state = STATE_HALT;
    reg [7:0] nextState;

    wire [15:0] realOpcode = (state == STATE_FETCH_CMD_A) ? tempOpcode : opcode;
    wire [15:0] tempOpcode = wbDatI;
    wire [15:0] tempReg = wbDatI;

    wire [15:0] realRegValue = (state == STATE_FETCH_VAL_A) ? wbDatI : regValue;

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
                                nextState = STATE_FETCH_CMD_R;
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
                            OPCODE_WAIT: nextState = STATE_READ_REG_R;
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
                        nextState = STATE_FETCH_CMD_R;
                    else
                        nextState = state;
                end
                STATE_READ_REG_R: begin
                    nextState = STATE_READ_REG_A;
                end
                STATE_READ_REG_A: begin
                    if(wbAckI) begin
                        if(tempReg >= regBottom && tempReg <= regTop) begin
                            nextState = STATE_FETCH_CMD_R;
                        end else begin
                            if(timeout) begin
                                nextState = STATE_FAIL;
                            end else
                                nextState = STATE_READ_REG_R;
                        end
                    end else
                        nextState = state;
                end
                STATE_WAIT: begin
                    if(timeout)
                        nextState = STATE_FETCH_CMD_R;
                    else
                        nextState = state;
                end
                default: nextState = state;
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
            case(nextState)
                STATE_WRITE_REG_A: begin
                    wbWeO <= 1'b1;
                end
                default: wbWeO <= 1'b0;
            endcase
            // wbWeO end

            // wbCycO and wbStbO begin
            case(nextState)
                STATE_FETCH_CMD_A,
                STATE_FETCH_ADDR_A,
                STATE_FETCH_VAL_A,
                STATE_FETCH_VAL_BOT_A,
                STATE_FETCH_VAL_TOP_A,
                STATE_FETCH_TIME_A,
                STATE_WRITE_REG_A,
                STATE_READ_REG_A: begin
                    wbCycO <= 1'b1;
                    wbStbO <= 1'b1;
                end
                default: begin
                    wbCycO <= 1'b0;
                    wbStbO <= 1'b0;
                end
            endcase
            // wbCycO and wbStbO end

            // wbAdrO and wbDatO begin
            case(nextState)
                STATE_FETCH_CMD_A: begin
                    wbAdrO <= instructionPointer;
                end
                STATE_FETCH_ADDR_A: begin
                    wbAdrO <= instructionPointer + 1;
                end
                STATE_FETCH_VAL_A: begin
                    wbAdrO <= currentInstructionPointer + 2;
                end
                STATE_FETCH_VAL_BOT_A: begin
                    wbAdrO <= currentInstructionPointer + 2;
                end
                STATE_FETCH_VAL_TOP_A: begin
                    wbAdrO <= currentInstructionPointer + 3;
                end
                STATE_FETCH_TIME_A: begin
                    case(realOpcode)
                        OPCODE_PAUSE: wbAdrO <= currentInstructionPointer + 1;
                        OPCODE_WAIT: wbAdrO <= currentInstructionPointer + 4;
                    endcase
                end
                STATE_WRITE_REG_A: begin
                    wbAdrO <= regAddress;
                    wbDatO <= realRegValue;
                end
                STATE_READ_REG_A: begin
                    wbAdrO <= regAddress;
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

    /* timeoutValue, regValue, regAddress, regBottom and regTop begin */
    reg [15:0] regBottom = 16'd0;
    reg [15:0] regTop = 16'd0;
    reg [15:0] regAddress = 16'd0;
    reg [15:0] timeoutValue = 16'd0;
    reg [15:0] regValue = 16'd0;
    always @(posedge clk) begin
        if(rst || controlHalt) begin
            regBottom <= 16'd0;
            regTop <= 16'd0;
            regAddress <= 16'd0;
            timeoutValue <= 16'd0;
            regValue <= 16'd0;
        end else begin
            if(state == STATE_FETCH_VAL_BOT_A && wbAckI)
                regBottom <= wbDatI;
            if(state == STATE_FETCH_VAL_TOP_A && wbAckI)
                regTop <= wbDatI;
            if(state == STATE_FETCH_ADDR_A && wbAckI)
                regAddress <= wbDatI;
            if(state == STATE_FETCH_TIME_A && wbAckI)
                timeoutValue <= wbDatI;
            if(state == STATE_FETCH_VAL_A && wbAckI)
                regValue <= wbDatI;
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
                STATE_READ_REG_R,
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
