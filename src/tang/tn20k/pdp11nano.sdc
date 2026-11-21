# GW2AR-LV18QN88C8/I7, 27 MHz board oscillator.
create_clock -name clk_in -period 37.037037 -waveform {0.000000 18.518519} [get_ports {clk_in}]
create_generated_clock -name clk_pixel_x20 -source [get_ports {clk_in}] -multiply_by 56 -divide_by 3 -phase 180 [get_pins {pll_inst/rpll_inst/CLKOUTP}]
create_generated_clock -name clk_hdmi_x5 -source [get_pins {pll_inst/rpll_inst/CLKOUTP}] -divide_by 4 [get_pins {div_inst126/CLKOUT}]
create_generated_clock -name clk_100 -source [get_pins {pll_inst/rpll_inst/CLKOUTP}] -divide_by 5 [get_pins {div_inst100/CLKOUT}]
# CLKOUTD divides unshifted CLKOUT by 10, not the 180-degree CLKOUTP.
create_generated_clock -name clk_50 -source [get_ports {clk_in}] -multiply_by 28 -divide_by 15 [get_pins {pll_inst/rpll_inst/CLKOUTD}]
create_generated_clock -name clk_pixel -source [get_pins {div_inst126/CLKOUT}] -divide_by 5 [get_pins {div_inst25/CLKOUT}]
# VGA pixel enable: vgaclk toggles on every 50.4 MHz edge, so it is clk_50 / 2.
#create_generated_clock -name clk_vga -source [get_pins {div_inst100/CLKOUT}] -divide_by 2 [get_pins {pdp11_inst/vt0/vga0/vgaclk/Q}]

# SDRAM FSM (clk_100, sdram c0): c1 raises CPU clock, c8 lowers it, next c1 is 14
# clk_100 cycles later (7 high, 7 low). Model the shortest legal cycle; do not cut
# CPU <-> MMU/SDRAM paths or add blanket multicycle exceptions.
create_generated_clock -name clk_cpu -source [get_pins {div_inst100/CLKOUT}] -edges {1 15 29} [get_pins {pdp11_inst/sdram0/cpuclk_s1/Q}]
# A c6 wait (MMU not ready) stretches the high phase, moving the falling edge and the next
# rising edge by one clk_100 period. Both phase classes are analyzed, including paths between
# them, because the wait count changes at run time.
create_generated_clock -name clk_cpu_wait -source [get_pins {div_inst100/CLKOUT}] -edges {1 17 31} -add [get_pins {pdp11_inst/sdram0/cpuclk_s1/Q}]

# ODDR (clocked by sdram c0 = clk_100) D0=0, D1=1 forwards an inverted fast clock to SDRAM.
create_generated_clock -name clk_sdram -source [get_pins {div_inst100/CLKOUT}] -divide_by 1 -invert [get_ports {O_sdram_clk}]

# SPI clocks from the BL616 MCU (onboard) and the companion pmod. spi_io_clk muxes
# between them (pdp11nano.vhd), so both port clocks propagate to the mux output.
create_clock -name clk_spi_onboard -period 41.666667 -waveform {0.000000 20.833333} [get_ports {spi_sclk}]
create_clock -name clk_spi_companion -period 41.666667 -waveform {0.000000 20.833333} [get_ports {pmod_companion_clk}]
create_clock -name spi_io_clk -period 41.666667 -waveform {0.000000 20.833333} [get_nets {spi_io_clk}]
set_clock_groups -asynchronous -group [get_clocks {clk_pixel}] -group [get_clocks {clk_spi_onboard clk_spi_companion spi_io_clk}]

report_timing -setup -from_clock [get_clocks {clk_pixel}] -to_clock [get_clocks {clk_pixel}] -max_paths 100 -max_common_paths 1
report_timing -setup -from_clock [all_clocks] -to_clock [all_clocks] -max_paths 100 -max_common_paths 1
report_timing -hold -from_clock [all_clocks] -to_clock [all_clocks] -max_paths 100 -max_common_paths 1
