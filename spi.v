// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2024 3mdeb Sp. z o.o.

`timescale 1 ns / 1 ps

`define ST_D_S            0
`define ST_ADDR1          1
`define ST_ADDR2          2
`define ST_ADDR3          3
`define ST_WAIT           4
`define ST_WRITE          5
`define ST_READ           6

module spi_periph (
  clk_i,
  miso,
  mosi,
  cs,
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
  output reg         miso;      // Main In Sub Out
  input  wire        mosi;      // Main Out Sub In
  input  wire        cs;        // Chip Select, active low

  //# {{Interface to data provider}}
  input  wire [ 7:0] data_i;    // Data to be sent (I/O Read) to host
  output reg  [ 7:0] data_o;    // Data received (I/O Write) from host
  output reg  [15:0] addr_o;    // 16-bit TPM Register Address
  output reg         data_wr;   // Signal to data provider that data_o has valid write data
  input  wire        wr_done;   // Signal from data provider that data_o has been read,
                                // ignored for SPI because there is no inter-byte flow control
  input  wire        data_rd;   // Signal from data provider that data_i has data for read
  output reg         data_req;  // Signal to data provider that is requested (@posedge) or
                                // has been read (@negedge) from data_i

  reg  [ 2:0] state;
  reg  [ 2:0] bit_counter;
  reg  [ 1:0] size;
  reg  [ 7:0] byte;
  reg         direction;
  reg         mask_cs;
  wire        effective_cs;
  // verilog_format: on

  initial state = `ST_D_S;
  initial data_wr = 1'b0;
  initial data_req = 1'b0;
  initial mask_cs = 1'b0;

  assign effective_cs = cs | mask_cs;

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
  // The following task checks if the access crosses 4B boundary, and when it
  // does, the size is limited to maximum size that doesn't cross it.
  task validate_size (input [1:0] addr, input [1:0] size, output [1:0] val_size);
    reg [2:0] sum;
    begin
      sum = addr + size;
      if (sum >= 3'b100) begin
        val_size = 2'b11 - addr;
      end else begin
        val_size = size;
      end
    end
  endtask

  // Drive on falling edge
  always @(negedge clk_i or negedge effective_cs) begin
    if (effective_cs == 1'b1) begin
      miso <= 1'bz;
    end else begin
      case (state)
        `ST_D_S: begin
          miso <= 1'bz;
        end
        `ST_ADDR1: begin
          miso <= 1'bz;
        end
        `ST_ADDR2: begin
          miso <= 1'bz;
        end
        `ST_ADDR3: begin
          // Always insert wait state for reads
          miso <= !direction;
        end
        `ST_WRITE: begin
          miso <= 1'b1;
        end
        `ST_WAIT: begin
          miso <= 1'b0;
          if (data_rd === 1'b1) begin
            // No more wait cycles
            miso <= 1'b1;
          end
        end
        `ST_READ: begin
          miso <= byte[bit_counter];
        end
      endcase
    end
  end

  // Sample on rising edge
  always @(posedge clk_i or posedge cs) begin
    if (cs === 1'b1) begin
      mask_cs <= 1'b0;
      state <= `ST_D_S;
      data_req <= 1'b0;
      data_wr <= 1'b0;
      size <= 2'd0;
      bit_counter <= 3'd7;
    end else if (effective_cs === 1'b0) begin
      bit_counter <= bit_counter - 3'd1;
      case (state)
        `ST_D_S: begin
          data_req <= 0;
          data_wr <= 0;
          byte[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            direction <= byte[7];
            size <= {byte[1], mosi};
            state <= `ST_ADDR1;
            // Handle over-sized transfers and reserved bit
            if (|byte[6:2] !== 1'b0) begin
              mask_cs <= 1'b1;
              state <= `ST_D_S;
            end
          end
        end
        `ST_ADDR1: begin
          byte[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            if ({byte[7:1], mosi} === 8'hD4) begin
              state <= `ST_ADDR2;
            end else begin
              // Pretend we're not the receiver of this transaction
              mask_cs <= 1'b1;
              state <= `ST_D_S;
            end
          end
        end
        `ST_ADDR2: begin
          byte[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            addr_o[15:8] <= {byte[7:1], mosi};
            state <= `ST_ADDR3;
          end
        end
        `ST_ADDR3: begin
          byte[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            addr_o[7:0] <= {byte[7:1], mosi};
            validate_size ({byte[1], mosi}, size, size);
            if (direction) begin
              state <= `ST_WAIT;
            end else begin
              state <= `ST_WRITE;
            end
          end
        end
        `ST_WRITE: begin
          byte[bit_counter] <= mosi;
          data_wr <= 1'b0;
          if (bit_counter === 3'd0) begin
            data_o <= {byte[7:1], mosi};
            data_wr <= 1'b1;
            size <= size - 2'd1;
            state <= `ST_WRITE;
            if (size === 2'd0) begin
              // Mask CS to hide implicit 9th edge caused by CS transition
              mask_cs <= 1'b1;
              state <= `ST_D_S;
            end
          end
        end
        `ST_WAIT: begin
          if (bit_counter === 3'd7) begin
              data_req <= 1'b1;
          end
          data_wr <= 1'b0;
          byte <= data_i;
          // Check miso instead of data_rd, it may arrive between negedge and here
          if (bit_counter === 3'd0 && miso === 1'b1) begin
            data_req <= 1'b0;
            //size <= size - 2'd1;
            state <= `ST_READ;
          end
        end
        `ST_READ: begin
          // Don't fetch data past last byte, some reads have side effects!
          if (bit_counter === 3'd7 && size !== 2'd0) begin
              data_req <= 1'b1;
          end
          data_wr <= 1'b0;
          if (bit_counter === 3'd0) begin
            byte <= data_i;
            data_req <= 1'b0;
            size <= size - 2'd1;
            state <= `ST_READ;
            if (size === 2'd0) begin
              // Mask CS to hide implicit 9th edge caused by CS transition
              mask_cs <= 1'b1;
              state <= `ST_D_S;
            end
          end
        end
      endcase
    end
  end

endmodule
