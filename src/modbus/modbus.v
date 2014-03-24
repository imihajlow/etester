/*
*/
module ModbusToWishbone(
    input clk,
    input rst,
    // Wishbone
    output [ADDRESS_WIDTH-1:0] wbAdrO,
    output [DATA_WIDTH-1:0] wbDatO,
    input [DATA_WIDTH-1:0] wbDatI,
    output wbCycO,
    output wbStbO,
    input wbAckI,
    output wbWeO,

    // Input UART
    output uartClk,
    input [8:0] uartDataIn,
    input uartDataReceived,
    input parityError,
    input overflow,
    input silence,
    output uartReceiveReq,

    // Output FIFO
    output fifoClk,
    input full,
    output fifoWriteReq,
    input fifoWriteAck,
    output [7:0] fifoDataOut
);
    parameter ADDRESS_WIDTH = 24;
    parameter DATA_WIDTH = 16;

    parameter MODBUS_STATION_ADDRESS = 8'h37;
    parameter OFFSET_INPUT_REGISTERS = 'hA00000;
    parameter QUANTITY_INPUT_REGISTERS = 32;
    parameter OFFSET_HOLDING_REGISTERS = 'hA00000;
    parameter QUANTITY_HOLDING_REGISTERS = 32;
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
    localparam RSTATE_ADDRESS = 0;
    localparam RSTATE_WAIT = 1;
    localparam RSTATE_FUNCTION = 2;
    localparam RSTATE_CRC_LO = 3;
    localparam RSTATE_CRC_HI = 4;
    localparam RSTATE_ADDRESS_LO = 5;
    localparam RSTATE_ADDRESS_HI = 6;
    localparam RSTATE_QUANTITY_LO = 7;
    localparam RSTATE_QUANTITY_HI = 8;
    localparam RSTATE_DATA_LO = 9;
    localparam RSTATE_DATA_HI = 10;
    localparam RSTATE_BYTE_COUNT = 11;
    reg [7:0] rstate = RSTATE_ADDRESS;

    reg isTempFunctionSupported;
    reg isAddressValid;
    reg isTempQuantityValid;
    reg isQuantityValid;
    reg isTempByteCountValid;
    wire [15:0] tempQuantity = {quantityHi, uartDataIn[7:0]};
    wire [7:0] tempFunction = uartDataIn[7:0];
    wire [7:0] tempByteCount = uartDataIn[7:0];
    reg [7:0] modbusFunction = 8'd0;
    always @(tempFunction, startAddress, tempQuantity, quantity, tempByteCount) begin
        case(tempFunction)
            FUN_READ_COILS,
            FUN_READ_DISCRETE_INPUTS: begin
                isTempFunctionSupported = 1'b0;
            end
            FUN_READ_HOLDING_REGISTERS,
            FUN_READ_INPUT_REGISTERS: begin
                isTempFunctionSupported = 1'b1;
            end
            FUN_WRITE_MULTIPLE_REGISTERS: begin
                isTempFunctionSupported = 1'b1;
            end
            default: begin
                isTempFunctionSupported = 1'b0;
            end
        endcase

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

    reg uartReceiveReq = 1'b0;

    reg [7:0] startAddressLo = 8'h0;
    reg [7:0] startAddressHi = 8'h0;
    wire [15:0] startAddress = { startAddressHi, startAddressLo };
    
    reg [7:0] quantityLo = 8'h0;
    reg [7:0] quantityHi = 8'h0;
    wire [15:0] quantity = { quantityHi, quantityLo };

    reg [7:0] currentDataHi = 8'd0;
    wire [15:0] currentData = {currentDataHi, uartDataIn[7:0]};

    reg processRequest = 1'b0;
    reg error = 1'b0;
    reg [7:0] exceptionCode = 8'h0;
    always @(posedge clk) begin
        if(rst) begin
            error <= 1'b0;
            exceptionCode <= 8'h0;
            processRequest <= 1'b0;
            currentDataHi <= 8'd0;
        end else begin
            if(silence) begin
                rstate <= RSTATE_ADDRESS;
            end else begin
                uartReceiveReq <= uartDataReceived;
                if(uartDataReceived) begin
                    if(parityError)
                        rstate <= RSTATE_WAIT;
                    else begin
                        case(rstate)
                            RSTATE_ADDRESS: begin
                                if(uartDataIn[7:0] == MODBUS_STATION_ADDRESS) begin
                                    rstate <= RSTATE_FUNCTION;
                                end else begin
                                    rstate <= RSTATE_WAIT;
                                    $display("Modbus receive: unknown address %h", uartDataIn[7:0]);
                                end
                            end
                            RSTATE_FUNCTION: begin
                                modbusFunction <= uartDataIn[7:0];
                                if(isTempFunctionSupported) begin
                                    case(tempFunction)
                                        FUN_READ_HOLDING_REGISTERS,
                                        FUN_READ_INPUT_REGISTERS,
                                        FUN_WRITE_MULTIPLE_REGISTERS: begin
                                            rstate <= RSTATE_ADDRESS_HI;
                                        end
                                        default: begin
                                            $display("Function %h is not implemented", uartDataIn[7:0]);
                                            rstate <= RSTATE_WAIT;
                                        end
                                    endcase
                                end else begin
                                    rstate <= RSTATE_WAIT;
                                    processRequest <= 1'b1;
                                    error <= 1'b1;
                                    exceptionCode <= 8'h1;
                                    $display("Unknown function %h", uartDataIn[7:0]);
                                end
                            end
                            RSTATE_CRC_LO: begin
                                expectedCrcLo <= uartDataIn[7:0];
                                rstate <= RSTATE_CRC_HI;
                            end
                            RSTATE_CRC_HI: begin
                                if(expectedCrc == icrcOut) begin
                                    $display("CRC OK");
                                    processRequest <= 1'b1;
                                end else begin
                                    $display("CRC fail");
                                end
                                rstate <= RSTATE_ADDRESS;
                            end
                            RSTATE_ADDRESS_LO: begin
                                rstate <= RSTATE_QUANTITY_HI;
                                startAddressLo <= uartDataIn[7:0];
                            end
                            RSTATE_ADDRESS_HI: begin
                                rstate <= RSTATE_ADDRESS_LO;
                                startAddressHi <= uartDataIn[7:0];
                            end
                            RSTATE_QUANTITY_LO: begin
                                quantityLo <= uartDataIn[7:0];
                                case(modbusFunction)
                                    FUN_READ_HOLDING_REGISTERS,
                                    FUN_READ_INPUT_REGISTERS: begin
                                        if(isAddressValid && isTempQuantityValid) begin
                                            rstate <= RSTATE_CRC_LO;
                                        end else begin
                                            rstate <= RSTATE_WAIT;
                                            processRequest <= 1'b1;
                                            error <= 1'b1;
                                            if(~isTempQuantityValid) begin
                                                exceptionCode <= 8'h03;
                                                $display("Invalid quantity %h", tempQuantity);
                                            end else begin
                                                exceptionCode <= 8'h02;
                                                $display("Invalid address %h", startAddress);
                                            end
                                        end
                                    end
                                    FUN_WRITE_MULTIPLE_REGISTERS: begin
                                        rstate <= RSTATE_BYTE_COUNT;
                                        transactionBufferWritePtr <= 7'd0;
                                    end
                                    default: begin
                                        rstate <= RSTATE_WAIT;
                                        $display("Unexpected unknown function %h", modbusFunction);
                                    end
                                endcase
                            end
                            RSTATE_QUANTITY_HI: begin
                                rstate <= RSTATE_QUANTITY_LO;
                                quantityHi <= uartDataIn[7:0];
                            end
                            RSTATE_BYTE_COUNT: begin
                                case(modbusFunction)
                                    FUN_WRITE_MULTIPLE_REGISTERS: begin
                                        if(isAddressValid && isQuantityValid && isTempByteCountValid) begin
                                            rstate <= RSTATE_DATA_HI;
                                        end else begin
                                            rstate <= RSTATE_WAIT;
                                            processRequest <= 1'b1;
                                            error <= 1'b1;
                                            if(~isQuantityValid || ~isTempByteCountValid) begin
                                                exceptionCode <= 8'h03;
                                                $display("Invalid quantity %h or byte count %h", quantity, tempByteCount);
                                            end else begin
                                                exceptionCode <= 8'h02;
                                                $display("Invalid address %h", startAddress);
                                            end
                                        end
                                    end
                                    default: begin
                                        rstate <= RSTATE_WAIT;
                                        $display("Unexpected unknown function %h", modbusFunction);
                                    end
                                endcase
                            end
                            RSTATE_DATA_HI: begin
                                rstate <= RSTATE_DATA_LO;
                                currentDataHi <= uartDataIn[7:0];
                            end
                            RSTATE_DATA_LO: begin
                                transactionBuffer[transactionBufferWritePtr] <= currentData;
                                transactionBufferWritePtr <= transactionBufferWritePtr + 7'd1;
                                if(transactionBufferWritePtr == quantity[6:0] - 7'd1)
                                    rstate <= RSTATE_CRC_LO;
                                else
                                    rstate <= RSTATE_DATA_HI;
                            end
                            RSTATE_WAIT: ;
                            default: begin
                                $display("Unknown state %d", rstate);
                                rstate <= RSTATE_WAIT;
                            end
                        endcase
                    end // parityError
                end // uartDataReceived
            end // silence
        end
    end
    /* Receive end */

    /* Input CRC begin */
    wire [15:0] icrcOut;
    reg [7:0] expectedCrcLo = 8'h0;
    wire [15:0] expectedCrc = {uartDataIn[7:0], expectedCrcLo};
    wire icrcRst = rstate == RSTATE_ADDRESS || rstate == RSTATE_WAIT;
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
    reg [DATA_WIDTH-1:0] wbCurrentData = 0;
    always @(modbusFunction, quantity, startAddress) begin
        case(modbusFunction)
            FUN_READ_HOLDING_REGISTERS,
            FUN_WRITE_MULTIPLE_REGISTERS: begin
                wbStartAddress = OFFSET_HOLDING_REGISTERS + startAddress;
                wbEndAddress = OFFSET_HOLDING_REGISTERS + startAddress + quantity;
            end
            FUN_READ_INPUT_REGISTERS: begin
                wbStartAddress = OFFSET_INPUT_REGISTERS + startAddress;
                wbEndAddress = OFFSET_INPUT_REGISTERS + startAddress + quantity;
            end
            default: wbEndAddress = 0;
        endcase
    end
    /**/

    
    /* Transaction buffer begin*/
    reg [15:0] transactionBuffer [127:0];
    reg [6:0] transactionBufferWritePtr = 7'd0;
    reg [6:0] transactionBufferReadPtr = 7'd0;
    always @(posedge clk) begin
        if(rst) begin
            transactionBufferWritePtr <= 7'd0;
            transactionBufferReadPtr <= 7'd0;
        end
    end
    /* Transaction buffer end*/

    /* Send begin */
    localparam SSTATE_WAIT = 0;
    localparam SSTATE_STATION_ADDRESS = 1;
    localparam SSTATE_FUNCTION = 2;
    localparam SSTATE_ERROR_CODE = 3;
    localparam SSTATE_CRC_LO = 4;
    localparam SSTATE_CRC_HI = 5;
    localparam SSTATE_BEGIN = 6;
    localparam SSTATE_END = 7;
    localparam SSTATE_BYTE_COUNT = 8;
    localparam SSTATE_DATA_LO = 10;
    localparam SSTATE_WB_READ = 11;
    localparam SSTATE_WB_WAIT_DATA_HI = 12;
    localparam SSTATE_WB_WRITE = 13;
    localparam SSTATE_WB_WRITE_ACK = 14;
    localparam SSTATE_ADDRESS_HI = 15;
    localparam SSTATE_ADDRESS_LO = 16;
    localparam SSTATE_QUANTITY_HI = 17;
    localparam SSTATE_QUANTITY_LO = 18;

    reg [7:0] sstate = SSTATE_WAIT;
    reg [7:0] fifoDataOut = 8'h0;

    always @(posedge clk) begin
        if(rst) begin
            sstate <= SSTATE_WAIT;
            fifoDataOut <= 8'h0;
        end else begin
            case(sstate)
                SSTATE_WAIT: begin
                    if(fifoWriteAck) begin
                        $display("fifoWriteAck during SSTATE_WAIT");
                    end
                    if(processRequest) begin
                        case(modbusFunction)
                            FUN_READ_HOLDING_REGISTERS,
                            FUN_READ_INPUT_REGISTERS:
                                sstate <= SSTATE_BEGIN;
                            FUN_WRITE_MULTIPLE_REGISTERS: begin
                                sstate <= SSTATE_WB_WRITE;
                                transactionBufferReadPtr <= 7'd0;
                                wbCurrentAddress <= wbStartAddress;
                            end
                            default: begin
                                $display("Unexpected unknown function %h", modbusFunction);
                            end
                        endcase
                        processRequest <= 1'b0;
                    end
                end
                SSTATE_BEGIN: begin
                    fifoDataOut <= MODBUS_STATION_ADDRESS;
                    sstate <= SSTATE_FUNCTION;
                end
                SSTATE_CRC_LO: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= ocrcOut[7:0];
                        sstate <= SSTATE_CRC_HI;
                    end
                end
                SSTATE_CRC_HI: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= ocrcOut[15:8];
                        sstate <= SSTATE_END;
                    end
                end
                SSTATE_STATION_ADDRESS: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= MODBUS_STATION_ADDRESS;
                        sstate <= SSTATE_FUNCTION;
                    end
                end
                SSTATE_FUNCTION: begin
                    if(fifoWriteAck) begin
                        if(error) begin
                            fifoDataOut <= { 1'b1, modbusFunction[6:0] };
                            sstate <= SSTATE_ERROR_CODE;
                        end else begin
                            fifoDataOut <= modbusFunction;
                            case(modbusFunction)
                                FUN_READ_HOLDING_REGISTERS,
                                FUN_READ_INPUT_REGISTERS: begin
                                    sstate <= SSTATE_BYTE_COUNT;
                                end
                                FUN_WRITE_MULTIPLE_REGISTERS: begin
                                    sstate <= SSTATE_ADDRESS_HI;
                                end
                                default: begin
                                    $display("Function %h is not implemented", modbusFunction);
                                    sstate <= SSTATE_WAIT;
                                end
                            endcase
                        end
                    end
                end
                SSTATE_ERROR_CODE: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= exceptionCode;
                        sstate <= SSTATE_CRC_LO;
                    end
                end
                SSTATE_END: begin
                    if(fifoWriteAck) begin
                        sstate <= SSTATE_WAIT;
                    end
                end
                SSTATE_BYTE_COUNT: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= byteCount;
                        sstate <= SSTATE_WB_READ;
                        wbCurrentAddress <= wbStartAddress;
                        if(byteCount == 8'd0) begin
                            $display("Error: zero byte count");
                        end
                    end
                end
                SSTATE_WB_READ: begin
                    if(fifoWriteAck) begin
                        sstate <= SSTATE_WB_WAIT_DATA_HI;
                        wbCurrentAddress <= wbCurrentAddress + 1;
                    end
                end
                SSTATE_WB_WAIT_DATA_HI: begin
                    if(wbAckI) begin
                        wbCurrentData <= wbDatI;
                        fifoDataOut <= wbDatI[15:8];
                        sstate <= SSTATE_DATA_LO;
                    end
                end
                SSTATE_DATA_LO: begin
                    if(fifoWriteAck) begin
                        fifoDataOut <= wbCurrentData[7:0];
                        if(wbCurrentAddress == wbEndAddress)
                            sstate <= SSTATE_CRC_LO;
                        else
                            sstate <= SSTATE_WB_READ;
                    end
                end
                SSTATE_WB_WRITE: begin
                    sstate <= SSTATE_WB_WRITE_ACK;
                    wbCurrentAddress <= wbCurrentAddress + 1;
                end
                SSTATE_WB_WRITE_ACK: begin
                    if(wbAckI) begin
                        if(wbCurrentAddress == wbEndAddress) begin
                            sstate <= SSTATE_BEGIN;
                        end else begin
                            wbCurrentAddress <= wbCurrentAddress + 1;
                        end
                    end
                end
                SSTATE_ADDRESS_HI: begin
                    fifoDataOut <= startAddressHi;
                    sstate <= SSTATE_ADDRESS_LO;
                end
                SSTATE_ADDRESS_LO: begin
                    fifoDataOut <= startAddressLo;
                    sstate <= SSTATE_QUANTITY_HI;
                end
                SSTATE_QUANTITY_HI: begin
                    fifoDataOut <= quantityHi;
                    sstate <= SSTATE_QUANTITY_LO;
                end
                SSTATE_QUANTITY_LO: begin
                    fifoDataOut <= quantityLo;
                    sstate <= SSTATE_CRC_LO;
                end
                default: sstate <= SSTATE_WAIT;
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
                SSTATE_WB_WAIT_DATA_HI: ocrcEnabled <= wbAckI;
                SSTATE_WB_READ,
                SSTATE_WB_WRITE,
                SSTATE_WB_WRITE_ACK,
                SSTATE_CRC_LO,
                SSTATE_CRC_HI: ocrcEnabled <= 1'b0;
                default: ocrcEnabled <= fifoWriteAck;
            endcase
        end
    end
    /* ocrcEnabled end */
    
    /* fifoWriteReq begin */
    reg fifoWriteReq = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            fifoWriteReq <= 1'b0;
        end else begin
            case(sstate)
                SSTATE_WAIT,
                SSTATE_WB_WRITE,
                SSTATE_WB_WRITE_ACK:
                    fifoWriteReq <= 1'b0;
                SSTATE_END,
                SSTATE_WB_READ:
                    fifoWriteReq <= ~fifoWriteAck;
                SSTATE_WB_WAIT_DATA_HI:
                    fifoWriteReq <= wbAckI;
                default:
                    fifoWriteReq <= 1'b1;
            endcase
        end
    end
    /* fifoWriteReq end */

    /* wishbone begin */
    reg [DATA_WIDTH-1:0] wbDatO = 0;
    reg [ADDRESS_WIDTH-1:0] wbAdrO = 0;
    reg wbCycO = 1'b0, wbStbO = 1'b0, wbWeO = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            wbCycO <= 1'b0;
            wbStbO <= 1'b0;
            wbWeO <= 1'b0;
            wbDatO <= 0;
            wbAdrO <= 0;
        end else begin
            case(sstate)
                SSTATE_WB_READ: begin
                    if(fifoWriteAck) begin
                        wbCycO <= 1'b1;
                        wbStbO <= 1'b1;
                        wbWeO <= 1'b0;
                        wbAdrO <= wbCurrentAddress;
                    end
                end
                SSTATE_WB_WAIT_DATA_HI: begin
                    if(wbAckI) begin
                        wbCycO <= 1'b0;
                        wbStbO <= 1'b0;
                        wbWeO <= 1'b0;
                    end
                end
                SSTATE_WB_WRITE: begin
                    wbCycO <= 1'b1;
                    wbStbO <= 1'b1;
                    wbAdrO <= wbCurrentAddress;
                    wbWeO <= 1'b1;
                    wbDatO <= transactionBuffer[transactionBufferReadPtr];
                    transactionBufferReadPtr <= transactionBufferReadPtr + 7'd1;
                end
                SSTATE_WB_WRITE_ACK: begin
                    if(wbAckI) begin
                        if(wbCurrentAddress == wbEndAddress) begin
                            wbCycO <= 1'b0;
                            wbWeO <= 1'b0;
                            wbStbO <= 1'b0;
                        end else begin
                            wbCycO <= 1'b1;
                            wbStbO <= 1'b1;
                            wbAdrO <= wbCurrentAddress;
                            wbWeO <= 1'b1;
                            wbDatO <= transactionBuffer[transactionBufferReadPtr];
                            transactionBufferReadPtr <= transactionBufferReadPtr + 7'd1;
                        end
                    end
                end
                default: begin
                    wbCycO <= 1'b0;
                    wbStbO <= 1'b0;
                    wbWeO <= 1'b0;
                end
            endcase
        end
    end
    /* wishbone end */


    // TODO Задерживать обработку входящего запроса при не до конца отправленном ответе

    always @(negedge clk) begin
        if(rst) begin
        end else begin
        end
    end
endmodule
