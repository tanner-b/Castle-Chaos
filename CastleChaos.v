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
	
	// wires for passing in the coordinates and colour of the pixel to be drawn
	wire [2:0] colour;
	wire [7:0] x;
	wire [6:0] y;

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
			
endmodule
	 
	 
	 

// each checkerboard grid consists of 2 regions:
//	- the inner box which can either contain a blue or yellow figure (fg)
//		- if there is no figure on that grid, this colour will either be black or white, depending on its location
// 	- the outer rim which surrounds the figure. This part can only be black or white, depenging on the grid'd location (bg)

//	+---------------+
//	|	bg			|		bg options: black, white
//	|	+-------+	|
//	|	|	fg	|	|		fg options: black, white, blue, yellow
//	|	+-------+	|
//	|				|
//	+---------------+

module Draw_Grid_FSM(clk, done, draw, reset, start_x, start_y, bg_colour, fg_colour, x_pos, y_pos, colour_out);
// this module can draw a box of any size based on input. Largest box we may need is 25x25,
// so the pixel counter size never needs more than 6 bits

	input clk;
	input draw;
	input reset;

	input [7:0] start_x;
	input [6:0] start_y;
	input [2:0] bg_colour;
	input [2:0] fg_colour;

	// this is passed into the module which draws the pixel on the screen
	output reg [7:0] x_pos;
	output reg [6:0] y_pos;
	output reg [2:0] colour_out;

	// this signals when the module finished drawing the current grid to the screen
	output reg done = 1'b0;

	// registers we will use for internal computations:
	reg [4:0] x_incr;
	reg [4:0] y_incr;
	
	reg curr_state = WAIT;
	reg next_state = WAIT;
	reg wait_one_cycle;
	parameter WAIT = 2'b00, INCREMENT = 2'b01, DONE = 2'b11;

	// this determines the next state
	always@(*) begin
		case(curr_state)
			WAIT: next_state = draw ? INCREMENT : WAIT;
			// if both x and y counter reached 0, we are done drawing the grid
			INCREMENT: next_state = ((x_incr == 5'b00000) && (y_incr == 5'b00000)) ? DONE : INCREMENT;
			DONE: next_state = WAIT;
		endcase
	end

	// what to do at each state
	always@(posedge clk) begin: state_table
		case (curr_state) 
		
			WAIT: begin 
				done <= 1'b0;
				// each counter starts at 25: each grid is 25x25 pixels
				x_incr <= 5'b11001;
				y_incr <= 5'b11001;
			end

			INCREMENT: begin
				done <= 1'b0;
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 

				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else begin
					// go through first row of x, then second row, ... etc
					if (x_incr == 5'b00000) begin
						x_incr <= 5'b11001;
						y_incr <= y_incr - 5'b0001;
					end else x_incr <= x_incr - 5'b0001;
				end

				// logic for colour_out: if 5<= x,y <= 19 => drawing fg, else drawing bg
				if ((x_incr >= 5'b00101) && (x_incr <= 5'b10011) && (y_incr >= 5'b00101) && (y_incr <= 5'b10011))
					colour_out <= fg_colour;
				else colour_out <= bg_colour;
			end

			DONE: done <= 1'b1;

		endcase
	end

	always @(posedge clk) begin	
		curr_state = next_state;
   end

endmodule




// selector will draw inside of a given grid. The thickness of the boarder will be one pixel wide

module Selector_Drawer_FSM(clk, reset, draw, start_x, start_y, colour_in, done, x_pos, y_pos, colour_out);

	input clk;
	input reset;
	input draw;
	input [7:0] start_x;
	input [6:0] start_y;
	input [2:0] colour_in;

	// this is passed into the module which draws the pixel on the screen
	output reg [7:0] x_pos;
	output reg [6:0] y_pos;
	output [2:0] colour_out;
	assign colour_out = colour_in;


	// this signals when the module finished drawing the current grid to the screen
	output reg done = 1'b0;
	
	// We need the same registers as in Draw_Grid_FSM for internal computations
	reg [4:0] x_incr;
	reg [4:0] y_incr;
	
	reg curr_state = WAIT;
	reg next_state = WAIT;
	reg wait_one_cycle;
	parameter WAIT = 3'b000, BOTTOM_BOARDER = 3'b001, LEFT_BOARDER = 3'b011, TOP_BOARDER = 3'b111, RIGHT_BOARDER = 3'b110, DONE = 3'b100;

	// this determines the next state
	always@(*) begin
		case(curr_state)
			WAIT: next_state = draw ? TOP_BOARDER : WAIT;
			// X counter reached 0, Y stayed at 25
			BOTTOM_BOARDER: next_state = ((x_incr == 5'b00000) && (y_incr == 5'b11001)) ? RIGHT_BOARDER : TOP_BOARDER;
			// Y counter reached 0, X stayed at 0
			LEFT_BOARDER: next_state = ((x_incr == 5'b00000) && (y_incr == 5'b00000)) ? BOTTOM_BOARDER : RIGHT_BOARDER;
			// X counter went back up to 25, Y stayed at 0
			TOP_BOARDER: next_state = ((x_incr == 5'b11001) && (y_incr == 5'b00000)) ? LEFT_BOARDER : BOTTOM_BOARDER;
			// Y counter went back up to 25, X stayed at 25
			RIGHT_BOARDER: next_state = ((x_incr == 5'b11001) && (y_incr == 5'b11001)) ? DONE : LEFT_BOARDER;
			DONE: next_state = WAIT;
		endcase
	end
	
	
	always @(posedge clk) begin	
		curr_state = next_state;
   end


   // what to do at each state
	always@(posedge clk) begin: state_table
		case (curr_state) 
		
			WAIT: begin 
				done <= 1'b0;
				// each counter starts at 25: boarder is drawn on the interior pixel of a single grid
				x_incr <= 5'b11001;
				y_incr <= 5'b11001;
			end

			BOTTOM_BOARDER: begin
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 
				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else x_incr <= x_incr - 5'b0001;
			end

			LEFT_BOARDER: begin
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 
				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else y_incr <= y_incr - 5'b0001;
			end

			TOP_BOARDER: begin
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 
				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else x_incr <= x_incr + 5'b0001;
			end

			RIGHT_BOARDER: begin
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 
				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else y_incr <= y_incr + 5'b0001;
			end

			DONE: next_state = WAIT;
		endcase
		
	end
		
endmodule


	// locations of white grid boards (x,y):
	//		([56:80], [11:35]);		([106:130], [11:35]);		([31:55], [36:60]);		([81:105], [36:60]);
	//		([56:80], [61:85]);		([106:130], [61:85]);		([31:55], [86:110]);	([81:105], [86:110]);
