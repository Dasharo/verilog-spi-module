// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2024 3mdeb Sp. z o.o.

`timescale 1 ns / 1 ps

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
  output wire        miso;      // Main In Sub Out
  input  wire        mosi;      // Main Out Sub In
  input  wire        cs;        // Chip Select, active low

  //# {{Interface to data provider}}
  input  wire [ 7:0] data_i;    // Data to be sent (I/O Read) to host
  output reg  [ 7:0] data_o;    // Data received (I/O Write) from host
  output reg  [15:0] addr_o;    // 16-bit TPM Register Address
  output             data_wr;   // Signal to data provider that data_o has valid write data
  input  wire        wr_done;   // Signal from data provider that data_o has been read
  input  wire        data_rd;   // Signal from data provider that data_i has data for read
  output             data_req;  // Signal to data provider that is requested (@posedge) or
                                // has been read (@negedge) from data_i

assign miso = 1;

endmodule
