module ModbusToWishbone(
    input clk,
    input rst,
    // Wishbone
    output [ADDRESS_WIDTH-1:0] adr_o,
    output [DATA_WIDTH-1:0] dat_o,
    input [DATA_WIDTH-1:0] dat_i,
    output cyc_o,
    output stb_o,
    input ack_i,
    output we_o,

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
    parameter DATA_WIDTH = 32;
    parameter MODBUS_STATION_ADDRESS = 8'h37;

    assign uartClk = ~clk;
    assign fifoClk = ~clk;
    
    localparam RSTATE_ADDRESS = 0;
    localparam RSTATE_WAIT = 1;
    localparam RSTATE_FUNCTION = 2;
    localparam RSTATE_CRC0 = 3;
    localparam RSTATE_CRC1 = 4;

    localparam SSTATE_WAIT = 0;
    localparam SSTATE_ADDRESS = 1;
    localparam SSTATE_FUNCTION = 2;
    localparam SSTATE_ERROR_CODE = 3;
    localparam SSTATE_CRC0 = 4;
    localparam SSTATE_CRC1 = 5;
    localparam SSTATE_BEGIN = 6;
    localparam SSTATE_END = 7;

    localparam FUN_WRITE_SINGLE_REGISTER = 8'h06;

    reg [7:0] modbusFunction = 8'd0;
    reg [7:0] rstate = RSTATE_ADDRESS;
    reg [7:0] sstate = SSTATE_WAIT;

    reg receiveReq = 1'b0;


    /* Input CRC begin */
    wire [15:0] crc;
    reg [7:0] expectedCrcLo = 8'h0;
    wire [15:0] expectedCrc = {dataIn[7:0], expectedCrcLo};
    wire crcRst = rstate == RSTATE_ADDRESS || rstate == RSTATE_WAIT;
    reg crcEnabled = 1'b0;
    Crc _crc(
        .data_in(dataIn[7:0]),
        .crc_en(crcEnabled),
        .crc_out(crc),
        .rst(crcRst),
        .clk(~clk)
    );
    always @(posedge clk) begin
        if(rst) begin
            crcEnabled <= 1'b0;
        end else begin
            if(rstate != RSTATE_CRC0 && rstate != RSTATE_CRC1)
                crcEnabled <= dataReceived;
        end
    end
    /* Input CRC end */

    /* Output CRC begin */
    wire [15:0] crcOut;
    wire crcOutRst = sstate == SSTATE_WAIT;
    wire crcOutEnabled = writeAck && sstateNeg != SSTATE_CRC1 && sstateNeg != SSTATE_END;
    reg [7:0] crcOutDataIn = 8'b0;
    reg [7:0] sstateNeg = 8'b0;
    Crc _crcOut(
        .data_in(crcOutDataIn),
        .crc_en(crcOutEnabled),
        .crc_out(crcOut),
        .rst(crcOutRst),
        .clk(clk)
    );
    always @(negedge clk) begin
        sstateNeg <= sstate;
        crcOutDataIn <= dataOut;
    end
    /* Output CRC end */

    /* Receive begin */
    always @(posedge clk) begin
        if(rst) begin
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
                                    $display("My address");
                                end else begin
                                    rstate <= RSTATE_WAIT;
                                    $display("Unknown address");
                                end
                            end
                            RSTATE_FUNCTION: begin
                                modbusFunction <= dataIn[7:0];
                                rstate <= RSTATE_WAIT;
                                sstate <= SSTATE_BEGIN;
                                error <= 1'b1;
                                exceptionCode <= 8'h1;
                                $display("Unknown function");
                            end
                            RSTATE_CRC0: begin
                                expectedCrcLo <= dataIn[7:0];
                                rstate <= RSTATE_CRC1;
                            end
                            RSTATE_CRC1: begin
                                if(expectedCrc == crc) begin
                                    $display("CRC OK");
                                    sstate <= SSTATE_BEGIN;
                                end else begin
                                    $display("CRC fail");
                                end
                                rstate <= RSTATE_ADDRESS;
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

    /* Send begin */
    reg [7:0] dataOut = 8'h0;
    assign writeReq = sstate != SSTATE_WAIT && sstate != SSTATE_BEGIN;

    reg error = 1'b0;
    reg [7:0] exceptionCode = 8'h0;
    always @(posedge clk) begin
        if(rst) begin
            sstate <= SSTATE_WAIT;
            error <= 1'b0;
            exceptionCode <= 8'h0;
            dataOut <= 8'h0;
        end else begin
            if(writeAck) begin
                case(sstate)
                    SSTATE_WAIT: begin
                        $display("writeAck during SSTATE_WAIT");
                    end
                    SSTATE_CRC0: begin
                        dataOut <= crcOut[7:0];
                        $display("crcOut[7:0] = %h", crcOut[7:0]);
                        sstate <= SSTATE_CRC1;
                    end
                    SSTATE_CRC1: begin
                        dataOut <= crcOut[15:8];
                        $display("crcOut[15:8] = %h", crcOut[15:8]);
                        sstate <= SSTATE_END;
                    end
                    SSTATE_ADDRESS: begin
                        dataOut <= MODBUS_STATION_ADDRESS;
                        sstate <= SSTATE_FUNCTION;
                    end
                    SSTATE_FUNCTION: begin
                        if(error) begin
                            dataOut <= { 1'b1, modbusFunction[6:0] };
                            sstate <= SSTATE_ERROR_CODE;
                        end else begin
                            $display("Success is not implemented");
                            sstate <= SSTATE_WAIT;
                        end
                    end
                    SSTATE_ERROR_CODE: begin
                        dataOut <= exceptionCode;
                        sstate <= SSTATE_CRC0;
                    end
                    SSTATE_END: begin
                        sstate <= SSTATE_WAIT;
                    end
                    default: sstate <= SSTATE_WAIT;
                endcase
            end else begin // writeAck
                case(sstate)
                    SSTATE_BEGIN: begin
                        $display("Transmission begin");
                        dataOut <= MODBUS_STATION_ADDRESS;
                        sstate <= SSTATE_FUNCTION;
                    end
                endcase
            end // writeAck
        end // rst
    end
    /* Send end */
    // TODO Задерживать обработку входящего запроса при не до конца отправленном ответе

    always @(negedge clk) begin
        if(rst) begin
        end else begin
        end
    end
endmodule
