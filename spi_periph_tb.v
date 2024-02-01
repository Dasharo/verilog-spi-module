// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2024 3mdeb Sp. z o.o.

`timescale 1 ns / 1 ps

module spi_periph_tb ();

  // verilog_format: off  // verible-verilog-format messes up comments alignment
  reg  [31:0] periph_data   = 32'h00000000;
  reg  [31:0] expected_data = 32'h00000000;

  reg         clk;
  reg         mosi;
  wire        miso;
  reg         cs;

  reg         clk_en;         // SPI clock isn't freerunning
  reg         scatter_bytes;  // Some hosts pause SPI clock between bytes, simulate it
  integer     delay;          // Delay before wr_done/data_rd

  reg  [ 7:0] spi_data_i;     // Data to be sent (I/O Read) to host
  wire [ 7:0] spi_data_o;     // Data received (I/O Write) from host
  wire [15:0] spi_addr_o;     // 16-bit TPM Address
  wire        spi_data_wr;    // Signal to data provider that spi_data_o has valid write data
  reg         spi_wr_done;    // Signal from data provider that spi_data_o has been read
  reg         spi_data_rd;    // Signal from data provider that spi_data_i has data for read
  wire        spi_data_req;   // Signal to data provider that is requested (@posedge) or
                              // has been read (@negedge)

  // verilog_format: on

  task spi_xfer_byte (input [7:0] in, output [7:0] out);
    integer bit;
    begin
      clk_en = 1;
      // Bits are always transferred from msb to lsb
      // First bit can be driven on falling CS, falling CLK or any arbitrary moment
      mosi = in[7];
      // Handle last bit separately, clk_en must be flipped before last cycle
      for (bit=0; bit<7; bit=bit+1) begin
        @(posedge clk) out[7-bit] = miso;
        @(negedge clk) mosi = in[6-bit];
      end
      clk_en = 0;
      @(posedge clk) out[0] = miso;
      @(negedge clk) mosi = 1'bz;
      if (scatter_bytes)
        #150;
    end
  endtask

  // last_byte returned to check for wait states
  task spi_addr (input [23:0] addr, output [7:0] last_byte);
    begin
      // Address is transferred from MSB to LSB
      spi_xfer_byte (addr[23:16], last_byte);
      spi_xfer_byte (addr[15: 8], last_byte);
      spi_xfer_byte (addr[ 7: 0], last_byte);
    end
  endtask

  // Up to 4 bytes
  task spi_xfer_n_bytes (input integer size, input [31:0] in, output [31:0] out);
    integer ii;
    begin
      for (ii=1; ii<=size; ii=ii+1) begin
        // Data is transferred from LSB to MSB
        // Note: `in` uses modulo arithmetic, `out` doesn't. This way we never
        // send invalid data, but we want to capture first output bytes to test
        // for over-sized transfers.
        spi_xfer_byte (in[(8*ii-1)%32 -: 8], out[8*ii-1 -: 8]);
      end
    end
  endtask

  // Up to 4 bytes, not checked to allow testing for over-sized transfers
  task spi_read_reg (input integer size, input [23:0] addr, output [31:0] data);
    reg [5:0] size_encoded;
    reg [7:0] tmp;
    begin
      size_encoded = size[5:0] - 6'd1;

      cs = 0;
      // Command and size
      spi_xfer_byte ({1'b1, 1'b0, size_encoded}, tmp);
      // Address, last read byte specifies if wait state is inserted
      spi_addr (addr, tmp);

      // Handle wait states using logical equality - avoid halting on 1'bz
      while (tmp[0] != 1'b1)
        spi_xfer_byte (8'hFF, tmp);

      // Get the data
      spi_xfer_n_bytes (size, 32'hFFFFFFFF, data);
      cs = 1;
    end
  endtask

  // Up to 4 bytes, not checked to allow testing for over-sized transfers
  task spi_write_reg (input integer size, input [23:0] addr, input [31:0] data);
    reg [5:0] size_encoded;
    reg [7:0] tmp;
    reg [31:0] ignored;
    begin
      size_encoded = size[5:0] - 6'd1;

      cs = 0;
      // Command and size
      spi_xfer_byte ({1'b0, 1'b0, size_encoded}, tmp);
      // Address, last read byte specifies if wait state is inserted
      spi_addr (addr, tmp);

      // Transfer first data byte and check for wait states - different than read
      spi_xfer_byte (data[7:0], tmp);

      // Handle wait states, keep sending first byte until TPM is ready for rest
      while (tmp[0] != 1'b1)
        spi_xfer_byte (data[7:0], tmp);

      // Send rest of the data
      spi_xfer_n_bytes (size-1, data[31:8], ignored);
      cs = 1;
    end
  endtask

  task tpm_read_reg_4B (input [15:0] addr, output [31:0] data);
    reg [31:0] expected;
    begin
      expected = periph_data;
      spi_read_reg (4, {8'hD4, addr}, data);
      if (data !== expected)
        $display("### Read failed, expected %8h, got %8h @ %t", expected, data, $realtime);
      #50;
    end
  endtask

  task tpm_read_reg_1B (input [15:0] addr, output [7:0] data);
    reg [7:0] expected;
    reg [31:0] tmp;
    begin
      expected = periph_data[7:0];
      spi_read_reg (1, {8'hD4, addr}, tmp);
      data = tmp[7:0];
      if (data !== expected)
        $display("### Read failed, expected %2h, got %2h @ %t", expected, data, $realtime);
      #50;
    end
  endtask

  task tpm_write_reg_4B (input [15:0] addr, input [31:0] data);
    begin
      spi_write_reg (4, {8'hD4, addr}, data);
      if (periph_data !== data)
        $display("### Write failed, expected %8h, got %8h @ %t", data, periph_data, $realtime);
      #50;
    end
  endtask

  task tpm_write_reg_1B (input [15:0] addr, input [7:0] data);
    begin
      spi_write_reg (1, {8'hD4, addr}, {{24{1'b0}}, data});
      if (periph_data[31:24] !== data)
        $display("### Write failed, expected %2h, got %2h @ %t", data, periph_data[31:24], $realtime);
      #50;
    end
  endtask

  initial begin
    clk = 0;
    clk_en = 0;
    scatter_bytes = 0;
    cs = 1;
  end

  always @(posedge clk_en) begin
    if (clk_en) begin
      clk = 0;
      while (clk_en) begin
        #20 clk = 1;
        #20 clk = 0;
      end
    end
  end

  initial begin
    // Initialize
    $dumpfile("spi_periph_tb.vcd");
    $dumpvars(0, spi_periph_tb);
    $timeformat(-9, 0, " ns", 10);

    #50 clk_en = 1;
    // Perform write
    $display("Performing TPM write w/o delay");
    expected_data = 8'h3C;
    tpm_write_reg_1B (16'hC44C, expected_data);

    expected_data = 32'h113C359A;
    tpm_write_reg_4B (16'h4C4C, expected_data);

    // Perform write with delay
    $display("Performing TPM write with delay");
    delay = 500;
    expected_data = 8'h42;
    tpm_write_reg_1B (16'h9C39, expected_data);

    delay = 500;
    expected_data = 32'h942E17F3;
    tpm_write_reg_4B (16'hC98C, expected_data);

    // Perform read with delay
    $display("Performing TPM read with delay");
    delay = 500;
    periph_data = 8'hA5;
    tpm_read_reg_1B (16'hFF00, expected_data);

    delay = 500;
    periph_data = 32'hFA005735;
    tpm_read_reg_4B (16'hF0F0, expected_data);

    // Perform read without delay
    $display("Performing TPM read w/o delay");
    periph_data = 8'h7E;
    tpm_read_reg_1B (16'hF00F, expected_data);

    periph_data = 32'h0712E8B0;
    tpm_read_reg_4B (16'h0000, expected_data);

    #500;

    // Test with scattered clock
    scatter_bytes = 1;
    $display("Testing transfers with scattered clock between bytes");
    expected_data = 8'h3C;
    tpm_write_reg_1B (16'hC44C, expected_data);

    expected_data = 32'h113C359A;
    tpm_write_reg_4B (16'h4C4C, expected_data);

    periph_data = 8'h7E;
    tpm_read_reg_1B (16'hF00F, expected_data);

    periph_data = 32'h0712E8B0;
    tpm_read_reg_4B (16'h0000, expected_data);

    scatter_bytes = 0;

    // Test over-sized transfers
    $display("Testing over-sized transfers");
    periph_data = 32'h2E06488B;
    spi_read_reg (7, {24'hD43210}, expected_data);
    // There should be a pull-up, but we must distinguish 0xFF from no response
    if (expected_data !== 32'hzzzzzzzz)
      $display("### Read wasn't ignored, expected zzzzzzzz, got %8h @ %t", expected_data, $realtime);
    #50;

    periph_data = 32'h78B00017;
    spi_read_reg (8, {24'hD47251}, expected_data);
    if (expected_data !== 32'hzzzzzzzz)
      $display("### Read wasn't ignored, expected zzzzzzzz, got %8h @ %t", expected_data, $realtime);
    #50;

    periph_data = 32'hzzzzzzzz;
    expected_data = 32'hE197F423;
    spi_write_reg (5, {24'hD40532}, expected_data);
    if (periph_data !== 32'hzzzzzzzz)
      $display("### Write wasn't dropped, expected zzzzzzzz, got %8h @ %t", periph_data, $realtime);
    #50;

    periph_data = 32'hzzzzzzzz;
    expected_data = 32'h01234567;
    spi_write_reg (12, {24'hD405C0}, expected_data);
    if (periph_data !== 32'hzzzzzzzz)
      $display("### Write wasn't dropped, expected zzzzzzzz, got %8h @ %t", periph_data, $realtime);
    #50;

    // Test non-TPM addresses
    $display("Testing non-TPM addresses");
    expected_data = 32'hzzzzzzzz;
    periph_data = 8'h8A;
    spi_read_reg (1, {24'h003210}, expected_data);
    // There should be a pull-up, but we must distinguish 0xFF from no response
    if (expected_data !== 32'hzzzzzzzz)
      $display("### Read wasn't ignored, expected zzzzzzzz, got %8h @ %t", expected_data, $realtime);
    #50;

    expected_data = 32'hzzzzzzzz;
    periph_data = 32'h78B00017;
    // Note: 80D4 would be valid D/S and ADDR[23:16] bytes
    spi_read_reg (4, {24'hD080D4}, expected_data);
    if (expected_data !== 32'hzzzzzzzz)
      $display("### Read wasn't ignored, expected zzzzzzzz, got %8h @ %t", expected_data, $realtime);
    #50;

    periph_data = 32'hzzzzzzzz;
    expected_data = 8'h23;
    spi_write_reg (1, {24'h054D32}, expected_data);
    if (periph_data !== 32'hzzzzzzzz)
      $display("### Write wasn't dropped, expected zzzzzzzz, got %8h @ %t", periph_data, $realtime);
    #50;

    periph_data = 32'hzzzzzzzz;
    expected_data = 32'h01234567;
    // Note: 03D4 would be valid D/S and ADDR[23:16] bytes
    spi_write_reg (4, {24'h7203D4}, expected_data);
    if (periph_data !== 32'hzzzzzzzz)
      $display("### Write wasn't dropped, expected zzzzzzzz, got %8h @ %t", periph_data, $realtime);
    #50;

    #3000;
    //------------------------------
    $stop;
    $finish;
  end

  // Simulate response to read and write requests with optional delay
  always @(posedge spi_data_wr) begin
    periph_data = {spi_data_o, periph_data[31:8]};
    #(delay) spi_wr_done = 1;
    // No delays between bytes on SPI
    delay = 0;
  end

  always @(negedge spi_data_wr) begin
    spi_wr_done = 0;
  end

  always @(posedge spi_data_req) begin
    #(delay) spi_data_i = periph_data[7:0];
    spi_data_rd = 1;
    periph_data = {8'h00, periph_data[31:8]};
    // No delays between bytes on SPI
    delay = 0;
  end

  always @(negedge spi_data_req) begin
    spi_data_rd = 0;
  end

  // SPI Peripheral instantiation
  spi_periph spi_periph_inst (
      // SPI Interface
      .clk_i(clk),
      .miso(miso),
      .mosi(mosi),
      .cs(cs),
      // Data provider interface
      .data_i(spi_data_i),
      .data_o(spi_data_o),
      .addr_o(spi_addr_o),
      .data_wr(spi_data_wr),
      .wr_done(spi_wr_done),
      .data_rd(spi_data_rd),
      .data_req(spi_data_req)
  );

endmodule
