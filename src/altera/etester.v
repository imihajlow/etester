module etester(
	output [3:0] leds,
	input [3:0] buttons,
	inout [7:0] gpio,
	input osc
);
	wire [7:0] uartDataOut;
	wire uartDataReceived;
	wire parityError;
	wire overflow;
	wire break;
	wire silence;
	wire rst = 1'b0;
	wire rx;
	wire tx;
	reg receiveReq = 1'b0;
	
	UartReceiver _r(
		.clk(~osc),
		.rst(rst),
		.rx(rx),
		.dataBits(2'b11),
		.hasParity(1'b0),
		.parityMode(2'b11),
		.extraStopBit(1'b0),
		.clockDivisor(24'd216),
		.dataOut(uartDataOut),
		.dataReceived(uartDataReceived),
		.parityError(parityError),
		.overflow(overflow),
		.break(break),
		.silence(silence), // 3 or more characters of silence
		.receiveReq(receiveReq)
	);
	
	/*assign leds[0] = ~silence;
	assign leds[1] = ~break;
	assign leds[2] = ~overflow;
	assign leds[3] = ~uartDataReceived;*/
	
	wire txReady;
	wire transmitReq;
	UartTransmitter _t(
    .clk(~osc),
    .rst(rst),
    .tx(tx),
    .dataBits(2'b11), // data bits count = dataBits + 5
    .hasParity(1'b0),
	 .parityMode(2'b11),
	 .extraStopBit(1'b0),
	 .clockDivisor(24'd216),

    .ready(txReady),
    .data(uartDataOut + 8'd1),
    .transmitReq(transmitReq)
	);
	
	assign transmitReq = receiveReq; //r; //transmitReq;
	reg [3:0] c;
	assign leds = ~c;
	always @(posedge osc) begin	
		if(uartDataReceived) begin
			c <= c + 4'd1;
		end
		receiveReq <= uartDataReceived;
	end
	assign gpio[4] = tx;
	assign rx = gpio[3];
	//assign gpio[4] = gpio[3];
endmodule