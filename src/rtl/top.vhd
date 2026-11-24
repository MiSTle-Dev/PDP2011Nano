--
-- Copyright (c) 2008-2025 Sytse van Slooten
--
-- Permission is hereby granted to any person obtaining a copy of these VHDL source files and
-- other language source files and associated documentation files ("the materials") to use
-- these materials solely for personal, non-commercial purposes.
-- You are also granted permission to make changes to the materials, on the condition that this
-- copyright notice is retained unchanged.
--
-- The materials are distributed in the hope that they will be useful, but WITHOUT ANY WARRANTY;
-- without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
--

-- $Revision$

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.sd_bus_pkg.all;

entity top is
   generic(
      ttype : boolean := false; -- false for VT100/105, true for VT52 terminal
      sdram_data_width : positive := 32
   );
   port(
	   --clocks
		clk_100        : in std_logic;
		clk_50         : in std_logic;
		clk_25         : in std_logic;

		--reset
		reset          : in std_logic;
      vtreset        : in std_logic;

		-- PDP settings
      modelcode      : in integer range 0 to 255;
		serial_console : in std_logic;
      have_rk        : in integer range 0 to 1;
      have_rl        : in integer range 0 to 1;
      have_rh        : in integer range 0 to 1;
      have_tc        : in integer range 0 to 1;
      have_xu        : in integer range 0 to 4;

		-- VT settings
		vttype         : in integer;
		have_act       : in integer;
		vga_cursor_block : in std_logic;
		vga_cursor_blink : in std_logic;
		teste          : in std_logic;
		testf          : in std_logic;
		
      -- second serial port
      rx1: in std_logic;
      tx1: out std_logic;
		rts1:out std_logic;
		cts1:in std_logic;

      -- sd card
      rk_sdcard_req   : out sd_req_t;
      rk_sdcard_rsp   : in sd_rsp_t := SD_RSP_IDLE;
		rk_sdcard_debug: out std_logic_vector (3 downto 0);

      rl_sdcard_req   : out sd_req_t;
      rl_sdcard_rsp   : in sd_rsp_t := SD_RSP_IDLE;
		rl_sdcard_debug: out std_logic_vector (3 downto 0);

      rh_sdcard_req   : out sd_req_t;
      rh_sdcard_rsp   : in sd_rsp_t := SD_RSP_IDLE;
		rh_sdcard_debug: out std_logic_vector (3 downto 0);
      rh_type        : in integer range 1 to 7 := 6; 

      tc_sdcard_req   : out sd_req_t;
      tc_sdcard_rsp   : in sd_rsp_t := SD_RSP_IDLE;
      tc_sdcard_debug: out std_logic_vector (3 downto 0);

      -- Ethernet
      xu_cs   : out std_logic;
      xu_mosi : out std_logic;
      xu_sclk : out std_logic;
      xu_miso : in std_logic;
      xu_debug_tx : out std_logic;

      -- pidp11 console
      panel_xled : out std_logic_vector(5 downto 0);
      panel_col : inout std_logic_vector(11 downto 0);
      panel_row : out std_logic_vector(2 downto 0);

      -- dram
      dram_addr      : out std_logic_vector(14 - sdram_data_width / 8 downto 0);
      dram_dq        : inout std_logic_vector(sdram_data_width - 1 downto 0);
      dram_dqm       : out std_logic_vector(sdram_data_width / 8 - 1 downto 0);
      O_sdram_ba     : out std_logic_vector(1 downto 0);
      dram_ras_n     : out std_logic;
      dram_cas_n     : out std_logic;
      dram_cke       : out std_logic;
      dram_clk       : out std_logic;
      dram_we_n      : out std_logic;
      dram_cs_n      : out std_logic;

		-- vga and keyboard
      vga_hsync      : out std_logic;
      vga_vsync      : out std_logic;
      vga_hblank     : out std_logic;
      vga_vblank     : out std_logic;
      vga_fb         : out std_logic;
      vga_ht         : out std_logic;

      usb_kbd        : in std_logic_vector (7 downto 0);
      kbd_strobe     : in std_logic;

      -- board peripherals
      greenled       : out std_logic
     );
   end top;

   architecture implementation of top is

signal cpuclk : std_logic;
signal cpureset : std_logic := '1';

signal ifetch: std_logic;
signal iwait: std_logic;
signal vt_ifetch: std_logic;
signal vt_iwait: std_logic;

signal txtx0 : std_logic;
signal rxrx0 : std_logic;
signal ctscts0: std_logic;
signal rtsrts0: std_logic;

signal txtx1 : std_logic;
signal rxrx1 : std_logic;
signal ctscts1: std_logic;
signal rtsrts1: std_logic;

signal txtx2 : std_logic;
signal rxrx2 : std_logic;
signal txtx3 : std_logic;
signal rxrx3 : std_logic;

