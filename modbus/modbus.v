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
    
    localparam STATE_ADDRESS = 0;
    localparam STATE_FUNCTION = 1;

    reg [7:0] modbusAddress = 8'd0;
    reg [7:0] modbusFunction = 8'd0;
    reg [7:0] state = STATE_ADDRESS;

    always @(posedge clk) begin
        if(rst) begin
        end else begin
        end
    end

    always @(negedge clk) begin
        if(rst) begin
        end else begin
        end
    end
endmodule
