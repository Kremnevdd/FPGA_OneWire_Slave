module one_wire(
inout led_port,
input wire clk,
output wire [3 : 0] state_out,
output synchro_success_out, 
output wire [0 : 7]ssss,
output wire b_count,
output wire by_count,
output wire divided_clk,
output wire test_2_byte, 
output wire test_synchro,
output wire[0 : 15] mpcd,
output wire tocntr,
output wire error
);
 
// Assigns to view in signalTap

assign mpcd = ctrl_reg[0];
assign state_out = state;
assign synchro_success_out = synchro_success;

//Assign to view data reg in signalTap
assign ssss[0] = input_byte[0];
assign ssss[1] = input_byte[1];
assign ssss[2] = input_byte[2];
assign ssss[3] = input_byte[3];
assign ssss[4] = input_byte[4];
assign ssss[5] = input_byte[5];
assign ssss[6] = input_byte[6];
assign ssss[7] = input_byte[7];

// Description of bidir port
reg[0 : 0] oe;
assign led_port = (oe)?inout_reg : 1'bz;
reg [0 : 0] ctrl_reg;
reg [0 : 0] inout_reg;

// Some counters
reg [0 : 13] presence_first_counter = 14'b0;
reg [0 : 7] write_bit_timeslot_counter = 8'd0;
reg [0 : 15] timeout_counter = 16'd0;
reg [0 : 2] bit_counter = 3'd0;
reg [0 : 3] byte_counter = 4'd0;

// Description of clock divider

reg [0 : 4] counter_divider = 8'd0;
reg [0 : 0] reg_divided_clk = 0;

//Some registers
reg [0 : 0] err_reg = 1'd0;
reg [0 : 15] out_reg;
reg [0 : 7] input_byte;

// States of state machine
localparam PRE_IDLE_STATE        = 4'd0;
localparam IDLE_STATE            = 4'd1;
localparam MASTER_PULSE 		 = 4'd2;
localparam MASTER_PULSE_WAIT     = 4'd3;
localparam MASTER_DROP 			 = 4'd4;
localparam SLAVE_PRESENCE_PULSE  = 4'd5;
localparam WAITING_FOR_VCC 		 = 4'd6;
localparam WAITING_FOR_THE_BIT   = 4'd7;
localparam FIRST_HALF_TS	     = 4'd8;
localparam SECOND_HALF_TS	     = 4'd9;
localparam END_BYTE			     = 4'd10;
localparam ERR                   = 4'd11;
// Number of bytes 
localparam NUMBER_OF_BYTES       = 4'd10;  

// Timings in clock_periods
localparam MASTER_PRESENCE_PULSE_TIMING = 14'd13800;	// 554 us 
localparam PRESENCE_FREE_LINE_TIMING    = 14'd1125;		// 45 us
localparam SLAVE_PRESENCE_PULSE_TIMING  = 14'd6000;		// 240 us
localparam TIMEOUT                      = 16'd30000;
localparam LINE_SETUP_TIMING			= 14'd15;		// 15 clocks
localparam HALF_TIMESLOT_TIMING         = 14'd600;		// Timeout timing in clocks


//Flags
reg[0 : 3] flag;
reg [0 : 15] control_register;
localparam READ_OR_WRITE = 0;
parameter FIRST_BIT_OF_QUANTITY = 1;	
	/*
	| RW | Q0 | Q1 | Q2 | Q3 | Q4 | Q5| Q6 |	| A0 | A1 | A2 | A3 | A4 | A5 | A6 | A7 |
					Quantity										Start address
	*/