signal vtrx  : std_logic;
signal vttx  : std_logic;
signal vtcts : std_logic;
signal vtrts : std_logic;

signal addr : std_logic_vector(21 downto 0);
signal dati : std_logic_vector(15 downto 0);
signal dato : std_logic_vector(15 downto 0);
signal control_dati : std_logic;
signal control_dato : std_logic;
signal control_datob : std_logic;

signal dram_match : std_logic;

signal cons_load : std_logic;
signal cons_exa : std_logic;
signal cons_dep : std_logic;
signal cons_cont : std_logic;
signal cons_ena : std_logic;
signal cons_start : std_logic;
signal cons_sw : std_logic_vector(21 downto 0);
signal cons_adss_mode : std_logic_vector(1 downto 0);
signal cons_adss_id : std_logic;
signal cons_adss_cons : std_logic;

signal cons_consphy : std_logic_vector(21 downto 0);
signal cons_progphy : std_logic_vector(21 downto 0);
signal cons_br : std_logic_vector(15 downto 0);
signal cons_shfr : std_logic_vector(15 downto 0);
signal cons_maddr : std_logic_vector(15 downto 0);
signal cons_dr : std_logic_vector(15 downto 0);
signal cons_parh : std_logic;
signal cons_parl : std_logic;

signal cons_adrserr : std_logic;
signal cons_run : std_logic;
signal cons_pause : std_logic;
signal cons_master : std_logic;
signal cons_kernel : std_logic;
signal cons_super : std_logic;
signal cons_user : std_logic;
signal cons_id : std_logic;
signal cons_map16 : std_logic;
signal cons_map18 : std_logic;
signal cons_map22 : std_logic;

signal cons_reset : std_logic;
signal mmu_ready : std_logic;

