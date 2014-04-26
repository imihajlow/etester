/*
*/
module ModbusToWishbone(
    input clk,
    input rst,
    // Wishbone
    output [ADDRESS_WIDTH-1:0] wbAdrO,
    output [DATA_WIDTH-1:0] wbDatO,
    input [DATA_WIDTH-1:0] wbDatI,
    output reg wbCycO,
    output reg wbStbO,
    input wbAckI,
    output reg wbWeO,

    // Input UART
    output uartClk,
    input [8:0] uartDataIn,
    input uartDataReceived,
    input parityError,
    input overflow,
    input silence,
    output reg uartReceiveReq,

    // Output FIFO
    output fifoClk,
    input full,
    output reg fifoWriteReq,
    input fifoWriteAck,
    output reg [7:0] fifoDataOut
);
    parameter ADDRESS_WIDTH = 24;
    parameter DATA_WIDTH = 16;

    parameter MODBUS_STATION_ADDRESS = 8'h37;
    parameter OFFSET_INPUT_REGISTERS = 'hA00000;
    parameter QUANTITY_INPUT_REGISTERS = 'hffff;
    parameter OFFSET_HOLDING_REGISTERS = 'hA00000;
    parameter QUANTITY_HOLDING_REGISTERS = 'hffff;
    parameter OFFSET_FILES = 'hB00000;

    localparam FUN_READ_COILS = 8'h01;
    localparam FUN_READ_DISCRETE_INPUTS = 8'h02;
    localparam FUN_READ_HOLDING_REGISTERS = 8'h03;
    localparam FUN_READ_INPUT_REGISTERS = 8'h04;
    localparam FUN_WRITE_SINGLE_REGISTER = 8'h06;
    localparam FUN_WRITE_MULTIPLE_REGISTERS = 8'h10;
    localparam FUN_READ_FILE_RECORD = 8'h14;
    localparam FUN_WRITE_FILE_RECORD = 8'h15;

    assign uartClk = ~clk;
    assign fifoClk = ~clk;

    /* Receive begin */
    localparam RSTATE_STATION_ADDRESS = 'h0;
    localparam RSTATE_WAIT = 'h1;
    localparam RSTATE_FUNCTION = 'h2;
    localparam RSTATE_CRC_LO = 'h3;
    localparam RSTATE_CRC_HI = 'h4;
    localparam RSTATE_ADDRESS_LO = 'h5;
    localparam RSTATE_ADDRESS_HI = 'h6;
    localparam RSTATE_QUANTITY_LO = 'h7;
    localparam RSTATE_QUANTITY_HI = 'h8;
    localparam RSTATE_DATA_LO = 'h9;
    localparam RSTATE_DATA_HI = 'hA;
    localparam RSTATE_BYTE_COUNT = 'hB;
    localparam RSTATE_ERROR = 'hC;
    localparam RSTATE_SUCCESS = 'hD;

    reg isAddressValid;
    reg isTempQuantityValid;
    reg isQuantityValid;
    reg isTempByteCountValid;
    wire [15:0] tempQuantity = {quantityHi, uartDataIn[7:0]};
    wire [7:0] tempFunction = uartDataIn[7:0];
    wire [7:0] tempByteCount = uartDataIn[7:0];
    reg [7:0] modbusFunction = 8'd0;
    always @(tempFunction, startAddress, tempQuantity, quantity, tempByteCount, modbusFunction) begin
        case(modbusFunction)
            FUN_READ_COILS,
            FUN_READ_DISCRETE_INPUTS: begin
                isTempQuantityValid = tempQuantity <= 16'h07d0 && tempQuantity >= 16'h0001;
                isQuantityValid = quantity <= 16'h07d0 && quantity >= 16'h0001;
            end
            FUN_READ_HOLDING_REGISTERS,
            FUN_READ_INPUT_REGISTERS: begin
                isTempQuantityValid = tempQuantity <= 16'h007d && tempQuantity >= 16'h0001;
                isQuantityValid = quantity <= 16'h007d && quantity >= 16'h0001;
            end
            FUN_WRITE_MULTIPLE_REGISTERS: begin
                isTempQuantityValid = tempQuantity <= 16'h007b && tempQuantity >= 16'h0001;
                isQuantityValid = quantity <= 16'h007b && quantity >= 16'h0001;
            end

            default: begin
                isTempQuantityValid = 1'b0;
                isQuantityValid = 1'b0;
            end
        endcase

        case(modbusFunction)
            FUN_READ_COILS,
            FUN_READ_DISCRETE_INPUTS: begin
                isAddressValid = 1'b0;
            end
            FUN_READ_HOLDING_REGISTERS: begin
                isAddressValid = startAddress + tempQuantity <= QUANTITY_HOLDING_REGISTERS;
            end
            FUN_READ_INPUT_REGISTERS: begin
                isAddressValid = startAddress + tempQuantity <= QUANTITY_INPUT_REGISTERS;
            end
            FUN_WRITE_MULTIPLE_REGISTERS: begin
                isAddressValid = startAddress + tempQuantity <= QUANTITY_HOLDING_REGISTERS;
            end
            default: begin
                isAddressValid = 1'b0;
            end
        endcase

        case(modbusFunction)
            FUN_WRITE_MULTIPLE_REGISTERS:
                isTempByteCountValid = tempByteCount == {quantity[6:0], 1'b0};
            default:
                isTempByteCountValid = 1'b0;
        endcase
    end // always

    /* uartReceiveReq begin */
    initial uartReceiveReq = 1'b0;
    always @(posedge clk) begin
        if(rst)
            uartReceiveReq <= 1'b0;
        else begin
            if(!silence) begin
                case(rstate)
                    RSTATE_SUCCESS,
                    RSTATE_ERROR,
                    RSTATE_WAIT: uartReceiveReq <= 1'b0;
                    default: uartReceiveReq <= uartDataReceived;
                endcase
            end
        end
    end
    /* uartReceiveReq end */

    reg [7:0] startAddressLo = 8'h0;
    reg [7:0] startAddressHi = 8'h0;
    wire [15:0] startAddress = { startAddressHi, startAddressLo };
    
    reg [7:0] quantityLo = 8'h0;
    reg [7:0] quantityHi = 8'h0;
    wire [15:0] quantity = { quantityHi, quantityLo };

    reg [7:0] currentDataHi = 8'd0;
    wire [15:0] currentData = {currentDataHi, uartDataIn[7:0]};

    /* processRequest begin */
    reg processRequest = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            processRequest <= 1'b0;
        end else begin
            if(processRequest && sstate == SSTATE_WAIT) begin
                processRequest <= 1'b0;
            end
            if(~silence && uartDataReceived && ~parityError) begin
                case(nextRstate)
                    RSTATE_ERROR,
                    RSTATE_SUCCESS: begin
                        processRequest <= 1'b1;
                    end
                endcase
            end
        end
    end
    /* processRequest end */

    always @(posedge clk) begin
        if(rst) begin
            currentDataHi <= 8'd0;
            transactionBufferWritePtr <= 7'd0;
        end else begin
            if(silence) begin
            end else begin
                if(uartDataReceived) begin
                    if(!parityError) begin
                        case(rstate)
                            RSTATE_STATION_ADDRESS: begin
                            end
                            RSTATE_FUNCTION: begin
                                modbusFunction <= uartDataIn[7:0];
                            end
                            RSTATE_CRC_LO: begin
                                expectedCrcLo <= uartDataIn[7:0];
                            end
                            RSTATE_CRC_HI: begin
                            end
                            RSTATE_ADDRESS_LO: begin
                                startAddressLo <= uartDataIn[7:0];
                            end
                            RSTATE_ADDRESS_HI: begin
                                startAddressHi <= uartDataIn[7:0];
                            end
                            RSTATE_QUANTITY_LO: begin
                                quantityLo <= uartDataIn[7:0];
                                case(modbusFunction)
                                    FUN_READ_HOLDING_REGISTERS,
                                    FUN_READ_INPUT_REGISTERS: begin
                                    end
                                    FUN_WRITE_MULTIPLE_REGISTERS: begin
                                        transactionBufferWritePtr <= 7'd0;
                                    end
                                    default: begin
                                    end
                                endcase
                            end
                            RSTATE_QUANTITY_HI: begin
                                quantityHi <= uartDataIn[7:0];
                            end
                            RSTATE_BYTE_COUNT: begin
                            end
                            RSTATE_DATA_HI: begin
                                currentDataHi <= uartDataIn[7:0];
                            end
                            RSTATE_DATA_LO: begin
                                transactionBuffer[transactionBufferWritePtr] <= currentData;
                                transactionBufferWritePtr <= transactionBufferWritePtr + 7'd1;
                            end
                            RSTATE_WAIT: ;
                            RSTATE_ERROR: ;
                            RSTATE_SUCCESS: ;
                            default: begin
                            end
                        endcase
                    end // parityError
                end // uartDataReceived
            end // silence
        end
    end
    /* rstate begin */
    reg [7:0] rstate = RSTATE_STATION_ADDRESS;
    always @(posedge clk) begin
        rstate <= nextRstate;
    end
    /* rstate end */

    /* error begin */
    reg error = 1'b0;
    reg [7:0] exceptionCode = 8'h0;
    always @(posedge clk) begin
        if(rst) begin
            error <= 1'b0;
            exceptionCode <= 8'h0;
        end else begin
            error <= asyncError;
            exceptionCode <= asyncExceptionCode;
        end
    end
    /* error end */

    /* nextRstate begin */
    reg [7:0] nextRstate;
    reg asyncError;
    reg [7:0] asyncExceptionCode;
    always @(*) begin
        nextRstate = rstate;
        asyncError = error;
        asyncExceptionCode = exceptionCode;
        if(rst) begin
            nextRstate = RSTATE_STATION_ADDRESS;
        end else begin
            if(silence) begin
                nextRstate = RSTATE_STATION_ADDRESS;
            end else begin
                if(uartDataReceived) begin
                    if(parityError)
                        nextRstate = RSTATE_WAIT;
                    else begin
                        case(rstate)
                            RSTATE_STATION_ADDRESS: begin
                                if(uartDataIn[7:0] == MODBUS_STATION_ADDRESS) begin
                                    nextRstate = RSTATE_FUNCTION;
                                end else begin
                                    nextRstate = RSTATE_WAIT;
                                end
                            end
                            RSTATE_FUNCTION: begin
                                case(tempFunction)
                                    FUN_READ_HOLDING_REGISTERS,
                                    FUN_READ_INPUT_REGISTERS,
                                    FUN_WRITE_MULTIPLE_REGISTERS: begin
                                        nextRstate = RSTATE_ADDRESS_HI;
                                    end
                                    default: begin
                                        $display("Function %h is not implemented", uartDataIn[7:0]);
                                        nextRstate = RSTATE_ERROR;
                                        asyncError = 1'b1;
                                        asyncExceptionCode = 8'h1;
                                    end
                                endcase
                            end
                            RSTATE_CRC_LO: begin
                                nextRstate = RSTATE_CRC_HI;
                            end
                            RSTATE_CRC_HI: begin
                                nextRstate = RSTATE_SUCCESS;
                            end
                            RSTATE_ADDRESS_LO: begin
                                nextRstate = RSTATE_QUANTITY_HI;
                            end
                            RSTATE_ADDRESS_HI: begin
                                nextRstate = RSTATE_ADDRESS_LO;
                            end
                            RSTATE_QUANTITY_LO: begin
                                case(modbusFunction)
                                    FUN_READ_HOLDING_REGISTERS,
                                    FUN_READ_INPUT_REGISTERS: begin
                                        if(isAddressValid && isTempQuantityValid) begin
                                            nextRstate = RSTATE_CRC_LO;
                                        end else begin
                                            nextRstate = RSTATE_ERROR;
                                            asyncError = 1'b1;
                                            if(~isTempQuantityValid) begin
                                                asyncExceptionCode = 8'h03;
                                            end else begin
                                                asyncExceptionCode = 8'h02;
                                            end
                                        end
                                    end
                                    FUN_WRITE_MULTIPLE_REGISTERS: begin
                                        nextRstate = RSTATE_BYTE_COUNT;
                                    end
                                    default: begin
                                        nextRstate = RSTATE_WAIT;
                                    end
                                endcase
                            end
                            RSTATE_QUANTITY_HI: begin
                                nextRstate = RSTATE_QUANTITY_LO;
                            end
                            RSTATE_BYTE_COUNT: begin
                                case(modbusFunction)
                                    FUN_WRITE_MULTIPLE_REGISTERS: begin
                                        if(isAddressValid && isQuantityValid && isTempByteCountValid) begin
                                            nextRstate = RSTATE_DATA_HI;
                                        end else begin
                                            nextRstate = RSTATE_ERROR;
                                            asyncError = 1'b1;
                                            if(~isQuantityValid || ~isTempByteCountValid) begin
                                                asyncExceptionCode = 8'h03;
                                            end else begin
                                                asyncExceptionCode = 8'h02;
                                            end
                                        end
                                    end
                                    default: begin
                                        nextRstate = RSTATE_WAIT;
                                    end
                                endcase
                            end
                            RSTATE_DATA_HI: begin
                                nextRstate = RSTATE_DATA_LO;
                            end
                            RSTATE_DATA_LO: begin
                                if(transactionBufferWritePtr == quantity[6:0] - 7'd1)
                                    nextRstate = RSTATE_CRC_LO;
                                else
                                    nextRstate = RSTATE_DATA_HI;
                            end
                            RSTATE_WAIT: ;
                            RSTATE_ERROR: begin
                                nextRstate = RSTATE_WAIT;
                            end
                            RSTATE_SUCCESS: begin
                                nextRstate = RSTATE_STATION_ADDRESS;
                            end
                            default: begin
                                $display("Unknown state %d", rstate);
                                nextRstate = RSTATE_WAIT;
                            end
                        endcase
                    end // parityError
                end // uartDataReceived
            end // silence
        end
    end
    /* nextRstate end */
    /* Receive end */

    /* Input CRC begin */
    wire [15:0] icrcOut;
    reg [7:0] expectedCrcLo = 8'h0;
    wire [15:0] expectedCrc = {uartDataIn[7:0], expectedCrcLo};
    wire icrcRst = rstate == RSTATE_STATION_ADDRESS || rstate == RSTATE_WAIT;
    reg icrcEnabled = 1'b0;
    reg [7:0] icrcData = 8'b0;
    Crc _crc(
        .data_in(icrcData),
        .crc_en(icrcEnabled),
        .crc_out(icrcOut),
        .rst(icrcRst),
        .clk(~clk)
    );
    always @(posedge clk) begin
        if(rst) begin
            icrcEnabled <= 1'b0;
        end else begin
            if(rstate != RSTATE_CRC_LO && rstate != RSTATE_CRC_HI) begin
                icrcEnabled <= uartDataReceived;
                icrcData <= uartDataIn[7:0];
            end else
                icrcEnabled <= 1'b0;
        end
    end
    /* Input CRC end */

    /**/
    reg [7:0] byteCount;
    always @(modbusFunction, quantity) begin
        case(modbusFunction)
            FUN_READ_HOLDING_REGISTERS,
            FUN_READ_INPUT_REGISTERS: byteCount = {quantity[6:0], 1'b0};
            default: byteCount = 8'd0;
        endcase
    end

    reg [ADDRESS_WIDTH-1:0] wbCurrentAddress = 0;
    reg [ADDRESS_WIDTH-1:0] wbStartAddress = 0;
    reg [ADDRESS_WIDTH-1:0] wbEndAddress = 0;
    always @(modbusFunction, quantity, startAddress) begin
        case(modbusFunction)
            FUN_READ_HOLDING_REGISTERS,
            FUN_WRITE_MULTIPLE_REGISTERS: begin
                wbStartAddress = OFFSET_HOLDING_REGISTERS + startAddress;
                wbEndAddress = OFFSET_HOLDING_REGISTERS + startAddress + quantity - 1;
            end
            FUN_READ_INPUT_REGISTERS: begin
                wbStartAddress = OFFSET_INPUT_REGISTERS + startAddress;
                wbEndAddress = OFFSET_INPUT_REGISTERS + startAddress + quantity - 1;
            end
            default: begin
                wbEndAddress = 0;
                wbStartAddress = 0;
            end
        endcase
    end
    /**/

    
    /* Transaction buffer begin*/
    reg [15:0] transactionBuffer [127:0];
    reg [6:0] transactionBufferWritePtr = 7'd0;
    reg [6:0] transactionBufferReadPtr = 7'd0;
    /* Transaction buffer end*/

    /* Send begin */
    localparam SSTATE_WAIT = 'h0;
    localparam SSTATE_STATION_ADDRESS = 'h1;
    localparam SSTATE_FUNCTION = 'h2;
    localparam SSTATE_ERROR_CODE = 'h3;
    localparam SSTATE_CRC_LO = 'h4;
    localparam SSTATE_CRC_HI = 'h5;
    localparam SSTATE_BEGIN = 'h6;
    localparam SSTATE_END = 'h7;
    localparam SSTATE_BYTE_COUNT = 'h8;
    localparam SSTATE_DATA_LO = 'ha;
    localparam SSTATE_WB_READ = 'hb;
    localparam SSTATE_DATA_HI = 'hc;
    localparam SSTATE_WB_WRITE_START = 'hd;
    localparam SSTATE_WB_WRITE = 'he;
    localparam SSTATE_ADDRESS_HI = 'hf;
    localparam SSTATE_ADDRESS_LO = 'h10;
    localparam SSTATE_QUANTITY_HI = 'h11;
    localparam SSTATE_QUANTITY_LO = 'h12;
    localparam SSTATE_WB_READ_START = 'h13;

    /* sstate begin */
    reg [7:0] sstate = SSTATE_WAIT;
    always @(posedge clk) begin
        sstate <= nextSstate;
    end
    /* sstate end */

    initial fifoDataOut = 8'h0;

    /* nextSstate begin */
    reg [7:0] nextSstate;
    always @(*) begin
        nextSstate = sstate;
        if(rst) begin
            nextSstate = SSTATE_WAIT;
        end else begin
            case(sstate)
                SSTATE_WAIT: begin
                    if(processRequest) begin
                        case(modbusFunction)
                            FUN_READ_HOLDING_REGISTERS,
                            FUN_READ_INPUT_REGISTERS:
                                nextSstate = SSTATE_BEGIN;
                            FUN_WRITE_MULTIPLE_REGISTERS: begin
                                nextSstate = SSTATE_WB_WRITE_START;
                            end
                        endcase
                    end
                end
                SSTATE_BEGIN: begin
                    nextSstate = SSTATE_FUNCTION;
                end
                SSTATE_CRC_LO: begin
                    if(fifoWriteAck) begin
                        nextSstate = SSTATE_CRC_HI;
                    end
                end
                SSTATE_CRC_HI: begin
                    if(fifoWriteAck) begin
                        nextSstate = SSTATE_END;
                    end
                end
                SSTATE_STATION_ADDRESS: begin
                    if(fifoWriteAck) begin
                        nextSstate = SSTATE_FUNCTION;
                    end
                end
                SSTATE_FUNCTION: begin
                    if(fifoWriteAck) begin
                        if(error) begin
                            nextSstate = SSTATE_ERROR_CODE;
                        end else begin
                            case(modbusFunction)
                                FUN_READ_HOLDING_REGISTERS,
                                FUN_READ_INPUT_REGISTERS: begin
                                    nextSstate = SSTATE_BYTE_COUNT;
                                end
                                FUN_WRITE_MULTIPLE_REGISTERS: begin
                                    nextSstate = SSTATE_ADDRESS_HI;
                                end
                                default: begin
                                    nextSstate = SSTATE_WAIT;
                                end
                            endcase
                        end
                    end
                end
                SSTATE_ERROR_CODE: begin
                    if(fifoWriteAck) begin
                        nextSstate = SSTATE_CRC_LO;
                    end
                end
                SSTATE_END: begin
                    if(fifoWriteAck) begin
                        nextSstate = SSTATE_WAIT;
                    end
                end
                SSTATE_BYTE_COUNT: begin
                    if(fifoWriteAck) begin
                        nextSstate = SSTATE_WB_READ_START;
                    end
                end
                SSTATE_WB_READ_START: begin
                    nextSstate = SSTATE_WB_READ;
                end
                SSTATE_WB_READ: begin
                    if(fifoWriteAck) begin
                        nextSstate = SSTATE_DATA_HI;
                    end
                end
                SSTATE_DATA_HI: begin
                    if(fifoWriteAck) begin
                        nextSstate = SSTATE_DATA_LO;
                    end
                end
                SSTATE_DATA_LO: begin
                    if(fifoWriteAck) begin
                        if(wbCurrentAddress == wbEndAddress)
                            nextSstate = SSTATE_CRC_LO;
                        else
                            nextSstate = SSTATE_WB_READ;
                    end
                end
                SSTATE_WB_WRITE_START: begin
                    nextSstate = SSTATE_WB_WRITE;
                end
                SSTATE_WB_WRITE: begin
                    if(wbAckI) begin
                        if(wbCurrentAddress == wbEndAddress) begin
                            nextSstate = SSTATE_BEGIN;
                        end
                    end
                end
                SSTATE_ADDRESS_HI: begin
                    if(fifoWriteAck)
                        nextSstate = SSTATE_ADDRESS_LO;
                end
                SSTATE_ADDRESS_LO: begin
                    if(fifoWriteAck)
                        nextSstate = SSTATE_QUANTITY_HI;
                end
                SSTATE_QUANTITY_HI: begin
                    if(fifoWriteAck)
                        nextSstate = SSTATE_QUANTITY_LO;
                end
                SSTATE_QUANTITY_LO: begin
                    if(fifoWriteAck)
                        nextSstate = SSTATE_CRC_LO;
                end
                default: nextSstate = SSTATE_WAIT;
            endcase
        end // rst
    end
    /* nextSstate begin */

    /* wbCurrentAddress, wbCurrentData begin */
    reg [DATA_WIDTH-1:0] wbCurrentData = 0;
    always @(posedge clk) begin
        if(rst) begin
        end else begin
            if(sstate == SSTATE_WB_READ && wbAckI)
                wbCurrentData <= wbDatI;
            case(sstate)
                SSTATE_WB_READ_START: begin
                    wbCurrentAddress <= wbStartAddress;
                end
                SSTATE_DATA_LO: begin
                    wbCurrentAddress <= wbCurrentAddress + 1;
                end
                SSTATE_WB_WRITE_START: begin
                    wbCurrentAddress <= wbStartAddress;
                end
                SSTATE_WB_WRITE: begin
                    if(wbAckI)
                        wbCurrentAddress <= wbCurrentAddress + 1;
                end
            endcase
        end // rst
    end
    /* wbCurrentAddress, wbCurrentData end */
    always @(posedge clk) begin
        if(rst) begin
            fifoDataOut <= 8'h0;
        end else begin
            case(sstate)
                SSTATE_WAIT: begin
                    if(fifoWriteAck) begin
                        $display("fifoWriteAck during SSTATE_WAIT");
                    end
                end
                SSTATE_BEGIN: begin
                    fifoDataOut <= MODBUS_STATION_ADDRESS;
                end
                SSTATE_CRC_LO: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= ocrcOut[7:0];
                    end
                end
                SSTATE_CRC_HI: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= ocrcOut[15:8];
                    end
                end
                SSTATE_STATION_ADDRESS: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= MODBUS_STATION_ADDRESS;
                    end
                end
                SSTATE_FUNCTION: begin
                    if(fifoWriteAck) begin
                        if(error) begin
                            fifoDataOut <= { 1'b1, modbusFunction[6:0] };
                        end else begin
                            fifoDataOut <= modbusFunction;
                        end
                    end
                end
                SSTATE_ERROR_CODE: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= exceptionCode;
                    end
                end
                SSTATE_BYTE_COUNT: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= byteCount;
                        if(byteCount == 8'd0) begin
                            $display("Error: zero byte count");
                        end
                    end
                end
                SSTATE_DATA_HI: begin
                    if(wbAckI) begin
                        fifoDataOut <= wbDatI[15:8];
                    end
                end
                SSTATE_DATA_LO: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= wbCurrentData[7:0];
                    end
                end
                SSTATE_ADDRESS_HI: begin
                    fifoDataOut <= startAddressHi;
                end
                SSTATE_ADDRESS_LO: begin
                    fifoDataOut <= startAddressLo;
                end
                SSTATE_QUANTITY_HI: begin
                    fifoDataOut <= quantityHi;
                end
                SSTATE_QUANTITY_LO: begin
                    fifoDataOut <= quantityLo;
                end
                default: ;
            endcase
        end // rst
    end
    /* Send end */


    /* Output CRC begin */
    wire [15:0] ocrcOut;
    wire ocrcRst = sstate == SSTATE_WAIT;
    Crc _crcOut(
        .data_in(fifoDataOut),
        .crc_en(ocrcEnabled),
        .crc_out(ocrcOut),
        .rst(ocrcRst),
        .clk(~clk)
    );
    /* Output CRC end */

    /* ocrcEnabled begin */
    reg ocrcEnabled = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            ocrcEnabled <= 1'b0;
        end else begin
            case(sstate)
                SSTATE_BEGIN: ocrcEnabled <= 1'b1;
                SSTATE_DATA_HI: ocrcEnabled <= wbAckI;
                SSTATE_WB_READ,
                SSTATE_WB_READ_START,
                SSTATE_WB_WRITE_START,
                SSTATE_WB_WRITE,
                SSTATE_CRC_LO,
                SSTATE_CRC_HI: ocrcEnabled <= 1'b0;
                default: ocrcEnabled <= fifoWriteAck;
            endcase
        end
    end
    /* ocrcEnabled end */
    
    /* fifoWriteReq begin */
    initial fifoWriteReq = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            fifoWriteReq <= 1'b0;
        end else begin
            case(sstate)
                SSTATE_WAIT,
                SSTATE_WB_READ_START,
                SSTATE_WB_READ,
                SSTATE_WB_WRITE_START,
                SSTATE_WB_WRITE:
                    fifoWriteReq <= 1'b0;
                SSTATE_END:
                    fifoWriteReq <= ~fifoWriteAck;
                default:
                    fifoWriteReq <= 1'b1;
            endcase
        end
    end
    /* fifoWriteReq end */

    /* wishbone begin */
    assign wbDatO = transactionBuffer[transactionBufferReadPtr];
    assign wbAdrO = wbCurrentAddress;
    always @(*) begin
        wbCycO = 1'b0;
        wbStbO = 1'b0;
        wbWeO = 1'b0;
        if(~rst) begin
            case(sstate)
                SSTATE_WB_READ: begin
                    wbCycO = 1'b1;
                    wbStbO = 1'b1;
                    wbWeO = 1'b0;
                end
                SSTATE_WB_WRITE: begin
                    wbCycO = 1'b1;
                    wbStbO = 1'b1;
                    wbWeO = 1'b1;
                end
            endcase
        end
    end
    /* wishbone end */
    
    always @(posedge clk) begin
        if(rst) begin
            transactionBufferReadPtr <= 7'd0;
        end else begin
            case(sstate)
                SSTATE_WB_WRITE_START: begin
                    transactionBufferReadPtr <= 7'd0;
                end
                SSTATE_WB_WRITE: begin
                    if(wbAckI) begin
                        transactionBufferReadPtr <= transactionBufferReadPtr + 7'd1;
                    end
                end
            endcase
        end
    end
endmodule
