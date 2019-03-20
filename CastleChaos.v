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
		VGA_B,
		HEX0,
		HEX1,
		HEX4,
		HEX5//	VGA Blue[9:0]
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
	output [6:0] HEX0, HEX1, HEX4, HEX5;
	
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
		
		wire load_p, load_s;
		wire done_p, done_s;
		wire [2:0] grid_colour; selector_colour;
		wire [7:0] start_x; x_grid; x_selector;
		wire [6:0] start_y; y_grid; y_selector;
		wire [2:0] bg_colour, fg_colour;
		wire s; // s==0 means we are drawing a grid, s==1 means we are drawing a red selector outline
		wire writeEn;
		wire [5:0] state;
		
		// instantiate all the modules we wrote for this game
		Draw_Grid_FSM grid_drawer(.clk(CLOCK_50), .done(done_p), .load_p(load_p), .reset(~resetn), .start_x(start_x), .start_y(start_y), .bg_colour(bg_colour), .fg_colour(fg_colour), .x_pos(x_grid), .y_pos(y_grid), .colour_out(grid_colour), .draw(writeEn));
		Selector_Drawer_FSM selector_drawer(.clk(CLOCK_50), .reset(~resetn), .load_s(load_s), .start_x(start_x), .start_y(start_y), .colour_in(bg_colour), .done(done_s), .x_pos(x_selector), .y_pos(y_selector), .colour_out(selector_colour), .draw(writeEn));
		game_controller_fsm main(.load_p(load_p), .load_s(load_s), .x_out(start_x), .y_out(start_y), .colour1_out(bg_colour), .colour2_out(fg_colour), .done_p(done_p), .done_s(done_s), .selector(SW[3:0]), .direction(KEY[3:0]), .clk(CLOCK_50), .reset(~resetn), .hex_state(state), .s(s));
		// contract: grid data comes first, then selector data
		pixel_drawing_MUX mux(.s(s), .colour_in({grid_colour, selector_colour}), .x_in({x_grid, x_selector}), .y_in({y_grid, y_selector}), .colour_out(colour), .x_out(x), .y_out(y));
		hex_decoder hex0 (.hex_digit(start_x[3:0]), .segments(HEX0));
		hex_decoder hex1 (.hex_digit(start_y[3:0]), .segments(HEX1));
		hex_decoder hex4 (.hex_digit(state[3:0]), .segments(HEX4));
		hex_decoder hex5 (.hex_digit({2'b00, state[5:4]}), .segments(HEX5));
			
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

module Draw_Grid_FSM(clk, done, load_p, reset, start_x, start_y, bg_colour, fg_colour, x_pos, y_pos, colour_out, draw);
// this module can draw a box of any size based on input. Largest box we may need is 25x25,
// so the pixel counter size never needs more than 6 bits

	input clk;
	input load_p;
	input reset;

	input [7:0] start_x;
	input [6:0] start_y;
	input [2:0] bg_colour;
	input [2:0] fg_colour;

	// this is passed into the module which draws the pixel on the screen
	output reg [7:0] x_pos;
	output reg [6:0] y_pos;
	output reg [2:0] colour_out;
	output reg draw;

	// this signals when the module finished drawing the current grid to the screen
	output reg done = 1'b0;

	// registers we will use for internal computations:
	reg [4:0] x_incr;
	reg [4:0] y_incr;
	
	reg [1:0] curr_state = WAIT;	
	reg [1:0] next_state = WAIT;
	reg wait_one_cycle;
	parameter WAIT = 2'b00, INCREMENT = 2'b01, DONE = 2'b11;

	// this determines the next state
	always@(*) begin
		case(curr_state)
			WAIT: next_state = load_p ? INCREMENT : WAIT;
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
				x_pos <= start_x + {3'b000, x_incr[4:0]};
				y_pos <= start_y + {2'b00, y_incr[4:0]}; 

				if (wait_one_cycle == 1'b1) begin
					wait_one_cycle = 1'b0;
					draw <= 1'b0;
				end
				
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
					//colour_out <= 3'b100;
				else colour_out <= bg_colour;
				//colour_out <= 3'b010;
				draw <= 1'b1;
			end

			DONE: done <= 1'b1;

		endcase
	end

	always @(posedge clk) begin	
		curr_state = next_state;
   end

endmodule




// selector will draw inside of a given grid. The thickness of the boarder will be one pixel wide

module Selector_Drawer_FSM(clk, reset, load_s, start_x, start_y, colour_in, done, x_pos, y_pos, colour_out, draw);

	input clk;
	input reset;
	input load_s;
	input [7:0] start_x;
	input [6:0] start_y;
	input [2:0] colour_in;

	// this is passed into the module which draws the pixel on the screen
	output reg [7:0] x_pos;
	output reg [6:0] y_pos;
	output [2:0] colour_out;
	assign colour_out = colour_in;
	output reg draw;


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
			WAIT: next_state = load_s ? TOP_BOARDER : WAIT;
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
				draw <= 1'b0;
			end

			BOTTOM_BOARDER: begin
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 
				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else x_incr <= x_incr - 5'b0001;
				draw <= 1'b1;
			end

			LEFT_BOARDER: begin
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 
				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else y_incr <= y_incr - 5'b0001;
				draw <= 1'b1;
			end

			TOP_BOARDER: begin
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 
				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else x_incr <= x_incr + 5'b0001;
				draw <= 1'b1;
			end

			RIGHT_BOARDER: begin
				x_pos <= start_x + {5'b00000, x_incr[4:0]};
				y_pos <= start_y + {4'b0000, y_incr[4:0]}; 
				if (wait_one_cycle == 1'b1) wait_one_cycle = 1'b0;
				else y_incr <= y_incr + 5'b0001;
				draw <= 1'b1;
			end

			DONE: next_state = WAIT;
		endcase
		
	end
		
endmodule


	// locations of white grid boards (x,y):
	//		([56:80], [11:35]); 	([106:130], [11:35]);		([31:55], [36:60]);		([81:105], [36:60]);
	//		([56:80], [61:85]);		([106:130], [61:85]);		([31:55], [86:110]);	([81:105], [86:110]);

module game_controller_fsm (load_p, load_s, x_out, y_out, colour1_out, colour2_out, done_p, done_s, selector, direction, clk, reset, hex_state, s);

	input [3:0] selector; // Changes the cell the selector is on
	input [3:0] direction; // Tries to move the selected peice up, down, left, right
	input done_p, done_s; // Signals for when the other fsm's are done thier drawing.
	input clk, reset; // Clk is clock, and reset resets.
	
	output reg load_p, load_s; // The signals given to the piece_drawer_fsm and selector_drawer_fsm
	output reg [7:0] x_out; // X and Y are the top left corner of what ever we want to draw
	output reg [6:0] y_out;
	output [2:0] colour1_out, colour2_out; // Two colour outputs used by the drawers.
	output reg [5:0] hex_state;
	output reg s; // s==0 means we draw a grid, s==1 means we draw the red selector outline
	
	reg [2:0] fg_colour, bg_colour;
	//reg player_turn = 0;
	
	fg_colour_decoder myfg (.cell_data(fg_colour), .colour(colour2_out));
	bg_colour_decoder mybg (.cell_data(bg_colour), .colour(colour1_out));
	
	// Registers for holding the board information
	// Each cell is 3 bits, and thus a 4x4 board.
	// bit[2] -> 0 : black, 1 : white;
	// bits[1:0] -> 00 : black, 10 : white, 01 : blue, 11 : yellow;
	reg [47:0] cells; 
	
	assign player_has_input = direction[0] || direction[1] || direction[2] || direction[3];
	
	reg player_input = 2'b00;
	
	parameter UP = 2'b00, DOWN = 2'b01, LEFT = 2'b10, RIGHT = 2'b11;
	
	parameter RESET = 6'b000000, 
	DRAW_BOARD_0 = 6'b000001, WAIT_BOARD_0 = 6'b000010,
	DRAW_BOARD_1 = 6'b000011, WAIT_BOARD_1 = 6'b000100,	
	DRAW_BOARD_2 = 6'b000101, WAIT_BOARD_2 = 6'b000110,
	DRAW_BOARD_3 = 6'b000111, WAIT_BOARD_3 = 6'b001000,	
	DRAW_BOARD_4 = 6'b001001, WAIT_BOARD_4 = 6'b001010,
	DRAW_BOARD_5 = 6'b001011, WAIT_BOARD_5 = 6'b001100,	
	DRAW_BOARD_6 = 6'b001101, WAIT_BOARD_6 = 6'b001110,
	DRAW_BOARD_7 = 6'b001111, WAIT_BOARD_7 = 6'b010000,	
	DRAW_BOARD_8 = 6'b010001, WAIT_BOARD_8 = 6'b010010,
	DRAW_BOARD_9 = 6'b010011, WAIT_BOARD_9 = 6'b010100,	
	DRAW_BOARD_10 = 6'b010101, WAIT_BOARD_10 = 6'b010110,
	DRAW_BOARD_11 = 6'b010111, WAIT_BOARD_11 = 6'b011000,	
	DRAW_BOARD_12 = 6'b011001, WAIT_BOARD_12 = 6'b011010,
	DRAW_BOARD_13 = 6'b011011, WAIT_BOARD_13 = 6'b011100,	
	DRAW_BOARD_14 = 6'b011101, WAIT_BOARD_14 = 6'b011110,
	DRAW_BOARD_15 = 6'b011111, WAIT_BOARD_15 = 6'b100000,	
	DRAW_SELECTOR = 6'b100001, 
	WAIT_SELECTOR_DONE = 6'b100010, WAIT_PLAYER = 6'b100011, 
	WAIT_PLAYER_UP = 6'b100100, DO_LOGIC = 6'b100101;
	
	reg [5:0] curr_state = RESET;
	reg [5:0] next_state = DRAW_BOARD_0;		  
	
	// State changing logic		  
	always@(*) begin
		case (curr_state)
			RESET: next_state = reset ? RESET : DRAW_BOARD_0; 
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
			
			WAIT_PLAYER: next_state = player_has_input ? WAIT_PLAYER_UP : WAIT_PLAYER;
			
			WAIT_PLAYER_UP: next_state = player_has_input ? WAIT_PLAYER_UP : DO_LOGIC;
			
			DO_LOGIC: next_state = DRAW_BOARD_0;
		endcase
		
		if(reset == 1'b1)
			next_state = RESET;
	end
	
	always@(posedge clk)
	begin: state_table
		case (curr_state)	
		
			RESET: 
			begin
				cells <= {3'b001, 3'b111, 3'b000, 3'b110,
                         3'b101, 3'b000, 3'b111, 3'b010,
                         3'b001, 3'b111, 3'b000, 3'b110,
                         3'b101, 3'b000, 3'b111, 3'b010};
				load_p <= 1'b0;
				load_s <= 1'b0;
				x_out <= 8'b00000000;
				y_out <= 7'b0000000;
			end
						
			DRAW_BOARD_0: begin
				s <= 1'b0; 					// start drawing the grids
				bg_colour <= cells[2:0];
				fg_colour <= cells[2:0];
				load_p <= 1'b1;
				x_out <= 8'b00011110;
				y_out <= 7'b0001010;
			end
			WAIT_BOARD_0: begin 
				load_p <= 1'b0;
			end
			DRAW_BOARD_1: begin
				bg_colour <= cells[5:3];
				fg_colour <= cells[5:3];			
				load_p <= 1'b1;
				x_out <= 8'b00110111;
				y_out <= 7'b0001011;
			end
			WAIT_BOARD_1: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_2: begin 
				bg_colour <= cells[8:6];
				fg_colour <= cells[8:6];			
				load_p <= 1'b1;
				x_out <= 8'b01010000;
				y_out <= 7'b0001011;
			end
			WAIT_BOARD_2: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_3: begin
				bg_colour <= cells[11:9];
				fg_colour <= cells[11:9];			
				load_p <= 1'b1;
				x_out <= 8'b01101001;
				y_out <= 7'b0001011;
			end
			WAIT_BOARD_3: begin
				load_p <= 1'b0;			
			end
			DRAW_BOARD_4: begin
				bg_colour <= cells[14:12];
				fg_colour <= cells[14:12];			
				load_p <= 1'b1;
				x_out <= 8'b00011110;
				y_out <= 7'b0100011;
			end
			WAIT_BOARD_4: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_5: begin 
				bg_colour <= cells[17:15];
				fg_colour <= cells[17:15];			
				load_p <= 1'b1;
				x_out <= 8'b00110111;
				y_out <= 7'b0100011;
			end
			WAIT_BOARD_5: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_6: begin
				bg_colour <= cells[20:18];
				fg_colour <= cells[20:18];			
				load_p <= 1'b1;
				x_out <= 8'b01010000;
				y_out <= 7'b0100011;
			end
			WAIT_BOARD_6: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_7: begin
				bg_colour <= cells[23:21];
				fg_colour <= cells[23:21];			
				load_p <= 1'b1;
				x_out <= 8'b01101001;
				y_out <= 7'b0100011;
			end
			WAIT_BOARD_7: begin 
				load_p <= 1'b0;
			end
			DRAW_BOARD_8: begin
				bg_colour <= cells[26:24];
				fg_colour <= cells[26:24];			
				load_p <= 1'b1;
				x_out <= 8'b00011110;
				y_out <= 7'b0111100;
			end
			WAIT_BOARD_8: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_9: begin
				bg_colour <= cells[29:27];
				fg_colour <= cells[29:27];			
				load_p <= 1'b1;
				x_out <= 8'b00110111;
				y_out <= 7'b0111100;
			end
			WAIT_BOARD_9: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_10: begin
				bg_colour <= cells[32:30];
				fg_colour <= cells[32:30];			
				load_p <= 1'b1;
				x_out <= 8'b01010000;
				y_out <= 7'b0111100;
			end
			WAIT_BOARD_10: begin 
				load_p <= 1'b0;
			end
			DRAW_BOARD_11: begin
				bg_colour <= cells[35:33];
				fg_colour <= cells[35:33];			
				load_p <= 1'b1;
				x_out <= 8'b01101001;
				y_out <= 7'b0111100;
			end
			WAIT_BOARD_11: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_12: begin 
				bg_colour <= cells[38:36];
				fg_colour <= cells[38:36];			
				load_p <= 1'b1;
				x_out <= 8'b00011110;
				y_out <= 7'b1010101;
			end
			WAIT_BOARD_12: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_13: begin
				bg_colour <= cells[41:39];
				fg_colour <= cells[41:39];			
				load_p <= 1'b1;
				x_out <= 8'b00110111;
				y_out <= 7'b1010101;
			end
			WAIT_BOARD_13: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_14: begin
				bg_colour <= cells[44:42];
				fg_colour <= cells[44:42];
				load_p <= 1'b1;
				x_out <= 8'b01010000;
				y_out <= 7'b1010101;
			end
			WAIT_BOARD_14: begin
				load_p <= 1'b0;
			end
			DRAW_BOARD_15: begin
				bg_colour <= cells[47:45];
				fg_colour <= cells[47:45];
				load_p <= 1'b1;
				x_out <= 8'b01101001;
				y_out <= 7'b1010101;
			end
			WAIT_BOARD_15: begin
				load_p <= 1'b0;
			end
			
			DRAW_SELECTOR: begin
				s <= 1'b1; 					// start drawing the selector
				load_p <= 1'b0;
				load_s <= 1'b1;
				bg_colour <= 3'b100; // RED for the selector outline.
				
				// Figure out what X and Y to draw the selector at
				case (selector)
					// 0
					4'b0000: begin
						x_out <= 8'b00011110;
						y_out <= 7'b0001010;
					end
					
					// 1
					4'b0001: begin
						x_out <= 8'b00110111;
						y_out <= 7'b0001011;
					end
					
					// 2
					4'b0010: begin
						x_out <= 8'b00110111;
						y_out <= 7'b0001011;
					end
					
					// 3
					4'b0011: begin
						x_out <= 8'b01101001;
						y_out <= 7'b0001011;
					end
					
					// 4
					4'b0100: begin
						x_out <= 8'b00011110;
						y_out <= 7'b0100011;				
					end
					
					// 5
					4'b0101: begin
						x_out <= 8'b00110111;
						y_out <= 7'b0100011;
					end
					
					// 6
					4'b0110: begin
						x_out <= 8'b00110111;
						y_out <= 7'b0100011;
					end
					
					// 7
					4'b0111: begin
						x_out <= 8'b01101001;
						y_out <= 7'b0100011;
					end
					
					// 8
					4'b1000: begin
						x_out <= 8'b00011110;
						y_out <= 7'b0111100;
					end
					
					// 9
					4'b1001: begin
						x_out <= 8'b00110111;
						y_out <= 7'b0111100;
					end
					
					// 10
					4'b1010: begin
						x_out <= 8'b00110111;
						y_out <= 7'b0111100;
					end
					
					// 11
					4'b1011: begin
						x_out <= 8'b01101001;
						y_out <= 7'b0111100;
					end
					
					// 12
					4'b1100: begin
						x_out <= 8'b00011110;
						y_out <= 7'b1010101;
					end
					
					// 13
					4'b1101: begin 
						x_out <= 8'b00110111;
						y_out <= 7'b1010101;
					end
					
					// 14
					4'b1110: begin
						x_out <= 8'b00110111;
						y_out <= 7'b1010101;
					end
					
					// 15
					4'b1111: begin
						x_out <= 8'b01101001;
						y_out <= 7'b1010101;
					end
					
					default: begin
						x_out <= 8'b00011110;
						y_out <= 7'b0111100;
					end
				endcase		
			end
			
			WAIT_SELECTOR_DONE: begin
				load_p <= 1'b0;
				load_s <= 1'b0;
			end 
			
			WAIT_PLAYER: load_p <= 1'b0;
			
			WAIT_PLAYER_UP: begin
				load_p <= 1'b0;
				case (direction)
					4'b1000: player_input = UP;
					4'b1000: player_input = DOWN;
					4'b1000: player_input = LEFT;
					4'b1000: player_input = RIGHT;
					default: player_input = UP; // Up by default if more than one button happens to be down at once
				endcase
			end
				
			DO_LOGIC: load_p <= 1'b0;
			// GAME LOGIC
			

			default:
				next_state <= RESET;
				
		endcase
		
		
		
	end
	
	always @(posedge clk) begin
		 // Should restart
		curr_state <= next_state;
		hex_state <= curr_state;
	end	

endmodule

module bg_colour_decoder(cell_data, colour);

	input [2:0] cell_data;
	output reg [2:0] colour;
	
	always@(*) begin
		case (cell_data)
			// White
			3'b111, 3'b101, 3'b110:
				colour <= 3'b111;
			// Black
			3'b000, 3'b001, 3'b010:
				colour <= 3'b000;
			default:
				colour <= 3'b000;
		endcase
	end
endmodule

module fg_colour_decoder(cell_data, colour);
	input [2:0] cell_data;
	output  reg [2:0] colour;
	
	always@(*) begin
		case (cell_data)
			// White
			3'b111:
				colour <= 3'b111;
			// Blue
			3'b001, 3'b101:
				colour <= 3'b001;
			// Yellow
			3'b010, 3'b110:
				colour <= 3'b110;
			// Black
			3'b000: 
				colour <= 3'b000;
			default:
				colour <= 3'b000;
		endcase
	end
endmodule	


module pixel_drawing_MUX(s, colour_in, x_in, y_in, colour_out, x_out, y_out);
	input s; // s==0 means we draw a grid, s==1 means we draw the red selector outline
	input [5:0] colour_in;	// [5:3] = grid_color, [2:0] = selector_color
	input [15:0] x_in;	// [15:8] = grid x, [7:0] = selector x
	input [13:0] y_in;	// [13:7] = grid y, [6:0] = selector y

	reg [2:0] colour_out;
	reg [7:0] x_out;
	reg [6:0] y_out;

	always @(*) begin
		case (s)
			1'b0: begin							// case: grid
				colour_out <= colour_in[5:3];
				x_out <= x_in[15:8];
				y_out <= y_in[13:7];
				end
			1'b1: begin
				colour_out <= colour_in[2:0];
				x_out <= x_in[7:0];
				y_out <= y_in[6:0];
				end
		endcase
	end
endmodule


module score_FSM();

endmodule

module hex_decoder(hex_digit, segments);
    input [3:0] hex_digit;
    output reg [6:0] segments;
   
    always @(*)
        case (hex_digit)
            4'h0: segments = 7'b100_0000;
            4'h1: segments = 7'b111_1001;
            4'h2: segments = 7'b010_0100;
            4'h3: segments = 7'b011_0000;
            4'h4: segments = 7'b001_1001;
            4'h5: segments = 7'b001_0010;
            4'h6: segments = 7'b000_0010;
            4'h7: segments = 7'b111_1000;
            4'h8: segments = 7'b000_0000;
            4'h9: segments = 7'b001_1000;
            4'hA: segments = 7'b000_1000;
            4'hB: segments = 7'b000_0011;
            4'hC: segments = 7'b100_0110;
            4'hD: segments = 7'b010_0001;
            4'hE: segments = 7'b000_0110;
            4'hF: segments = 7'b000_1110;   
            default: segments = 7'h7f;
        endcase
endmodule 