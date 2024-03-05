// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2024 3mdeb Sp. z o.o.

`timescale 1 ns / 1 ps

`define ST_D_S            0
`define ST_ADDR1          1
`define ST_ADDR2          2
`define ST_ADDR3          3
`define ST_WRITE          4
`define ST_READ           5

module spi_periph (
  clk_i,
  miso,
  mosi,
  cs_n,
  data_i,
  data_o,
  addr_o,
  data_wr,
  wr_done,
  data_rd,
  data_req
);
  // verilog_format: off  // verible-verilog-format messes up comments alignment
  //# {{SPI interface}}
  input  wire        clk_i;     // Serial Clock
  output wire        miso;      // Main In Sub Out
  input  wire        mosi;      // Main Out Sub In
  input  wire        cs_n;      // Chip Select, active low

  //# {{Interface to data provider}}
  input  wire [ 7:0] data_i;    // Data to be sent (I/O Read) to host
  output reg  [ 7:0] data_o;    // Data received (I/O Write) from host
  output reg  [15:0] addr_o;    // 16-bit TPM Register Address
  output wire        data_wr;   // Signal to data provider that data_o has valid write data
  input  wire        wr_done;   // Signal from data provider that data_o has been read,
                                // ignored for SPI because there is no inter-byte flow control
  input  wire        data_rd;   // Signal from data provider that data_i has data for read
  output wire        data_req;  // Signal to data provider that is requested (@posedge) or
                                // has been read (@negedge) from data_i

  reg  [ 2:0] state;
  reg  [ 2:0] bit_counter;
  reg  [ 1:0] size;
  reg  [ 7:0] byte_buf;
  reg         direction;
  reg         mask_cs;
  wire        effective_cs;
  reg         miso_r;
  reg         data_req_reg;
  reg         data_wr_reg;
  // verilog_format: on

  assign effective_cs = cs_n | mask_cs;
  assign miso = effective_cs ? 1'bz : miso_r;

  // Symbolator treats function inputs as module ports until it sees uncommented
  // 'endmodule' (almost) anywhere before the function, it may even be part of
  // longer name, so here it is:
  `undef _________endmodule_________

  // "If the transaction crosses a register boundary, the TPM may choose to
  //  accept all the data and discard the data that exceeds the size limit for
  //  that register as long as doing so does not cause a change to the state of
  //  any adjacent register."
  // This implementation chooses to trim each access to first 4B boundary higher
  // than the address. In FIFO TPM interface, there are no multiple smaller
  // registers in one 4B-aligned chunk of memory space, and there is only one
  // register that may be bigger than 4B (TPM_HASH_START), although the
  // specification isn't clear on that. It has 8B allocated in register map,
  // informative comment in "7.4 SPI Hardware Protocol" says that it is 4B, and
  // description in "Table 19 - Allocation of Register Space for FIFO TPM
  // Access" says that "This command SHALL be done on the LPC bus as a single
  // write to 4028h. Writes to 4029h to 402Fh are not decoded by TPM". To keep
  // the registers module implementation consistent between LPC and SPI, this
  // implementation treats TPM_HASH_START as 1B register.
  //
  // The following function checks if the access crosses 4B boundary, and when
  // it does, the size is limited to maximum size that doesn't cross it.
  function [1:0] validate_size;
    input [1:0] addr;
    input [1:0] size;
    reg [2:0] sum;
    begin
      sum = addr + size;
      if (sum >= 3'b100) begin
        validate_size = 2'b11 - addr;
      end else begin
        validate_size = size;
      end
    end
  endfunction

  wire [99:0] buffers_in, buffers_out;
  assign buffers_in = {buffers_out[98:0], data_req_reg};
  assign data_req = buffers_out[49];

  LUT4 #(
	.INIT(16'd2)
  ) buffers [99:0] (
	.Z(buffers_out),
	.A(buffers_in),
	.B(1'b0),
	.C(1'b0),
	.D(1'b0),
  );

  wire [99:0] wbuffers_in, wbuffers_out;
  assign wbuffers_in = {wbuffers_out[98:0], data_wr_reg};
  assign data_wr = wbuffers_out[49];

  LUT4 #(
	.INIT(16'd2)
  ) wbuffers [99:0] (
	.Z(wbuffers_out),
	.A(wbuffers_in),
	.B(1'b0),
	.C(1'b0),
	.D(1'b0),
  );

  // Drive on falling edge
  always @(negedge clk_i) begin
    miso_r <= 1;
    if (effective_cs == 1'b0 && state == `ST_READ)
      miso_r <= data_i[bit_counter];
  end

  // Sample on rising edge
  always @(posedge clk_i or posedge cs_n) begin
    data_req_reg <= 1'b0;
    data_wr_reg <= 1'b0;
    bit_counter <= 3'd7;
    if (cs_n === 1'b1) begin
      mask_cs <= 1'b0;
      state <= `ST_D_S;
      data_req_reg <= 1'b0;
      data_wr_reg <= 1'b0;
      size <= 2'd0;
      bit_counter <= 3'd7;
    end else if (effective_cs === 1'b0) begin
      bit_counter <= bit_counter - 3'd1;
      case (state)
        `ST_D_S: begin
          data_req_reg <= 0;
          data_wr_reg <= 0;
          byte_buf[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            direction <= byte_buf[7];
            size <= {byte_buf[1], mosi};
            state <= `ST_ADDR1;
            // Handle over-sized transfers and reserved bit
            if (|byte_buf[6:2] !== 1'b0) begin
              mask_cs <= 1'b1;
              state <= `ST_D_S;
            end
          end
        end
        `ST_ADDR1: begin
          byte_buf[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            if ({byte_buf[7:1], mosi} === 8'hD4) begin
              state <= `ST_ADDR2;
            end else begin
              // Pretend we're not the receiver of this transaction
              mask_cs <= 1'b1;
              state <= `ST_D_S;
            end
          end
        end
        `ST_ADDR2: begin
          byte_buf[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            addr_o[15:8] <= {byte_buf[7:1], mosi};
            state <= `ST_ADDR3;
          end
        end
        `ST_ADDR3: begin
          byte_buf[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            addr_o[7:0] <= {byte_buf[7:1], mosi};
            size <= validate_size ({byte_buf[1], mosi}, size);
            if (direction) begin
              data_req_reg <= 1'b1;
              state <= `ST_READ;
            end else begin
              state <= `ST_WRITE;
            end
          end
        end
        `ST_WRITE: begin
          byte_buf[bit_counter] <= mosi;
          data_wr_reg <= 1'b0;
          if (bit_counter === 3'd0) begin
            data_o <= {byte_buf[7:1], mosi};
            data_wr_reg <= 1'b1;
            size <= size - 2'd1;
            state <= `ST_WRITE;
            if (size === 2'd0) begin
              // Mask CS to hide implicit 9th edge caused by CS transition
              mask_cs <= 1'b1;
              state <= `ST_D_S;
            end else begin
              addr_o <= addr_o + 16'd1;
            end
          end
        end
        `ST_READ: begin
          data_wr_reg <= 1'b0;
          if (bit_counter === 3'd1) begin
            data_req_reg <= 1'b0;
          end
          if (bit_counter === 3'd0) begin
            size <= size - 2'd1;
            state <= `ST_READ;
            // Don't fetch data past last byte, some reads have side effects!
            if (size !== 2'd0) begin
              addr_o <= addr_o + 16'd1;
              data_req_reg <= 1'b1;
            end else begin
              // Mask CS to hide implicit 9th edge caused by CS transition
              mask_cs <= 1'b1;
              data_req_reg <= 1'b0;
              state <= `ST_D_S;
            end
          end
        end
      endcase
    end
  end

endmodule
