
module piece_drawer_fsm (x_out, y_out, colour_out, done, colour1, colour2, x, y, load, clk, reset);
endmodule


module selector_drawer_fsm (x_out, y_out, colour_out, done, colour1, x, y, load, clk, reset);
endmodule


module game_controller_fsm (load_p, load_s, x_out, y_out, colour1_out, colour2_out, done_p, done_s, selector, direction, clk, reset);

	input [3:0] selector; // Changes the cell the selector is on
	input [3:0] direction; // Tries to move the selected peice up, down, left, right
	input done_p, done_s; // Signals for when the other fsm's are done thier drawing.
	input clk, reset; // Clk is clock, and reset resets.
	
	output load_p, load_s; // The signals given to the piece_drawer_fsm and selector_drawer_fsm
	output [7:0] x_out; // X and Y are the top left corner of what ever we want to draw
	output [6:0] y_out;
	output [2:0] colour1_out, colour2_out; // Two colour outputs used by the drawers.
	
	reg [2:0] curr_state = RESET;
	reg [2:0] next_state = DRAW_BOARD;
	reg player_turn = 0;
	reg player_input = 2'b00;
	
	// Registers for holding the board information
	// Each cell is 3 bits, and thus a 4x4 board.
	// bit[2] -> 0 : black, 1 : white;
	// bits[1:0] -> 00 : black, 11 : white, 01 : blue, 10 : yellow;
	reg cells [47:0] = {3'b001, 3'b111, 3'b000, 3'b110,
						3'b101, 3'b000, 3'b111, 3'b010,
						3'b001, 3'b111, 3'b000, 3'b110,
						3'b101, 3'b000, 3'b111, 3'b010};
	
	assign player_has_input = in[0] | in[1] | in[2] | in[3];
	
	parameter RESET = 3'b000, DRAW_BOARD = 3'b001, WAIT_BOARD_DONE = 3'b010, DRAW_SELECTOR = 3'b011, 
			  WAIT_SELECTOR_DONE = 3'b100, WAIT_PLAYER = 3'b101, DO_LOGIC = 3'b110;
			  
	always@(*) begin
		case (curr_state)
			RESET: next_state = reset ? RESET : DRAW_BOARD; 
			DRAW_BOARD: next_state = WAIT_BOARD_DONE; 
			WAIT_BOARD_DONE: next_state = done_p ? DRAW_SELECTOR : WAIT_BOARD_DONE;
			DRAW_SELECTOR: next_state = WAIT_SELECTOR_DONE;
			WAIT_SELECTOR_DONE: next_state = done_s ? WAIT_PLAYER : WAIT_SELECTOR_DONE;
			WAIT_PLAYER: next_state = player_has_input ? DO_LOGIC : WAIT_PLAYER;
			DO_LOGIC: next_state = DRAW_BOARD;
		endcase
	end

endmodule
