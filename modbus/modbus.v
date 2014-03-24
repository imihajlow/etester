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
    input [8:0] dataIn,
    input dataReceived,
    input parityError,
    input overflow,
    input silence,
    output receiveReq,

    // Output FIFO
    output fifoClk,
    input full,
    output writeReq,
    input writeAck,
    output [7:0] dataOut
);
    parameter ADDRESS_WIDTH = 24;
    parameter DATA_WIDTH = 16;

    parameter MODBUS_STATION_ADDRESS = 8'h37;
    parameter OFFSET_INPUT_REGISTERS = 'hA00000;
    parameter QUANTITY_INPUT_REGISTERS = 32;
    parameter OFFSET_HOLDING_REGISTERS = 'hA00000;
    parameter QUANTITY_HOLDING_REGISTERS = 32;

    assign uartClk = ~clk;
    assign fifoClk = ~clk;
    
    localparam RSTATE_ADDRESS = 0;
    localparam RSTATE_WAIT = 1;
    localparam RSTATE_FUNCTION = 2;
    localparam RSTATE_CRC_LO = 3;
    localparam RSTATE_CRC_HI = 4;
    localparam RSTATE_ADDRESS_LO = 5;
    localparam RSTATE_ADDRESS_HI = 6;
    localparam RSTATE_QUANTITY_LO = 7;
    localparam RSTATE_QUANTITY_HI = 8;


    localparam FUN_READ_COILS = 8'h01;
    localparam FUN_READ_DISCRETE_INPUTS = 8'h02;
    localparam FUN_READ_HOLDING_REGISTERS = 8'h03;
    localparam FUN_READ_INPUT_REGISTERS = 8'h04;

    localparam FUN_WRITE_SINGLE_REGISTER = 8'h06;

    reg [7:0] rstate = RSTATE_ADDRESS;


    /* Input CRC begin */
    wire [15:0] crc;
    reg [7:0] expectedCrcLo = 8'h0;
    wire [15:0] expectedCrc = {dataIn[7:0], expectedCrcLo};
    wire crcRst = rstate == RSTATE_ADDRESS || rstate == RSTATE_WAIT;
    reg crcEnabled = 1'b0;
    reg [7:0] crcData = 8'b0;
    Crc _crc(
        .data_in(crcData),
        .crc_en(crcEnabled),
        .crc_out(crc),
        .rst(crcRst),
        .clk(~clk)
    );
    always @(posedge clk) begin
        if(rst) begin
            crcEnabled <= 1'b0;
        end else begin
            if(rstate != RSTATE_CRC_LO && rstate != RSTATE_CRC_HI) begin
                crcEnabled <= dataReceived;
                crcData <= dataIn[7:0];
            end else
                crcEnabled <= 1'b0;
        end
    end
    /* Input CRC end */

    /* Receive begin */
    reg isFunctionSupported;
    reg isFunctionRead;
    reg isAddressValid;
    reg isQuantityValid;
    wire [15:0] tempQuantity = {quantityHi, dataIn[7:0]};
    wire [7:0] tempFunction = dataIn[7:0];
    reg [7:0] modbusFunction = 8'd0;
    always @(tempFunction, startAddress, tempQuantity) begin
        case(tempFunction)
            FUN_READ_COILS,
            FUN_READ_DISCRETE_INPUTS: begin
                isFunctionSupported = 1'b0;
                isFunctionRead = 1'b1;
            end
            FUN_READ_HOLDING_REGISTERS,
            FUN_READ_INPUT_REGISTERS: begin
                isFunctionSupported = 1'b1;
                isFunctionRead = 1'b1;
            end
            default: begin
                isFunctionSupported = 1'b0;
                isFunctionRead = 1'b0;
            end
        endcase

        case(modbusFunction)
            FUN_READ_COILS,
            FUN_READ_DISCRETE_INPUTS: begin
                isQuantityValid = tempQuantity <= 16'h07d0 && tempQuantity >= 16'h0001;
            end
            FUN_READ_HOLDING_REGISTERS,
            FUN_READ_INPUT_REGISTERS: begin
                isQuantityValid = tempQuantity <= 16'h007d && tempQuantity >= 16'h0001;
            end
            default: begin
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
            default: begin
                isAddressValid = 1'b0;
            end
        endcase
    end // always

    reg receiveReq = 1'b0;

    reg [7:0] startAddressLo = 8'h0;
    reg [7:0] startAddressHi = 8'h0;
    wire [15:0] startAddress = { startAddressHi, startAddressLo };
    
    reg [7:0] quantityLo = 8'h0;
    reg [7:0] quantityHi = 8'h0;
    wire [15:0] quantity = { quantityHi, quantityLo };

    reg processRequest = 1'b0;
    reg error = 1'b0;
    reg [7:0] exceptionCode = 8'h0;
    always @(posedge clk) begin
        if(rst) begin
            error <= 1'b0;
            exceptionCode <= 8'h0;
            processRequest <= 1'b0;
        end else begin
            if(silence) begin
                rstate <= RSTATE_ADDRESS;
            end else begin
                receiveReq <= dataReceived;
                if(dataReceived) begin
                    if(parityError)
                        rstate <= RSTATE_WAIT;
                    else begin
                        case(rstate)
                            RSTATE_ADDRESS: begin
                                if(dataIn[7:0] == MODBUS_STATION_ADDRESS) begin
                                    rstate <= RSTATE_FUNCTION;
                                end else begin
                                    rstate <= RSTATE_WAIT;
                                    $display("Modbus receive: unknown address %h", dataIn[7:0]);
                                end
                            end
                            RSTATE_FUNCTION: begin
                                modbusFunction <= dataIn[7:0];
                                if(isFunctionSupported) begin
                                    if(isFunctionRead) begin
                                        rstate <= RSTATE_ADDRESS_HI;
                                    end else begin
                                        $display("Function %h is not implemented", dataIn[7:0]);
                                        rstate <= RSTATE_WAIT;
                                    end
                                end else begin
                                    rstate <= RSTATE_WAIT;
                                    processRequest <= 1'b1;
                                    error <= 1'b1;
                                    exceptionCode <= 8'h1;
                                    $display("Unknown function %h", dataIn[7:0]);
                                end
                            end
                            RSTATE_CRC_LO: begin
                                expectedCrcLo <= dataIn[7:0];
                                rstate <= RSTATE_CRC_HI;
                            end
                            RSTATE_CRC_HI: begin
                                if(expectedCrc == crc) begin
                                    $display("CRC OK");
                                    processRequest <= 1'b1;
                                end else begin
                                    $display("CRC fail");
                                end
                                rstate <= RSTATE_ADDRESS;
                            end
                            RSTATE_ADDRESS_LO: begin
                                rstate <= RSTATE_QUANTITY_HI;
                                startAddressLo <= dataIn[7:0];
                            end
                            RSTATE_ADDRESS_HI: begin
                                rstate <= RSTATE_ADDRESS_LO;
                                startAddressHi <= dataIn[7:0];
                            end
                            RSTATE_QUANTITY_LO: begin
                                if(isAddressValid && isQuantityValid) begin
                                    rstate <= RSTATE_CRC_LO;
                                    quantityLo <= dataIn[7:0];
                                end else begin
                                    rstate <= RSTATE_WAIT;
                                    processRequest <= 1'b1;
                                    error <= 1'b1;
                                    if(~isQuantityValid) begin
                                        exceptionCode <= 8'h03;
                                        $display("Invalid quantity %h", tempQuantity);
                                    end else begin
                                        exceptionCode <= 8'h02;
                                        $display("Invalid address %h", startAddress);
                                    end
                                end
                            end
                            RSTATE_QUANTITY_HI: begin
                                rstate <= RSTATE_QUANTITY_LO;
                                quantityHi <= dataIn[7:0];
                            end
                            RSTATE_WAIT: ;
                            default: begin
                                $display("Unknown state %d", rstate);
                                rstate <= RSTATE_WAIT;
                            end
                        endcase
                    end // parityError
                end // dataReceived
            end // silence
        end
    end
    /* Receive end */

    /* Output CRC begin */
    wire [15:0] crcOut;
    wire crcOutRst = sstate == SSTATE_WAIT;
    reg [7:0] crcOutDataIn = 8'b0;
    Crc _crcOut(
        .data_in(dataOut),
        .crc_en(crcOutEnabled),
        .crc_out(crcOut),
        .rst(crcOutRst),
        .clk(~clk)
    );
    /* Output CRC end */

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
            FUN_READ_HOLDING_REGISTERS: begin
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

    
    /* Send begin */
    localparam SSTATE_WAIT = 0;
    localparam SSTATE_ADDRESS = 1;
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

    reg [7:0] sstate = SSTATE_WAIT;
    reg [7:0] dataOut = 8'h0;

    always @(posedge clk) begin
        if(rst) begin
            sstate <= SSTATE_WAIT;
            dataOut <= 8'h0;
        end else begin
            case(sstate)
                SSTATE_WAIT: begin
                    if(writeAck) begin
                        $display("writeAck during SSTATE_WAIT");
                    end
                    if(processRequest) begin
                        sstate <= SSTATE_BEGIN;
                        processRequest <= 1'b0;
                    end
                end
                SSTATE_BEGIN: begin
                    dataOut <= MODBUS_STATION_ADDRESS;
                    sstate <= SSTATE_FUNCTION;
                end
                SSTATE_CRC_LO: begin
                    if(writeAck) begin
                        dataOut <= crcOut[7:0];
                        sstate <= SSTATE_CRC_HI;
                    end
                end
                SSTATE_CRC_HI: begin
                    if(writeAck) begin
                        dataOut <= crcOut[15:8];
                        sstate <= SSTATE_END;
                    end
                end
                SSTATE_ADDRESS: begin
                    if(writeAck) begin
                        dataOut <= MODBUS_STATION_ADDRESS;
                        sstate <= SSTATE_FUNCTION;
                    end
                end
                SSTATE_FUNCTION: begin
                    if(writeAck) begin
                        if(error) begin
                            dataOut <= { 1'b1, modbusFunction[6:0] };
                            sstate <= SSTATE_ERROR_CODE;
                        end else begin
                            case(modbusFunction)
                                FUN_READ_HOLDING_REGISTERS,
                                FUN_READ_INPUT_REGISTERS: begin
                                    dataOut <= modbusFunction;
                                    sstate <= SSTATE_BYTE_COUNT;
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
                    if(writeAck) begin
                        dataOut <= exceptionCode;
                        sstate <= SSTATE_CRC_LO;
                    end
                end
                SSTATE_END: begin
                    if(writeAck) begin
                        sstate <= SSTATE_WAIT;
                    end
                end
                SSTATE_BYTE_COUNT: begin
                    if(writeAck) begin
                        dataOut <= byteCount;
                        sstate <= SSTATE_WB_READ;
                        wbCurrentAddress <= wbStartAddress;
                        if(byteCount == 8'd0) begin
                            $display("Error: zero byte count");
                        end
                    end
                end
                SSTATE_WB_READ: begin
                    if(writeAck) begin
                        sstate <= SSTATE_WB_WAIT_DATA_HI;
                        wbCurrentAddress <= wbCurrentAddress + 1;
                    end
                end
                SSTATE_WB_WAIT_DATA_HI: begin
                    if(wbAckI) begin
                        wbCurrentData <= wbDatI;
                        dataOut <= wbDatI[15:8];
                        sstate <= SSTATE_DATA_LO;
                    end
                end
                SSTATE_DATA_LO: begin
                    if(writeAck) begin
                        dataOut <= wbCurrentData[7:0];
                        if(wbCurrentAddress == wbEndAddress)
                            sstate <= SSTATE_CRC_LO;
                        else
                            sstate <= SSTATE_WB_READ;
                    end
                end
                default: sstate <= SSTATE_WAIT;
            endcase
        end // rst
    end
    /* Send end */

    /* crcOutEnabled begin */
    reg crcOutEnabled = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            crcOutEnabled <= 1'b0;
        end else begin
            case(sstate)
                SSTATE_BEGIN: crcOutEnabled <= 1'b1;
                SSTATE_WB_WAIT_DATA_HI: crcOutEnabled <= wbAckI;
                SSTATE_WB_READ,
                SSTATE_CRC_LO,
                SSTATE_CRC_HI: crcOutEnabled <= 1'b0;
                default: crcOutEnabled <= writeAck;
            endcase
        end
    end
    /* crcOutEnabled end */
    
    /* writeReq begin */
    reg writeReq = 1'b0;
    always @(posedge clk) begin
        if(rst) begin
            writeReq <= 1'b0;
        end else begin
            case(sstate)
                SSTATE_WAIT:
                    writeReq <= 1'b0;
                SSTATE_END,
                SSTATE_WB_READ:
                    writeReq <= ~writeAck;
                SSTATE_WB_WAIT_DATA_HI:
                    writeReq <= wbAckI;
                default:
                    writeReq <= 1'b1;
            endcase
        end
    end
    /* writeReq end */

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
                    if(writeAck) begin
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
