set board "tang_nano20k"
set config "pdp2011nano"
source scripts/update_xml.tcl

set_device GW2AR-LV18QN88C8/I7 -name GW2AR-18C

add_file ../rtl/sd_card_if.sv
add_file gowin_dpb/sector_dpram.v
add_file hdmi/audio_clock_regeneration_packet.sv
add_file hdmi/audio_info_frame.sv
add_file hdmi/audio_sample_packet.sv
add_file hdmi/auxiliary_video_information_info_frame.sv
add_file hdmi/hdmi.sv
add_file hdmi/packet_assembler.sv
add_file hdmi/packet_picker.sv
add_file hdmi/serializer.sv
add_file hdmi/source_product_description_info_frame.sv
add_file hdmi/tmds_channel.sv
add_file misc/hid.v
add_file misc/mcu_spi.v
add_file misc/osd_u8g2.v
add_file misc/sd_card.v
add_file misc/sd_rw.v
add_file misc/sdcmd_ctrl.v
add_file misc/sysctrl.v
add_file misc/video.v
add_file misc/video_analyzer.v
add_file misc/ws2812.v
add_file ../rtl/cpu.vhd
add_file ../rtl/cpuregs.vhd
add_file ../rtl/cr.vhd
add_file ../rtl/csdr.vhd
add_file ../rtl/dr11c.vhd
add_file ../rtl/fpuregs.vhd
add_file ../rtl/ibv11.vhd
add_file ../rtl/ibv11_ah.vhd
add_file ../rtl/ibv11_c.vhd
add_file ../rtl/ibv11_e2.vhd
add_file ../rtl/ibv11_sh.vhd
add_file ../rtl/kl11.vhd
add_file ../rtl/kw11l.vhd
add_file ../rtl/m9312h-minc.vhd
add_file ../rtl/m9312h-odt.vhd
add_file ../rtl/m9312h-pdp2011.vhd
add_file ../rtl/m9312l-minc.vhd
add_file ../rtl/m9312l-odt.vhd
add_file ../rtl/m9312l-pdp2011.vhd
add_file ../rtl/mmu.vhd
add_file ../rtl/mncaa.vhd
add_file ../rtl/mncad.vhd
add_file ../rtl/mncdi.vhd
add_file ../rtl/mncdo.vhd
add_file ../rtl/mnckw.vhd
add_file ../rtl/paneldb.vhd
add_file ../rtl/paneldriver.vhd
add_file ../rtl/panelos.vhd
add_file ../rtl/top.vhd
add_file ../rtl/pdp2011.vhd
add_file ../rtl/ps2.vhd
add_file ../rtl/rh11.vhd
add_file ../rtl/rk11.vhd
add_file ../rtl/rl11.vhd
add_file ../rtl/sdram.vhd
add_file ../rtl/sdspi.vhd
add_file ../rtl/tc11.vhd
add_file ../rtl/unibus.vhd
add_file ../rtl/vga.vhd
add_file ../rtl/vgacr.vhd
add_file ../rtl/vgafont.vhd
add_file ../rtl/vt.vhd
add_file ../rtl/vtbr.vhd
add_file ../rtl/xu.vhd
add_file ../rtl/xu28m.vhd
add_file ../rtl/xubf.vhd
add_file ../rtl/xubg.vhd
add_file ../rtl/xubl.vhd
add_file ../rtl/xubm.vhd
add_file ../rtl/xubr.vhd
add_file ../rtl/xubs.vhd
add_file ../rtl/xubw.vhd
add_file tang/tn20k/pdp11nano.vhd
add_file tang/tn20k/gowin_rpll/gowin_rpll_126mhz.vhd
add_file tang/tn20k/pdp11nano.cst
add_file tang/tn20k/pdp11nano.sdc

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name pdp11
set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -top_module pdp11nano
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -rw_check_on_ram 0
set_option -user_code 00000001
set_option -bit_security 1
set_option -ireg_in_iob 1
set_option -oreg_in_iob 1
set_option -ioreg_in_iob 1

run all
