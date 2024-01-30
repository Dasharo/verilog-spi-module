# Verilog SPI module for TwPM project

This is FPGA based implementation of Serial Peripheral Interface (SPI) written
in Verilog HDL language. While SPI is a _de facto_ standard with many variants
used for different application, this implementation focuses on TPM protocol. As
such, only SPI mode 0 is supported (CPHA=0, CPOL=0). In addition, TPM
specification defines a method of flow control that operates on a transaction
basis that isn't used anywhere else. For these reasons, if you're  looking for a
code for use with SPI flash, sensors, SD cards or other components, this isn't
the repository you're looking for.