// Clock divider for debug
always @(posedge clk)begin
	ctrl_reg <= led_port;
	counter_divider <= counter_divider + 8'd1;
	if((reg_divided_clk) && (counter_divider == 8'd10/*250*/)) begin
			counter_divider <= 8'd0;
			reg_divided_clk <=0;
		end
	if((!reg_divided_clk) && (counter_divider == 8'd10/*250*/)) begin
			counter_divider <= 8'd0;
			reg_divided_clk <=1;
		end	
	end
assign divided_clk = reg_divided_clk;
// End of clock divider




assign mcpd = control_register;
reg [0 : 6] quantity_of_bytes;

assign b_count = bit_counter[0];
assign error = err_reg[0];
// test pins 
reg [0 : 0] test_start_synchro_pulse;


initial begin
reg [0 : 3] state = PRE_IDLE_STATE ; // Initial state of FSM
reg [0 : 0] synchro_success = 1'd0;
oe <= 1'd0;
flag <= 4'd0;
control_register <= 16'd0;
quantity_of_bytes <= 7'd0;
end
/*
FSM synchro_pulse
*/
always @(posedge clk)begin
	case(state)
	PRE_IDLE_STATE:begin  //0 //Предварительное состояние - проверка подтяжки к VCC
		oe <= 1'd0;
		if(ctrl_reg)begin
			presence_first_counter <= presence_first_counter + 14'd1;
			if(presence_first_counter == 14'd100)begin
				presence_first_counter <= 14'd0;
				state <= IDLE_STATE;
					end
			end
		else state <= PRE_IDLE_STATE;	
		end
		
	IDLE_STATE:begin  //1	// Если линия подтянута к VCC - автомат находится здесь
		oe <= 1'd0;
		presence_first_counter <= 14'd0;
		if(!ctrl_reg & !synchro_success)
			state <= MASTER_PULSE;
			end
			
	MASTER_PULSE:begin  //2		// Пришел срез управляющего сигнала - начинаем считать, ччтобы убедиться точно ли это синхроимпульс
		oe <= 1'd0;
		presence_first_counter <= presence_first_counter + 14'd1;
		if(presence_first_counter == MASTER_PRESENCE_PULSE_TIMING)begin
			state <= MASTER_PULSE_WAIT;
			presence_first_counter <= 14'd0;
			end	
		else begin
			if(ctrl_reg)begin 	// Если словили фронт раньше времени - например передачу бита
				state <= IDLE_STATE;
				presence_first_counter <= 14'd0;
				end 	
			end
		end
		
	MASTER_PULSE_WAIT:begin // 3 // Дожидаемся окончания мастер -импульса
		oe <= 1'd0;
		presence_first_counter <= presence_first_counter + 14'd1;
		if(ctrl_reg)begin
			presence_first_counter <= 14'd0;
			state <= MASTER_DROP;
			end
		else begin
			if(presence_first_counter == TIMEOUT)begin	// Линия не поднялась - валимся в ERR
				state <= ERR;
				presence_first_counter <= 14'd0;
				end
			end
		end
		
	MASTER_DROP:begin  //4		// Ждем пока линия поболтается в 1 на время паузы 
		oe <= 1'd0;
		presence_first_counter <= presence_first_counter + 14'd1;
		if(presence_first_counter == PRESENCE_FREE_LINE_TIMING) begin 
			state <= SLAVE_PRESENCE_PULSE;
			presence_first_counter <= 14'd0;
			end
		if((presence_first_counter != PRESENCE_FREE_LINE_TIMING) && !led_port )begin 
			state <= ERR;
			presence_first_counter <= 14'd0;
			end
		end
		
	SLAVE_PRESENCE_PULSE:begin 	 //5	//прижимаем линию в ответ 
		oe <= 1'd1;
		inout_reg <= 1'd0;
		presence_first_counter <= presence_first_counter + 14'd1;
		if(presence_first_counter == SLAVE_PRESENCE_PULSE_TIMING) begin 
			state <= WAITING_FOR_VCC; 
			presence_first_counter <= 14'd0;
			oe <= 1'd0;
			end
		end 
		
	WAITING_FOR_VCC:begin 		//6		Ждём пока линия точно поднимется
		presence_first_counter <= presence_first_counter + 14'd1;
		oe <= 1'd0;
		if(ctrl_reg)begin
			state <= WAITING_FOR_THE_BIT;
			presence_first_counter <= 14'd0;
			end
		if(!ctrl_reg)begin	
			if(presence_first_counter == TIMEOUT)begin
				state <= ERR;
				presence_first_counter <= 14'd0;
				end	
			else begin
				state <= WAITING_FOR_VCC;
				end
			end	
		end	
		
	WAITING_FOR_THE_BIT:begin	
		oe <= 1'd0;	//7
		//presence_first_counter <= presence_first_counter + 14'd1;
		if(!ctrl_reg)begin
				presence_first_counter <= 14'd0;
				state <= FIRST_HALF_TS;
				end
		/*if(presence_first_counter == 14'd1000)begin	// На случай если надо тут завершиться
			state <= PRE_IDLE_STATE;
			presence_first_counter <= 14'd0;
			synchro_success <= 1'd0;
			end */
		end
		
		
	FIRST_HALF_TS:begin			//8
		presence_first_counter <= presence_first_counter + 14'd1;
		if(presence_first_counter != 14'd800)begin
			state <= FIRST_HALF_TS;
			end
		if(presence_first_counter == 14'd800)begin
			presence_first_counter <= 14'd0;
			input_byte[7 - bit_counter] <= led_port;
			if(ctrl_reg)begin
				bit_counter <= bit_counter + 3'd1;
				if(bit_counter == 3'd7)begin
					state <= END_BYTE;
					end
				else begin
					state <= WAITING_FOR_VCC; 
					end
				end
			else begin
				state <= SECOND_HALF_TS;
				end
			end	
		end	
		
	SECOND_HALF_TS:begin		//9
		presence_first_counter <= presence_first_counter + 14'd1;
		if(ctrl_reg)begin    //
			bit_counter <= bit_counter + 3'd1;
			presence_first_counter <= 14'd0;
			if(bit_counter == 3'd7)begin
				state <= END_BYTE;
				byte_counter <= byte_counter + 4'd1;
				end
			else begin
				
				state <= WAITING_FOR_VCC; 
				end
			end
		if(presence_first_counter == 14'd1000)begin
			presence_first_counter <= 14'd0;
			state <= ERR;		
			end
		end
			
	END_BYTE:begin
	//	bit_counter <= 3'd0;
		presence_first_counter <= presence_first_counter + 14'd1;
		//Нововведенья
		if(presence_first_counter == 14'd100)begin
			if(flag == 4'd0)begin
				flag <= 4'd1;
				control_register[READ_OR_WRITE] <= input_byte[READ_OR_WRITE];
				control_register[1 : 7] <= input_byte[1 : 7];
				end
			if(flag == 4'd1)begin
				flag <= 4'd2;
				control_register[8 : 15] <= input_byte[0 : 7];
				end
			
		// Конец нововведенья		
			byte_counter <= byte_counter + 4'd1;
			bit_counter <= 3'd0;
			if(byte_counter == (NUMBER_OF_BYTES) )begin
				byte_counter <= 4'd0;
				state <= PRE_IDLE_STATE;
				synchro_success <= 1'd0;
				presence_first_counter <= 14'd0;
				end
			else state <= WAITING_FOR_VCC;  
				presence_first_counter <= 14'd0;
			end
			
		end	
	ERR:begin         //9
		err_reg <= 1'd1;
		state <=  PRE_IDLE_STATE;
		end	
	default:begin
		state <= PRE_IDLE_STATE;
		end
		endcase
		
end



endmodule