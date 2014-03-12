module ModbusSlave(
    input clk,
    input rst,

    // Read Fifo
    input empty,
    output readReq,
    input readAck,
    input [7:0] dataOut,

    // Write fifo
    input full,
    output writeReq,
    input writeAck,
    output [7:0] dataIn,
    
    input [7:0] stationAddress    
);

endmodule
