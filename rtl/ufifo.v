////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	ufifo.v
//
// Project:	wbuart32, a full featured UART with simulator
//
// Purpose:	
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2015-2016, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory, run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
module ufifo(i_clk, i_rst, i_wr, i_data, i_rd, o_data,
		o_empty_n, o_half_full, o_status, o_err);
	parameter	BW=8, LGFLEN=4;
	input			i_clk, i_rst;
	input			i_wr;
	input	[(BW-1):0]	i_data;
	input			i_rd;
	output	reg [(BW-1):0]	o_data;
	output	reg		o_empty_n, o_half_full;
	output	wire	[15:0]	o_status;
	output	wire		o_err;

	localparam	FLEN=(1<<LGFLEN);

	reg	[(BW-1):0]	fifo[0:(FLEN-1)];
	reg	[(LGFLEN-1):0]	r_first, r_last;

	wire	[(LGFLEN-1):0]	w_first_plus_one, w_first_plus_two,
				w_last_plus_one;
	assign	w_first_plus_two = r_first + {{(LGFLEN-2){1'b0}},2'b10};
	assign	w_first_plus_one = r_first + {{(LGFLEN-1){1'b0}},1'b1};
	assign	w_last_plus_one  = r_last  + {{(LGFLEN-1){1'b0}},1'b1};

	reg	will_overflow;
	initial	will_overflow = 1'b0;
	always @(posedge i_clk)
		if (i_rst)
			will_overflow <= 1'b0;
		else if (i_rd)
			will_overflow <= (will_overflow)&&(i_wr);
		else if (i_wr)
			will_overflow <= (w_first_plus_two == r_last);
		else if (w_first_plus_one == r_last)
			will_overflow <= 1'b1;

	// Write
	reg	r_ovfl;
	initial	r_first = 0;
	initial	r_ovfl  = 0;
	always @(posedge i_clk)
		if (i_rst)
		begin
			r_ovfl <= 1'b0;
			r_first <= { (LGFLEN){1'b0} };
		end else if (i_wr)
		begin // Cowardly refuse to overflow
			if ((i_rd)||(!will_overflow)) // (r_first+1 != r_last)
				r_first <= w_first_plus_one;
			else
				r_ovfl <= 1'b1;
		end
	always @(posedge i_clk)
		if (i_wr) // Write our new value regardless--on overflow or not
			fifo[r_first] <= i_data;

	// Reads
	//	Following a read, the next sample will be available on the
	//	next clock
	//	Clock	ReadCMD	ReadAddr	Output
	//	0	0	0		fifo[0]
	//	1	1	0		fifo[0]
	//	2	0	1		fifo[1]
	//	3	0	1		fifo[1]
	//	4	1	1		fifo[1]
	//	5	1	2		fifo[2]
	//	6	0	3		fifo[3]
	//	7	0	3		fifo[3]
	reg	will_underflow, r_unfl;
	initial	will_underflow = 1'b1;
	always @(posedge i_clk)
		if (i_rst)
			will_underflow <= 1'b1;
		else if (i_wr)
			will_underflow <= (will_underflow)&&(i_rd);
		else if (i_rd)
			will_underflow <= (w_last_plus_one == r_first);
		else
			will_underflow <= (r_last == r_first);

	initial	r_unfl = 1'b0;
	initial	r_last = 0;
	always @(posedge i_clk)
		if (i_rst)
		begin
			r_last <= { (LGFLEN){1'b0} };
			r_unfl <= 1'b0;
		end else if (i_rd)
		begin
			if ((i_wr)||(!will_underflow)) // (r_first != r_last)
				r_last <= w_last_plus_one;
				// Last chases first
				// Need to be prepared for a possible two
				// reads in quick succession
				// o_data <= fifo[r_last+1];
			else
				r_unfl <= 1'b1;
		end
	always @(posedge i_clk)
		o_data <= fifo[(i_rd)?(r_last+{{(LGFLEN-1){1'b0}},1'b1})
					:(r_last)];

	// wire	[(LGFLEN-1):0]	current_fill;
	// assign	current_fill = (r_first-r_last);

	always @(posedge i_clk)
		if (i_rst)
			o_empty_n <= 1'b0;
		else
			o_empty_n <= (~i_rd)&&(r_first != r_last)
					||(i_rd)&&(r_first != w_last_plus_one);

	reg	[(LGFLEN-1):0]	r_fill;
	always @(posedge i_clk)
		if (i_rst)
			r_fill <= 0;
		else if ((i_rd)&&(!i_wr))
			r_fill <= r_first - r_last - 1'b1;
		else if ((!i_rd)&&(i_wr))
			r_fill <= r_first - r_last + 1'b1;
		else
			r_fill <= r_first - r_last;
	assign	o_half_full = r_fill[(LGFLEN-1)];

	wire	[3:0]	lglen;
	assign lglen = LGFLEN;
	assign	o_status = { lglen, {(16-2-4-LGFLEN){1'b0}}, r_fill, o_half_full, o_empty_n };
	
endmodule
