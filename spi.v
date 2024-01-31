// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2024 3mdeb Sp. z o.o.

`timescale 1 ns / 1 ps

`define ST_IDLE           0
`define ST_D_S            1
`define ST_ADDR1          2
`define ST_ADDR2          3
`define ST_ADDR3          4
`define ST_WAIT           5
`define ST_WRITE          6
`define ST_READ           7

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
  // verilog_format: on

  initial state = `ST_IDLE;
  initial data_wr = 1'b0;
  initial data_req = 1'b0;

  // Drive on falling edge
  always @(negedge clk_i or negedge cs) begin
    if (cs == 1'b1) begin
      miso <= 1'bz;
      bit_counter <= 0;
      size <= 0;
    end else begin
      case (state)
        `ST_IDLE: begin
          miso <= 1'bz;
          bit_counter <= 3'd7;
          data_req <= 0;    // Here or posedge?
          data_wr <= 0;     // Here or posedge?
        end
        `ST_D_S: begin
          bit_counter <= bit_counter - 3'd1;
          miso <= 1'bz;
        end
        `ST_ADDR1: begin
          bit_counter <= bit_counter - 3'd1;
          miso <= 1'bz;
        end
        `ST_ADDR2: begin
          bit_counter <= bit_counter - 3'd1;
          miso <= 1'bz;
        end
        `ST_ADDR3: begin
          bit_counter <= bit_counter - 3'd1;
          // Insert wait state for reads
          miso <= !direction;
        end
        `ST_WRITE: begin
          bit_counter <= bit_counter - 3'd1;
          miso <= 1'b1;
        end
      endcase
    end
  end

  // Sample on rising edge
  // XXX: Should posedge cs also be in sensitivity list?
  always @(posedge clk_i) begin
    if (cs == 1'b1) begin
      state <= `ST_IDLE;
    end else begin
      case (state)
        `ST_IDLE: begin
          size <= 0;
          state <= `ST_D_S;
        end
        `ST_D_S: begin
          byte[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            direction <= byte[7];
            // TODO: handle oversized transfers
            size <= {byte[1], mosi};
            state <= `ST_ADDR1;
          end
        end
        `ST_ADDR1: begin
          byte[bit_counter] <= mosi;
          if (bit_counter === 3'd0) begin
            if ({byte[7:1], mosi} === 8'hD4) begin
              state <= `ST_ADDR2;
            end // else TODO
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
            // TODO: read
            state <= `ST_WRITE;
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
            if (size === 2'd0)
              state <= `ST_IDLE;
          end
        end
      endcase
    end
  end

endmodule
