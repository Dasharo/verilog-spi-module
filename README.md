# Verilog SPI module for TwPM project

This is FPGA based implementation of Serial Peripheral Interface (SPI) written
in Verilog HDL language. While SPI is a _de facto_ standard with many variants
used for different application, this implementation focuses on TPM protocol. As
such, only SPI mode 0 is supported (CPHA=0, CPOL=0). In addition, TPM
specification defines a method of flow control that operates on a transaction
basis that isn't used anywhere else. For these reasons, if you're  looking for a
code for use with SPI flash, sensors, SD cards or other components, this isn't
the repository you're looking for.

## Funding

This project was partially funded through the
[NGI Assure](https://nlnet.nl/assure) Fund, a fund established by
[NLnet](https://nlnet.nl/) with financial support from the European
Commission's [Next Generation Internet](https://ngi.eu/) programme, under the
aegis of DG Communications Networks, Content and Technology under grant
agreement No 957073.

<p align="center">
<img src="https://nlnet.nl/logo/banner.svg" height="75">
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
<img src="https://nlnet.nl/image/logos/NGIAssure_tag.svg" height="75">
</p>
