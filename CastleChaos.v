module CastleChaos
	(
		CLOCK_50,						//	On Board 50 MHz
		// This part is taken from our Lab6 to be able to produce a black screen display
        KEY,
        SW,
		// The ports below are for the VGA output
		VGA_CLK,   						//	VGA Clock
		VGA_HS,							//	VGA H_SYNC
		VGA_VS,							//	VGA V_SYNC
		VGA_BLANK_N,						//	VGA BLANK
		VGA_SYNC_N,						//	VGA SYNC
		VGA_R,   						//	VGA Red[9:0]
		VGA_G,	 						//	VGA Green[9:0]
		VGA_B   						//	VGA Blue[9:0]
	);

	input			CLOCK_50;				//	50 MHz
	input   [17:0]   SW;
	input   [3:0]   KEY;

	// Declare your inputs and outputs here
	// Do not change the following outputs
	output			VGA_CLK;   				//	VGA Clock
	output			VGA_HS;					//	VGA H_SYNC
	output			VGA_VS;					//	VGA V_SYNC
	output			VGA_BLANK_N;				//	VGA BLANK
	output			VGA_SYNC_N;				//	VGA SYNC
	output	[9:0]	VGA_R;   				//	VGA Red[9:0]
	output	[9:0]	VGA_G;	 				//	VGA Green[9:0]
	output	[9:0]	VGA_B;   				//	VGA Blue[9:0]
	
	wire resetn;
	assign resetn = SW[17];
	
	
											//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~??
	
	// Create the colour, x, y and writeEn wires that are inputs to the controller.
	wire [2:0] colour;
	wire [7:0] x;
	wire [6:0] y;
	wire writeEn;
	
	wire load_x;
	wire load_y;
	
	// Wire to draw a single white box on the board. We will need 8 of these blocks
	// each white block is 25x25 pixels, so we need 6 bits.
	wire [5:0] pixel_offsets;
	

	// Create an Instance of a VGA controller - there can be only one!
	// Define the number of colours as well as the initial background
	// image file (.MIF) for the controller.
	vga_adapter VGA(
			.resetn(resetn),
			.clock(CLOCK_50),
			.colour(colour),
			.x(x),
			.y(y),
			.plot(writeEn),
			/* Signals for the DAC to drive the monitor. */
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK(VGA_BLANK_N),
			.VGA_SYNC(VGA_SYNC_N),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = "160x120";
		defparam VGA.MONOCHROME = "FALSE";
		defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
		defparam VGA.BACKGROUND_IMAGE = "black.mif";
			
	// Put your code here. Your code should produce signals x,y,colour and writeEn/plot
	// for the VGA controller, in addition to any other functionality your design may require.
    
	 
	 
	 
	 
	 
	 
	 											//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~??
		
    // Instansiate datapath
	data_path d0(.x_pos(x), .y_pos(y), .colour_out(colour), .clk(CLOCK_50), .colour_in(SW[9:7]), 
					 .load_val(SW[6:0]), .load_x(load_x), .load_y(load_y), .pixel_counter(pixel_offsets), .reset_n(resetn));

    // Instansiate FSM control
    FSM controller(.go(KEY[3]), .ResetN(resetn), .LoadX(load_x), .LoadY(load_y), .increment(pixel_offsets), .draw(writeEn), .clk(CLOCK_50));
    
	 
	 
	 
	 
	 
	 //instantiate blank checker board
	 DrawBoard board();
	 DrawBox box();
	 DrawBlue();
	 DrawYellowx();
	 
endmodule


module DrawBox();
// this module can draw a box of any size based on input. Largest box we may need is 25x25,
// so the pixel counter size never needs more than 6 bits
	
	input [2:0] colour_in;
	input [5:0] pixel_counter;
	input clk;
	input reset_n;
	input [7:0] start_x;
	input [6:0] start_y;
	
	output reg [7:0] x_pos;
	output reg [6:0] y_pos;
	output [2:0] colour_out;
	
	assign colour_out = colour_in;
	
	reg [7:0] reg_x; 
	reg [6:0] reg_y;
	
	always@(posedge clk) begin
		if (!reset_n) begin
			x_pos <= 8'b00000000;
			y_pos <= 7'b0000000;
			x_pos <= start_x + {5'b00000, pixel_counter[2:0]}; // We use pixel_counter[2:0] as x offset
			y_pos <= start_y + {4'b0000, pixel_counter[5:3]}; // We use pixel_counter[5:3] as y offset
		end
	
endmodule


module DrawBoard();	

	// locations of white grid boards (x,y):
	//		([56:80], [11:35]);		([106:130], [11:35]);		([31:55], [36:60]);		([81:105], [36:60]);
	//		([56:80], [61:85]);		([106:130], [61:85]);		([31:55], [86:110]);		([81:105], [86:110]);

endmodule







module data_path(x_pos, y_pos, colour_out, clk, colour_in, load_val, load_x, load_y, pixel_counter, reset_n);

	input [2:0] colour_in;
	input [6:0] load_val;
	input load_x; 				// From FSM
	input load_y;				// From FSM
	input [5:0] pixel_counter;	// From FSM - Bits 0 and 1 are x offset, bits 2 and 3 are y offset
	input reset_n;
	input clk;
	
	output reg [7:0] x_pos;
	output reg [6:0] y_pos;
	output [2:0] colour_out;
	
	assign colour_out = colour_in;
	
	reg [7:0] reg_x; 
	reg [6:0] reg_y;
	
	always@(posedge clk) begin
		if (!reset_n) begin
			reg_x <= 8'b00000000;
			reg_y <= 7'b0000000;
			x_pos <= 8'b00000000;
			y_pos <= 7'b0000000;
		end
		
		if (load_x) // We want to load the x register
			reg_x <= {1'b0, load_val}; // MSB is 0, we will only be able to access 128 of the 160 cols
		
		if (load_y) // We want to load the y register
			reg_y <= load_val; // MSB is 0, the display is limited to 120 rows apparently
		
		if (!load_x & !load_y) begin // We want to output some pixel offset to the pixel registers
			x_pos <= reg_x + {6'b000000, pixel_counter[1:0]}; // We use pixel_counter[1:0] as x offset
			y_pos <= reg_y + {5'b00000, pixel_counter[3:2]}; // We use pixel_counter[3:2] as y offset
		end
	end

endmodule

module FSM(go, ResetN, LoadX, LoadY, increment, draw, clk);
	input go;
	input ResetN;
	input clk;
	
	output reg LoadX;
	output reg LoadY;
	output reg [5:0] increment;
	output reg draw;
	
	reg [2:0] curr_state = WAIT_LOAD_X;
	reg [2:0] next_state = WAIT_LOAD_X;
	
	parameter WAIT_LOAD_X = 3'b000, LOAD_X = 3'b001, WAIT_LOAD_Y = 3'b010, LOAD_Y = 3'b011, INCREMENT = 3'b100;
	reg wait_one_cycle = 1'b0;
	
	always@(*) begin
		case (curr_state)
			WAIT_LOAD_X: next_state = go ? LOAD_X : WAIT_LOAD_X; 
			LOAD_X: next_state = go ? LOAD_X : WAIT_LOAD_Y; 
			WAIT_LOAD_Y: next_state = go ? LOAD_Y : WAIT_LOAD_Y;
			LOAD_Y: next_state = go ? LOAD_Y : INCREMENT;
			INCREMENT: next_state = increment == 4'b1111 ? WAIT_LOAD_X : INCREMENT;
		endcase
		
		if(ResetN == 1'b0)
			next_state = WAIT_LOAD_X; // Should restart at getting X
	end
	
	always@(posedge clk)
	begin: state_table
		case (curr_state)	
		
			INCREMENT: begin
				LoadX <= 0;
				LoadY <= 0;
				if (wait_one_cycle == 1'b1)
				begin
					wait_one_cycle = 1'b0;
					draw <= 0;
					end
				else
					begin
					increment <= increment + 4'b0001;
					draw <= 1;
					end
					
			end
			
			LOAD_Y: begin
				LoadX <= 0;
				LoadY <= 1;
				draw <= 0;
				increment <= 4'b0000;
				wait_one_cycle = 1'b1;
			end
			
			WAIT_LOAD_Y: begin
				LoadX <= 0;
				LoadY <= 0;
				draw <= 0;
			end	

			LOAD_X: begin
				LoadX <= 1;
				LoadY <= 0;
				draw <= 0;
			end

			WAIT_LOAD_X: begin
				LoadX <= 0;
				LoadY <= 0;
				draw <= 0;
			end			
				
		endcase
	end
	
	always @(posedge clk) begin
		
		curr_state = next_state;
   end	
endmodule