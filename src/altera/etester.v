module etester(
    output [3:0] leds,
    input [3:0] buttons,
    inout [7:0] gpio,
    input osc
);
    wire [7:0] rxDataOut;
    wire rxDataReceived;
    wire rxParityError;
    wire rxOverflow;
    wire rxBreak;
    wire rxSilence;
    wire rst = ~buttons[3];
    wire rx;
    wire tx;
    wire rxReceiveReq;

    assign gpio[4] = tx;
    assign rx = gpio[3];
    
    UartReceiver _r(
        .clk(mUartClk),
        .rst(rst),
        .rx(rx),

        .dataBits(2'b11),
        .hasParity(1'b0),
        .parityMode(2'b11),
        .extraStopBit(1'b0),
        .clockDivisor(24'd216),

        .dataOut(rxDataOut),
        .dataReceived(rxDataReceived),
        .parityError(rxParityError),
        .overflow(rxOverflow),
        .break(rxBreak),
        .silence(rxSilence), // 3 or more characters of rxSilence
        .receiveReq(rxReceiveReq)
    );
    
    
    wire txReady;
    wire txTransmitReq;
    wire [7:0] txData;
    UartTransmitter _t(
        .clk(~mFifoClk),
        .rst(rst),
        .tx(tx),
        .dataBits(2'b11), // data bits count = dataBits + 5
        .hasParity(1'b0),
        .parityMode(2'b11),
        .extraStopBit(1'b0),
        .clockDivisor(24'd216),

        .ready(txReady),
        .data(txData),
        .transmitReq(txTransmitReq)
    );
    
    wire fifoWriteReq, fifoWriteAck;
    wire fifoReadReq, fifoReadAck;
    wire [7:0] fifoDataIn, fifoDataOut;
    wire fifoEmpty, fifoFull;
    Fifo #(
        .DATA_WIDTH(8)
        ) _f(
        .clk(mFifoClk),
        .rst(rst),

        .empty(fifoEmpty),
        .full(fifoFull),
        .readReq(fifoReadReq),
        .readAck(fifoReadAck),
        .writeReq(fifoWriteReq),
        .writeAck(fifoWriteAck),
        .dataIn(fifoDataIn),
        .dataOut(fifoDataOut)
    );

    assign txTransmitReq = fifoReadAck;
    assign fifoReadReq = txReady;
    assign txData = fifoDataOut;

    wire [23:0] wbAdrO;
    wire [15:0] wbDatO;
    wire [15:0] wbDatI;
    wire wbCycO, wbStbO, wbAckI, wbWeO;

    wire mFifoClk, mUartClk;
    ModbusToWishbone _m(
        .clk(osc),
        .rst(rst),
        // Wishbone
        .wbAdrO(wbAdrO),
        .wbDatO(wbDatO),
        .wbDatI(wbDatI),
        .wbCycO(wbCycO),
        .wbStbO(wbStbO),
        .wbAckI(wbAckI),
        .wbWeO(wbWeO),

        // Input UART
        .uartClk(mUartClk),
        .uartDataIn(rxDataOut),
        .uartDataReceived(rxDataReceived),
        .parityError(rxParityError),
        .overflow(rxOverflow),
        .silence(rxSilence),
        .uartReceiveReq(rxReceiveReq),

        // Output FIFO
        .fifoClk(mFifoClk),
        .full(fifoFull),
        .fifoWriteReq(fifoWriteReq),
        .fifoWriteAck(fifoWriteAck),
        .fifoDataOut(fifoDataIn),
    );

    WishboneRegs _regs(
        .clk(osc),
        .rst(rst),
        .wbAdrI(wbAdrO),
        .wbDatI(wbDatO),
        .wbDatO(wbDatI),
        .wbStbI(wbStbO),
        .wbCycI(wbCycO),
        .wbWeI(wbWeO),
        .wbAckO(wbAckI)
    );
    
    assign leds[0] = ~rxSilence;
    assign leds[1] = ~rxBreak;
    assign leds[2] = ~rxOverflow;
    assign leds[3] = ~rxDataReceived;
endmodule

module WishboneRegs(
    input clk,
    input rst,
    input [23:0] wbAdrI,
    input [15:0] wbDatI,
    output reg [15:0] wbDatO,
    input wbStbI,
    input wbCycI,
    input wbWeI,
    output wbAckO
);
    parameter ADDR_OFFSET = 24'hA00000;
    reg [15:0] data[15:0];
    assign wbAckO = wbStbI & wbCycI;
    always @(negedge clk) begin
        if(wbStbI & wbCycI) begin
            if(wbWeI)
                data[wbAdrI - ADDR_OFFSET] <= wbDatI;
            else
                wbDatO <= data[wbAdrI - ADDR_OFFSET];
        end
    end
endmodule
