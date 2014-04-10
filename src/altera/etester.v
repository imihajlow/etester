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
    wire clk;
    wire [23:0] clockDivisor;
    //assign clockDivisor = 24'd867; // 200 MHz
    //assign clockDivisor = 24'd433; // 100 Mhz
    assign clockDivisor = 24'd216; // 50 Mhz

    
    /* PLL begin */
    /*pll _pll(
        .areset(rst),
        .inclk0(osc),
        .c0(clk)
    );*/
    assign clk = osc;
    /* PLL end */


    /* UART begin */
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
        .clockDivisor(clockDivisor),

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
        .clockDivisor(clockDivisor),

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
    /* UART end */

    assign txTransmitReq = fifoReadAck;
    assign fifoReadReq = txReady;
    assign txData = fifoDataOut;


    wire [15:0] modbusAdrO;
    wire [15:0] modbusDatO;
    wire [15:0] modbusDatI;
    wire modbusCycO, modbusStbO, modbusAckI, modbusWeO;
    wire mFifoClk, mUartClk;
    ModbusToWishbone #(
        .ADDRESS_WIDTH(16),
        .OFFSET_INPUT_REGISTERS(16'd0),
        .QUANTITY_INPUT_REGISTERS(16'hffff),
        .OFFSET_HOLDING_REGISTERS(16'd0),
        .QUANTITY_HOLDING_REGISTERS(16'hffff)
    ) _m(
        .clk(clk),
        .rst(rst),
        // Wishbone
        .wbAdrO(modbusAdrO),
        .wbDatO(modbusDatO),
        .wbDatI(modbusDatI),
        .wbCycO(modbusCycO),
        .wbStbO(modbusStbO),
        .wbAckI(modbusAckI),
        .wbWeO(modbusWeO),

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
        .fifoDataOut(fifoDataIn)
    );
    assign modbusAckI = modbusStbO & modbusCycO;
    assign modbusDatI = 16'ha5;

    /*wire [15:0] procAdrO;
    wire [15:0] procDatO;
    wire [15:0] procDatI;
    wire procCycO, procStbO, procAckI, procWeO;

    wire [15:0] controlReg = 16'b0001;
    wire [15:0] statusReg;
    Processor #(
        .ADDRESS_WIDTH(16),
        .PROGMEM_START(16'h8000),
        .PROGMEM_END(16'hffff),
        .REGMEM_START(16'h0000),
        .REGMEM_END(16'h7fff)
    ) _p(
        .clk(clk),
        .rst(rst),

        // Wishbone
        .wbAdrO(procAdrO),
        .wbDatO(procDatO),
        .wbDatI(procDatI),
        .wbCycO(procCycO),
        .wbStbO(procStbO),
        .wbWeO(procWeO),
        .wbAckI(procAckI),
        
        .controlReg(controlReg),
        .statusReg(statusReg)
    );

    wire [1:0] mCycI = { procCycO, modbusCycO };
    wire [1:0] mStbI = { procStbO, modbusStbO };
    wire [1:0] mWeI = { procWeO, modbusWeO };
    wire [1:0] mAckO;
    assign procAckI = mAckO[1];
    assign modbusAckI = mAckO[0];
    wire [31:0] mAdrIPacked = { procAdrO, modbusAdrO };
    wire [31:0] mDatIPacked = { procDatO, modbusDatO };
    wire [31:0] mDatOPacked;
    assign procDatI = mDatOPacked[31:16];
    assign modbusDatI = mDatOPacked[15:0];

    wire [15:0] wbAdrO;
    wire [15:0] wbDatO;
    reg [15:0] wbDatI;
    wire wbCycO, wbStbO, wbWeO;
    reg wbAckI;

    Arbiter #(
        .MASTERS_WIDTH(1),
        .ADDRESS_WIDTH(16),
        .DATA_WIDTH(16)
    ) _a(
        .clk(clk),
        .rst(rst),

        .mCycI(mCycI),
        .mStbI(mStbI),
        .mWeI(mWeI),
        .mAckO(mAckO),
        .mAdrIPacked(mAdrIPacked),
        .mDatIPacked(mDatIPacked),
        .mDatOPacked(mDatOPacked),

        .sCycO(wbCycO),
        .sStbO(wbStbO),
        .sWeO(wbWeO),
        .sAckI(wbAckI),
        .sAdrO(wbAdrO),
        .sDatI(wbDatI),
        .sDatO(wbDatO)
    );*/

    /* Slave multiplexing begin */
    /*wire selProgmem = wbAdrO[15];
    wire selRegmem = wbAdrO[15:14] == 2'b01;
    wire selPorts = wbAdrO[15:14] == 2'b00;
    
    always @(*) begin
        casex(wbAdrO[15:14])
            2'b1x: begin
                wbDatI = progmemDatO;
                wbAckI = progmemAckO;
            end
            2'b01: begin
                wbDatI = regmemDatO;
                wbAckI = regmemAckO;
            end
            2'b00: begin
                wbDatI = portsDatO;
                wbAckI = portsAckO;
            end
        endcase
    end
    */
    /* Slave multiplexing end */

    /* Memory begin */
    /*wire [15:0] progmemDatO;
    wire progmemAckO;
    WishboneRegs #(
        .ADDRESS_WIDTH(14)
    ) _progmem(
        .clk(clk),
        .rst(rst),
        .wbAdrI(wbAdrO[13:0]),
        .wbDatI(wbDatO),
        .wbDatO(progmemDatO),
        .wbStbI(wbStbO & selProgmem),
        .wbCycI(wbCycO & selProgmem),
        .wbWeI(wbWeO & selProgmem),
        .wbAckO(progmemAckO)
    );

    wire [15:0] regmemDatO;
    wire regmemAckO;
    WishboneRegs #(
        .ADDRESS_WIDTH(14)
    ) _regmem(
        .clk(clk),
        .rst(rst),
        .wbAdrI(wbAdrO[13:0]),
        .wbDatI(wbDatO),
        .wbDatO(regmemDatO),
        .wbStbI(wbStbO & selRegmem),
        .wbCycI(wbCycO & selRegmem),
        .wbWeI(wbWeO & selRegmem),
        .wbAckO(regmemAckO)
    );
    /* Memory end */

    /* Ports begin */
    //wire [15:0] portsDatO = 16'd0;
    //wire portsAckO = 1'b1;
    /*wire selPortLb = selPorts && wbAdrO[13:1] == 13'h0;
    wire selPortProcControl = selPorts && wbAdrO[13:0] == 13'h10;
    wire selPortProcStatus = selPorts && wbAdrO[13:0] == 13'h11;

    reg [15:0] portsDatO;
    reg portsAckO;
    always @(*) begin
        if(selPortLb) begin
            portsAckO = portLbAckO;
            portsDatO = portLbDatO;
        end else if(selPortProcStatus) begin
            portsAckO = portProcStatusAckO;
            portsDatO = portProcStatusDatO;
        end else begin
            portsAckO = 1'b1;
            portsDatO = 16'd0;
        end
    end

    wire [15:0] portLbDatO;
    wire portLbAckO;
    wire [15:0] portOutput;
    Port _portLb(
        .clk(clk),
        .rst(rst),

        .wbStbI(wbStbO & selPortLb),
        .wbCycI(wbCycO & selPortLb),
        .wbWeI(wbWeO & selPortLb),
        .wbAckO(portLbAckO),

        .wbDatI(wbDatI),
        .wbDatO(portLbDatO),
        .wbAdrI(wbAdrO[0]),

        .port(portOutput)
    );
    assign leds = ~portOutput[7:4];
    assign portOutput[3:0] = ~buttons;
    assign portOutput[15:8] = 8'h00;

    wire [15:0] portProcStatusDatO;
    wire portProcStatusAckO;
    InPort _portProcStatus(
        .clk(clk),
        .rst(rst),

        .wbStbI(wbStbO & selPortProcStatus),
        .wbCycI(wbCycO & selPortProcStatus),
        .wbWeI(wbWeO & selPortProcStatus),
        .wbAckO(portProcStatusAckO),

        .wbDatO(portProcStatusDatO),
        
        .port(statusReg)
    );*/
    /* Ports end */
    
    assign leds[0] = ~rxSilence;
    assign leds[1] = ~rxBreak;
    assign leds[2] = ~rxOverflow;
    assign leds[3] = ~rxDataReceived;
endmodule

module WishboneRegs(
    input clk,
    input rst,
    input [ADDRESS_WIDTH-1:0] wbAdrI,
    input [DATA_WIDTH-1:0] wbDatI,
    output reg [DATA_WIDTH-1:0] wbDatO,
    input wbStbI,
    input wbCycI,
    input wbWeI,
    output wbAckO
);
    parameter ADDRESS_WIDTH = 16;
    parameter DATA_WIDTH = 16;

    localparam MEMORY_SIZE = 1 << ADDRESS_WIDTH;
    reg [DATA_WIDTH-1:0] data[MEMORY_SIZE-1:0];
    assign wbAckO = wbStbI & wbCycI;
    always @(negedge clk) begin
        if(wbStbI & wbCycI) begin
            if(wbWeI)
                data[wbAdrI] <= wbDatI;
            else
                wbDatO <= data[wbAdrI];
        end
    end
endmodule
