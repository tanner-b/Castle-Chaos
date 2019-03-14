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
	//		([56:80], [11:35]); 	([106:130], [11:35]);		([31:55], [36:60]);		([81:105], [36:60]);
	//		([56:80], [61:85]);		([106:130], [61:85]);		([31:55], [86:110]);	([81:105], [86:110]);

module game_controller_fsm (load_p, load_s, x_out, y_out, colour1_out, colour2_out, done_p, done_s, selector, direction, clk, reset);

	input [3:0] selector; // Changes the cell the selector is on
	input [3:0] direction; // Tries to move the selected peice up, down, left, right
	input done_p, done_s; // Signals for when the other fsm's are done thier drawing.
	input clk, reset; // Clk is clock, and reset resets.
	
	output reg load_p, load_s; // The signals given to the piece_drawer_fsm and selector_drawer_fsm
	output reg [7:0] x_out; // X and Y are the top left corner of what ever we want to draw
	output reg [6:0] y_out;
	output [2:0] colour1_out, colour2_out; // Two colour outputs used by the drawers.
	
	reg [2:0] curr_state = RESET;
	reg [2:0] next_state = DRAW_BOARD;
	reg player_turn = 0;
	reg player_input = 2'b00;
	
	// Registers for holding the board information
	// Each cell is 3 bits, and thus a 4x4 board.
	// bit[2] -> 0 : black, 1 : white;
	// bits[1:0] -> 00 : black, 10 : white, 01 : blue, 11 : yellow;
	reg [47:0] cells; 
	
	assign player_has_input = direction[0] | direction[1] | direction[2] | direction[3];
	
	parameter RESET = 3'b000, DRAW_BOARD_0 = 3'b001, WAIT_BOARD_0 = 3'b010, DRAW_SELECTOR = 3'b011, 
			  WAIT_SELECTOR_DONE = 3'b100, WAIT_PLAYER = 3'b101, DO_LOGIC = 3'b110;
	
	// State changing logic		  
	always@(*) begin
		case (curr_state)
			RESET: next_state = reset ? RESET : DRAW_BOARD; 
			DRAW_BOARD_0: next_state = WAIT_BOARD_0;
			WAIT_BOARD_0: next_state = done_p ? DRAW_BOARD_1 : WAIT_BOARD_0;
			DRAW_BOARD_1: next_state = WAIT_BOARD_1;
			WAIT_BOARD_1: next_state = done_p ? DRAW_BOARD_2 : WAIT_BOARD_1;
			DRAW_BOARD_2: next_state = WAIT_BOARD_2;
			WAIT_BOARD_2: next_state = done_p ? DRAW_BOARD_3 : WAIT_BOARD_2;
			DRAW_BOARD_3: next_state = WAIT_BOARD_3;
			WAIT_BOARD_3: next_state = done_p ? DRAW_BOARD_4 : WAIT_BOARD_3;
			DRAW_BOARD_4: next_state = WAIT_BOARD_4;
			WAIT_BOARD_4: next_state = done_p ? DRAW_BOARD_5 : WAIT_BOARD_4;
			DRAW_BOARD_5: next_state = WAIT_BOARD_5;
			WAIT_BOARD_5: next_state = done_p ? DRAW_BOARD_6 : WAIT_BOARD_5;
			DRAW_BOARD_6: next_state = WAIT_BOARD_6;
			WAIT_BOARD_6: next_state = done_p ? DRAW_BOARD_7 : WAIT_BOARD_6;
			DRAW_BOARD_7: next_state = WAIT_BOARD_7;
			WAIT_BOARD_7: next_state = done_p ? DRAW_BOARD_8 : WAIT_BOARD_7;
			DRAW_BOARD_8: next_state = WAIT_BOARD_8;
			WAIT_BOARD_8: next_state = done_p ? DRAW_BOARD_9 : WAIT_BOARD_8;
			DRAW_BOARD_9: next_state = WAIT_BOARD_9;
			WAIT_BOARD_9: next_state = done_p ? DRAW_BOARD_10 : WAIT_BOARD_9;
			DRAW_BOARD_10: next_state = WAIT_BOARD_10;
			WAIT_BOARD_10: next_state = done_p ? DRAW_BOARD_11 : WAIT_BOARD_10;
			DRAW_BOARD_11: next_state = WAIT_BOARD_11;
			WAIT_BOARD_11: next_state = done_p ? DRAW_BOARD_12 : WAIT_BOARD_11;
			DRAW_BOARD_12: next_state = WAIT_BOARD_12;
			WAIT_BOARD_12: next_state = done_p ? DRAW_BOARD_13 : WAIT_BOARD_12;
			DRAW_BOARD_13: next_state = WAIT_BOARD_13;
			WAIT_BOARD_13: next_state = done_p ? DRAW_BOARD_14 : WAIT_BOARD_13;
			DRAW_BOARD_14: next_state = WAIT_BOARD_14;
			WAIT_BOARD_14: next_state = done_p ? DRAW_BOARD_15 : WAIT_BOARD_14;
			DRAW_BOARD_15: next_state = WAIT_BOARD_15;
			WAIT_BOARD_15: next_state = done_p ? WAIT_PLAYER : WAIT_BOARD_15;
			
			DRAW_SELECTOR: next_state = WAIT_SELECTOR_DONE;
			WAIT_SELECTOR_DONE: next_state = done_s ? WAIT_PLAYER : WAIT_SELECTOR_DONE;
			WAIT_PLAYER: next_state = player_has_input ? DO_LOGIC : WAIT_PLAYER;
			DO_LOGIC: next_state = DRAW_BOARD;
		endcase
	end
	
	always@(posedge clk)
	begin: state_table
		case (curr_state)	
		
			RESET: 
			begin
				cells = {3'b001, 3'b111, 3'b000, 3'b110,
                         3'b101, 3'b000, 3'b111, 3'b010,
                         3'b001, 3'b111, 3'b000, 3'b110,
                         3'b101, 3'b000, 3'b111, 3'b010};
				load_p <= 1'b0;
				load_s <= 1'b0;
				x_out <= 8'b00000000;
				y_out <= 7'b0000000;
			end
						
			DRAW_BOARD_0: begin
				bg_colour_decoder(cells[2:0], colour1_out);
				fg_colour_decoder(cells[2:0], colour2_out);
				load_p <= 1'b1;
				x_out <= 8'b00001010;
				y_out <= 7'b0011110;
			end
			WAIT_BOARD_0: begin 
				load_p = 1'b0;
			end
			DRAW_BOARD_1: begin
				bg_colour_decoder(cells[5:3], colour1_out);
				fg_colour_decoder(cells[5:3], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b00110111;
				y_out <= 7'b0001011;
			end
			WAIT_BOARD_1: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_2: begin 
				bg_colour_decoder(cells[8:6], colour1_out);
				fg_colour_decoder(cells[8:6], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b01010000;
				y_out <= 7'b0001011;
			end
			WAIT_BOARD_2: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_3: begin
				bg_colour_decoder(cells[11:9], colour1_out);
				fg_colour_decoder(cells[11:9], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b01101001;
				y_out <= 7'b0001011;
			end
			WAIT_BOARD_3: begin
				load_p = 1'b0;			
			end
			DRAW_BOARD_4: begin
				bg_colour_decoder(cells[14:12], colour1_out);
				fg_colour_decoder(cells[14:12], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b00011110;
				y_out <= 7'b0100011;
			end
			WAIT_BOARD_4: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_5: begin 
				bg_colour_decoder(cells[17:15], colour1_out);
				fg_colour_decoder(cells[17:15], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b00110111;
				y_out <= 7'b0100011;
			end
			WAIT_BOARD_5: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_6: begin
				bg_colour_decoder(cells[20:18], colour1_out);
				fg_colour_decoder(cells[20:18], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b01010000;
				y_out <= 7'b0100011;
			end
			WAIT_BOARD_6: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_7: begin
				bg_colour_decoder(cells[23:21], colour1_out);
				fg_colour_decoder(cells[23:21], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b01101001;
				y_out <= 7'b0100011;
			end
			WAIT_BOARD_7: begin 
				load_p = 1'b0;
			end
			DRAW_BOARD_8: begin
				bg_colour_decoder(cells[26:24], colour1_out);
				fg_colour_decoder(cells[26:24], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b00001110;
				y_out <= 7'b0111100;
			end
			WAIT_BOARD_8: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_9: begin
				bg_colour_decoder(cells[29:27], colour1_out);
				fg_colour_decoder(cells[29:27], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b00110111;
				y_out <= 7'b0111100;
			end
			WAIT_BOARD_9: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_10: begin
				bg_colour_decoder(cells[32:30], colour1_out);
				fg_colour_decoder(cells[32:30], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b01010000;
				y_out <= 7'b0111100;
			end
			WAIT_BOARD_10: begin 
				load_p = 1'b0;
			end
			DRAW_BOARD_11: begin
				bg_colour_decoder(cells[35:33], colour1_out);
				fg_colour_decoder(cells[35:33], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b01101001;
				y_out <= 7'b0111100;
			end
			WAIT_BOARD_11: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_12: begin 
				bg_colour_decoder(cells[38:36], colour1_out);
				fg_colour_decoder(cells[38:36], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b00011110;
				y_out <= 7'b1010101;
			end
			WAIT_BOARD_12: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_13: begin
				bg_colour_decoder(cells[41:39], colour1_out);
				fg_colour_decoder(cells[41:39], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b00110111;
				y_out <= 7'b1010101;
			end
			WAIT_BOARD_13: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_14: begin
				bg_colour_decoder(cells[44:42], colour1_out);
				fg_colour_decoder(cells[44:42], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b01010000;
				y_out <= 7'b1010101;
			end
			WAIT_BOARD_14: begin
				load_p = 1'b0;
			end
			DRAW_BOARD_15: begin
				bg_colour_decoder(cells[47:45], colour1_out);
				fg_colour_decoder(cells[47:45], colour2_out);			
				load_p = 1'b1;
				x_out <= 8'b01101001;
				y_out <= 7'b1010101;
			end
			WAIT_BOARD_15: begin
				load_p = 1'b0;
			end
			
			DRAW_SELECTOR:
				
				
			WAIT_SELECTOR_DONE:
			
			WAIT_PLAYER:
			
			DO_LOGIC:

			default:
				next_state = RESET;
				
		endcase
	end
	
	always @(posedge clk) begin
		if(reset == 1'b0)
			next_state = RESET; // Should restart
		curr_state = next_state;
	end	

endmodule

module bg_colour_decoder(cell_data, colour);

	input [2:0] cell_data;
	output reg [2:0] colour;
	
	case (cell_data)
		// White
		3'b111, 3'b101, 3'b110:
			colour = 3'b111;
		// Black
		3'b000, 3'b001, 3'b010, default:
			colour = 3'b000;
	endcase
endmodule

module fg_colour_decoder(cell_data, colour);
	input [2:0] cell_data;
	output  reg [2:0] colour;
	
	case (cell_data)
		// White
		3'b111:
			colour = 3'b111;
		// Blue
		3'b001, 3'b101:
			colour = 3'b001;
		// Yellow
		3'b010, 3'b110:
			colour = 3'110;
		// Black
		3'b000, default:
			colour = 3'b000
	endcase
endmodule	