begin

   pdp11: entity work.unibus
   port map(
      modelcode => modelcode,  -- 24,45,70,94...
      lookup_clk => clk_50,
      sdcard_clk => clk_25,
      mmu_ready => mmu_ready,

      have_kl11 => 2,
      tx0 => txtx0,
      rx0 => rxrx0,
		cts0=> ctscts0,
		rts0=> rtsrts0,
		kl0_bps => 19200,
      kl0_force7bit => 0,
		kl0_rtscts => 0,

      tx1 => txtx1,
      rx1 => rxrx1,
		cts1=> ctscts1,
		rts1=> rtsrts1,
		kl1_bps => 19200,
		kl1_force7bit => 0,
		kl1_rtscts => 0,
		
--      tx2 => txtx2,
--      rx2 => rxrx2,
--      kl2_bps => 9600,
--      kl2_force7bit => 0,

--      tx3 => txtx3,
--      rx3 => rxrx3,
--      kl3_bps => 9600,
--      kl3_force7bit => 0,
		
      have_rl => have_rl,
      rl_sdcard_req   => rl_sdcard_req,
      rl_sdcard_rsp   => rl_sdcard_rsp,
      rl_sdcard_debug => rl_sdcard_debug,

		have_rk => have_rk,
		rk_sdcard_req   => rk_sdcard_req,
      rk_sdcard_rsp   => rk_sdcard_rsp,
      rk_sdcard_debug => rk_sdcard_debug,

      have_rh => have_rh,
      rh_sdcard_req => rh_sdcard_req,
      rh_sdcard_rsp => rh_sdcard_rsp,
      rh_sdcard_debug => rh_sdcard_debug,
      rh_type => rh_type,

      have_tc => have_tc,
      tc_sdcard_req => tc_sdcard_req,
      tc_sdcard_rsp => tc_sdcard_rsp,
      tc_sdcard_debug => tc_sdcard_debug,

      have_xu => have_xu, -- have_xu_esp,
      xu_cs => xu_cs,
      xu_mosi => xu_mosi,
      xu_sclk => xu_sclk,
      xu_miso => xu_miso,
      xu_debug_tx => xu_debug_tx,

      cons_load => cons_load,
      cons_exa => cons_exa,
      cons_dep => cons_dep,
      cons_cont => cons_cont,
      cons_ena => cons_ena,
      cons_start => cons_start,
      cons_sw => cons_sw,
      cons_adss_mode => cons_adss_mode,
      cons_adss_id => cons_adss_id,
      cons_adss_cons => cons_adss_cons,

      cons_consphy => cons_consphy,
      cons_progphy => cons_progphy,
      cons_shfr => cons_shfr,
      cons_maddr => cons_maddr,
      cons_br => cons_br,
      cons_dr => cons_dr,
      cons_parh => cons_parh,
      cons_parl => cons_parl,

      cons_adrserr => cons_adrserr,
      cons_run => cons_run,
      cons_pause => cons_pause,
      cons_master => cons_master,
      cons_kernel => cons_kernel,
      cons_super => cons_super,
      cons_user => cons_user,
      cons_id => cons_id,
      cons_map16 => cons_map16,
      cons_map18 => cons_map18,
      cons_map22 => cons_map22,

      addr => addr,
      dati => dati,
      dato => dato,
      control_dati => control_dati,
      control_dato => control_dato,
      control_datob => control_datob,
      addr_match => dram_match,

      ifetch => ifetch,
      iwait => iwait,

      reset => cpureset,
      clk50mhz => clk_50,
      clk => cpuclk
   );

   sdram0: entity work.sdram
   generic map(
      sdram_data_width => sdram_data_width
   )
   port map(
      addr => addr,
      dati => dati,
      dato => dato,
      control_dati => control_dati,
      control_dato => control_dato,
      control_datob => control_datob,
      dram_match => dram_match,
      mmu_ready => mmu_ready,

      dram_addr => dram_addr,
      dram_dq => dram_dq,
      dram_dqm => dram_dqm,
      O_sdram_ba => O_sdram_ba,
      dram_ras_n => dram_ras_n,
      dram_cas_n => dram_cas_n,
      dram_we_n => dram_we_n,
      dram_cs_n => dram_cs_n,
      dram_cke => dram_cke,
      dram_clk => dram_clk,

      reset => reset,
      ext_reset => cons_reset,
      cpureset => cpureset,
      cpuclk => cpuclk,
      c0 => clk_100,
      clk_25 => clk_25
   );

   panel: entity work.paneldriver port map(
      panel_xled => panel_xled,
      panel_col => panel_col,
      panel_row => panel_row,

      cons_load => cons_load,
      cons_exa => cons_exa,
      cons_dep => cons_dep,
      cons_cont => cons_cont,
      cons_ena => cons_ena,
      cons_start => cons_start,
      cons_sw => cons_sw,
      cons_adss_mode => cons_adss_mode,
      cons_adss_id => cons_adss_id,
      cons_adss_cons => cons_adss_cons,

      cons_consphy => cons_consphy,
      cons_progphy => cons_progphy,
      cons_shfr => cons_shfr,
      cons_maddr => cons_maddr,
      cons_br => cons_br,
      cons_dr => cons_dr,
      cons_parh => cons_parh,
      cons_parl => cons_parl,

      cons_adrserr => cons_adrserr,
      cons_run => cons_run,
      cons_pause => cons_pause,
      cons_master => cons_master,
      cons_kernel => cons_kernel,
      cons_super => cons_super,
      cons_user => cons_user,
      cons_id => cons_id,
      cons_map16 => cons_map16,
      cons_map18 => cons_map18,
      cons_map22 => cons_map22,

      cons_reset => cons_reset,

      paneltype => 0,

      clkin => cpuclk,
      reset => reset
   );

   default_term: if not ttype generate
	  vt0: entity work.vt port map(
      vttype => vttype,
      vga_hsync => vga_hsync,
      vga_vsync => vga_vsync,
      vga_hblank => vga_hblank,
      vga_vblank => vga_vblank,
      vga_fb => vga_fb,
      vga_ht => vga_ht,

      rx => vtrx,
      tx => vttx,
		cts=> vtcts,
		rts=> vtrts,
      bps => 19200,
		force7bit => 0,

      usb_kbd => usb_kbd,
      kbd_strobe => kbd_strobe,

      vga_cursor_block => vga_cursor_block,
      vga_cursor_blink => vga_cursor_blink,
      teste => teste,
      testf => testf,
		
		ifetch => vt_ifetch,
		iwait  => vt_iwait,

      have_act_seconds => 900,  -- screen activity counter
      have_act => have_act,     --Screen activity

      cpuclk => cpuclk,
      clk50mhz => clk_50,
      reset => vtreset 
   );
   end generate;

   vt_term: if ttype generate
   vt52inst: entity work.vt52
   port map (
      clk         => clk_50,
      clk_pixel   => clk_25,
      uart_clk    => clk_50,
      pll_lock    => not vtreset,
      hsync       => vga_hsync,
      vsync       => vga_vsync,
      vblank      => vga_vblank,
      hblank      => vga_hblank,
      video       => vga_fb,
      led         => open,
      usb_kbd     => usb_kbd,
      kbd_strobe  => kbd_strobe,
      rxd         => vtrx,
      txd         => vttx
   );

   vga_ht <= '1';
  end generate;

   vtrx <= txtx0;
   rxrx0 <= vttx;
   ctscts0 <= '0';

   -- 2nd serial port
   rxrx1 <= rx1; 
   tx1 <= txtx1;
   ctscts1 <= cts1;
   rts1 <= '1';

   greenled  <= '0';

	dram_match <= '1' when addr(21 downto 18) /= "1111" else '0';

end implementation;

