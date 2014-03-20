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
    input full,
    output writeReq,
    output writeAck,
    output [10:0] dataOut
);
    parameter ADDRESS_WIDTH = 24;
    parameter DATA_WIDTH = 32;
    parameter MODBUS_STATION_ADDRESS = 37;

    assign uartClk = ~clk;
    
    localparam STATE_ADDRESS = 0;
    localparam STATE_WAIT = 1;
    localparam STATE_FUNCTION = 2;

    reg [7:0] modbusAddress = 8'd0;
    reg [7:0] modbusFunction = 8'd0;
    reg [7:0] state = STATE_ADDRESS;

    reg receiveReq = 1'b0;
    wire [15:0] crc;
    reg crcRst = 1'b0;
    reg crcEnabled = 1'b0;
    Crc _crc(
        .data_in(dataIn[7:0]),
        .crc_en(crcEnabled),
        .crc_out(crc),
        .rst(crcRst),
        .clk(clk)
    );

    always @(posedge clk) begin
        if(rst) begin
        end else begin
            if(silence) begin
                state <= STATE_ADDRESS;
            end else begin
                case(state)
                    STATE_ADDRESS: begin
                        if(dataReceived) begin
                            receiveReq <= 1'b1;
                            if(parityError)
                                state <= STATE_WAIT;
                            else if(dataIn[7:0] == MODBUS_STATION_ADDRESS)
                                state <= STATE_FUNCTION;
                            end
                        end
                    end
                    default: state <= STATE_ADDRESS;
                endcase
            end // silence
        end
    end

    always @(negedge clk) begin
        if(rst) begin
        end else begin
        end
    end
endmodule
