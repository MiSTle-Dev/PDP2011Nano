# GW5A-LV25MG121NC1/I0, 50 MHz board oscillator.
create_clock -name clk_in -period 20.000 -waveform {0.000 10.000} [get_ports {clk_in}]

# PLLA: VCO = 50 MHz * (20 + 1/8) = 1006.25 MHz (IDIV 1, FBDIV 20 + 1/8);
# output dividers = 4, 8, 10, 20, 40 (CLKOUT0..CLKOUT4). Keep all PLL outputs related.
# CLKOUT0 (pixel x10) is unused by the top level.
create_generated_clock -name clk_hdmi_x5 -source [get_ports {clk_in}] -multiply_by 161 -divide_by 64 [get_pins {pll_inst/u_pll/PLLA_inst/CLKOUT1}]
create_generated_clock -name clk_100 -source [get_ports {clk_in}] -multiply_by 161 -divide_by 80 [get_pins {pll_inst/u_pll/PLLA_inst/CLKOUT2}]
create_generated_clock -name clk_50 -source [get_ports {clk_in}] -multiply_by 161 -divide_by 160 [get_pins {pll_inst/u_pll/PLLA_inst/CLKOUT3}]
create_generated_clock -name clk_pixel -source [get_ports {clk_in}] -multiply_by 161 -divide_by 320 [get_pins {pll_inst/u_pll/PLLA_inst/CLKOUT4}]

# SDRAM FSM (clk_100 = c0): c1 raises CPU clock, c8 lowers it, next c1 is 14 c0 cycles
# later (7 high, 7 low). Model the shortest legal cycle; do not cut CPU <-> MMU/SDRAM
# paths or add blanket multicycle exceptions.
create_generated_clock -name clk_cpu -source [get_pins {pll_inst/u_pll/PLLA_inst/CLKOUT2}] -edges {1 15 29} [get_pins {pdp11_inst/sdram0/cpuclk_s1/Q}]
# A c6 wait (MMU not ready) stretches the high phase, moving the falling edge and the next
# rising edge by one c0 period. Both phase classes are analyzed, including paths between
# them, because the wait count changes at run time.
create_generated_clock -name clk_cpu_wait -source [get_pins {pll_inst/u_pll/PLLA_inst/CLKOUT2}] -edges {1 17 31} -add [get_pins {pdp11_inst/sdram0/cpuclk_s1/Q}]

# ODDR D0=0, D1=1 forwards an inverted c0 to SDRAM.
create_generated_clock -name clk_sdram -source [get_pins {pll_inst/u_pll/PLLA_inst/CLKOUT2}] -divide_by 1 -invert [get_ports {O_sdram_clk}]

create_clock -name clk_spi_companion -period 41.666667 -waveform {0.000000 20.833333} [get_ports {pmod_companion_clk}]

report_timing -setup -from_clock [get_clocks {clk_pixel}] -to_clock [get_clocks {clk_pixel}] -max_paths 100 -max_common_paths 1
report_timing -setup -from_clock [all_clocks] -to_clock [all_clocks] -max_paths 100 -max_common_paths 1
report_timing -hold -from_clock [all_clocks] -to_clock [all_clocks] -max_paths 100 -max_common_paths 1
