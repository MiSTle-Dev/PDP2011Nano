
--
-- Copyright (c) 2008-2021 Sytse van Slooten
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

entity vt is
   port(
      vga_hsync : out std_logic;                                     -- horizontal sync
      vga_vsync : out std_logic;                                     -- vertical sync
      vga_hblank: out std_logic;                                     
      vga_vblank : out std_logic;                                    
		ce_pix     : out std_logic;
      vga_fb : out std_logic;                                        -- output - full
      vga_ht : out std_logic;                                        -- output - half

-- serial port
      tx : out std_logic;                                            -- transmit
      rx : in std_logic;                                             -- receive
      rts : out std_logic;                                           -- request to send
      cts : in std_logic := '0';                                     -- clear to send
      bps : in integer range 1200 to 230400 := 9600;                 -- bps rate - don't set to more than 38400
      force7bit : in integer range 0 to 1 := 0;                      -- zero out high order bit on transmission and reception
      rtscts : in integer range 0 to 1 := 0;                         -- conditional compilation switch for rts and cts signals; also implies to include core that implements a silo buffer

-- usb keyboard
      usb_kbd        : in std_logic_vector (7 downto 0);
      kbd_strobe     : in std_logic;

-- debug & blinkenlights
      ifetch : out std_logic;                                        -- ifetch : the cpu is running an instruction fetch cycle
      iwait : out std_logic;                                         -- iwait : the cpu is in wait state
      teste : in std_logic := '0';                                   -- teste : display 24*80 capital E without changing the display buffer
      testf : in std_logic := '0';                                   -- testf : display 24*80 all pixels on
      vga_debug : out std_logic_vector(15 downto 0);                 -- debug output from microcode
      vga_bl : out std_logic_vector(9 downto 0);                     -- blinkenlight vector

-- vt type code : 100 or 105
      vttype : in integer := 100;                   -- vt100 or vt105
      vga_cursor_block : in std_logic := '1';                        -- cursor is block ('1') or underline ('0')
      vga_cursor_blink : in std_logic := '0';                        -- cursor blinks ('1') or not ('0')
      have_act_seconds : in integer range 0 to 7200 := 900;          -- auto screen off time, in seconds; 0 means disabled
      have_act : in integer := 2;                       -- auto screen off counter reset by keyboard and serial port activity (1) or keyboard only (2)

-- clock & reset
      cpuclk : in std_logic;                                         -- cpuclk : should be around 10MHz, give or take a few
      clk50mhz : in std_logic;                                       -- clk50mhz : used for vga signal timing
      reset : in std_logic                                           -- reset
   );
end vt;

architecture implementation of vt is

                       -- sr2, register autoincrement/autodecrement information for instruction restart



constant modelcode : integer := 20;
constant init_r7 : std_logic_vector(15 downto 0) := x"0200";         -- cpu starts at 1000 octal, 0x0200 hex
constant init_psw : std_logic_vector(15 downto 0) := x"00e0";        -- initial psw: priority 7

signal cpu_addr : std_logic_vector(15 downto 0);
signal cpu_datain : std_logic_vector(15 downto 0);
signal cpu_dataout : std_logic_vector(15 downto 0);
signal cpu_wr : std_logic;
signal cpu_rd : std_logic;
signal cpu_psw : std_logic_vector(15 downto 0);
signal cpu_psw_in : std_logic_vector(15 downto 0);
signal cpu_psw_we_even : std_logic;
signal cpu_psw_we_odd : std_logic;
signal cpu_pir_in : std_logic_vector(15 downto 0);
signal cpu_dw8 : std_logic;
signal cpu_cp : std_logic;
signal cpu_id : std_logic;
signal cpu_init : std_logic;
signal cpu_addr_match : std_logic;
signal cpu_sr0_ic : std_logic;
signal cpu_sr1 : std_logic_vector(15 downto 0);
signal cpu_sr2 : std_logic_vector(15 downto 0);
signal cpu_dstfreference : std_logic;
signal cpu_sr3csmenable : std_logic;

signal cpu_br7 : std_logic;
signal cpu_bg7 : std_logic;
signal cpu_int_vector7 : std_logic_vector(8 downto 0);
signal cpu_br6 : std_logic;
signal cpu_bg6 : std_logic;
signal cpu_int_vector6 : std_logic_vector(8 downto 0);
signal cpu_br5 : std_logic;
signal cpu_bg5 : std_logic;
signal cpu_int_vector5 : std_logic_vector(8 downto 0);
signal cpu_br4 : std_logic;
signal cpu_bg4 : std_logic;
signal cpu_int_vector4 : std_logic_vector(8 downto 0);

signal mmu_trap : std_logic;
signal mmu_abort : std_logic;
signal mmu_oddabort : std_logic;
signal cpu_ack_mmuabort : std_logic;
signal cpu_ack_mmutrap : std_logic;

signal cpu_npr : std_logic;
signal cpu_npg : std_logic;

signal nxmabort : std_logic;
signal oddabort : std_logic;
signal illhalt : std_logic;
signal ysv : std_logic;
signal rsv : std_logic;
signal ifetchcopy : std_logic;

signal bus_unibus_mapped : std_logic;

signal bus_addr : std_logic_vector(21 downto 0);
signal bus_dati : std_logic_vector(15 downto 0);
signal bus_dato : std_logic_vector(15 downto 0);
signal bus_control_dati : std_logic;
signal bus_control_dato : std_logic;
signal bus_control_datob : std_logic;

signal busmaster_nxmabort : std_logic;

signal bus_addr_match : std_logic;
signal unibus_addr_match : std_logic;

signal unibus_addr : std_logic_vector(17 downto 0);
signal unibus_dati : std_logic_vector(15 downto 0);
signal unibus_dato : std_logic_vector(15 downto 0);
signal unibus_control_dati : std_logic;
signal unibus_control_dato : std_logic;
signal unibus_control_datob : std_logic;

signal unibus_busmaster_addr : std_logic_vector(17 downto 0);
signal unibus_busmaster_dati : std_logic_vector(15 downto 0);
signal unibus_busmaster_dato : std_logic_vector(15 downto 0);
signal unibus_busmaster_control_dati : std_logic;
signal unibus_busmaster_control_dato : std_logic;
signal unibus_busmaster_control_datob : std_logic;
signal unibus_busmaster_control_npg : std_logic;

signal kl0_addr_match : std_logic;
signal kl0_dati : std_logic_vector(15 downto 0);

signal ps2_addr_match : std_logic;
signal ps2_dati : std_logic_vector(15 downto 0);

signal ram_addr_match : std_logic;
signal ram_dati : std_logic_vector(15 downto 0);

signal vga_addr_match : std_logic;
signal vga_dati : std_logic_vector(15 downto 0);
signal vgacr_addr_match : std_logic;
signal vgacr_dati : std_logic_vector(15 downto 0);

signal vga_cursor : std_logic_vector(12 downto 0);
signal vga_shade0 : std_logic_vector(7 downto 0);
signal vga_shade1 : std_logic_vector(7 downto 0);
signal vga_xp : std_logic_vector(8 downto 0);
signal vga_acth : std_logic_vector(7 downto 0);
signal vga_actl : std_logic_vector(7 downto 0);

signal vga_graphics : std_logic;
signal vga_graph0 : std_logic;
signal vga_graph1 : std_logic;
signal vga_hist0 : std_logic;
signal vga_hist1 : std_logic;
signal vga_hlines : std_logic;
signal vga_vlines : std_logic;
signal vga_vcur : std_logic;
signal vga_marker0 : std_logic;
signal vga_marker1 : std_logic;
signal vga_graph0s : std_logic;
signal vga_graph1s : std_logic;
signal vga_strip0 : std_logic;
signal vga_strip1 : std_logic;
signal vga_square : std_logic;
signal vga_doublewidth : std_logic_vector(23 downto 0);
signal vga_doubleheight : std_logic_vector(23 downto 0);
signal vga_doubleheight_low : std_logic_vector(23 downto 0);

signal cer_nxmabort : std_logic;
signal cer_ioabort : std_logic;

signal cpu_stack_limit : std_logic_vector(15 downto 0);
signal cpu_kmillhalt : std_logic;

signal cr_addr_match : std_logic;
signal cr_dati : std_logic_vector(15 downto 0);

signal nclk : std_logic;

begin

   rts <= '0';                                                    -- no flow control on the VT terminal

   cpu0: entity work.cpu port map(
      addr_v => cpu_addr,
      datain => cpu_datain,
      dataout => cpu_dataout,
      wr => cpu_wr,
      rd => cpu_rd,
      dw8 => cpu_dw8,
      cp => cpu_cp,
      ifetch => ifetchcopy,
      iwait => iwait,
      id => cpu_id,
      init => cpu_init,
      br7 => '0',
      int_vector7 => o"000",
      br6 => '0',
      int_vector6 => o"000",
      br5 => cpu_br5,
      bg5 => cpu_bg5,
      int_vector5 => cpu_int_vector5,
      br4 => cpu_br4,
      bg4 => cpu_bg4,
      int_vector4 => cpu_int_vector4,
      mmutrap => mmu_trap,
      ack_mmutrap => cpu_ack_mmutrap,
      mmuabort => mmu_abort,
      ack_mmuabort => cpu_ack_mmuabort,
      npr => cpu_npr,
      npg => cpu_npg,
      nxmabort => nxmabort,
      oddabort => oddabort,
      illhalt => illhalt,
      ysv => ysv,
      rsv => rsv,
      cpu_stack_limit => cpu_stack_limit,
      cpu_kmillhalt => cpu_kmillhalt,
      sr0_ic => cpu_sr0_ic,
      sr1 => cpu_sr1,
      sr2 => cpu_sr2,
      dstfreference => cpu_dstfreference,
      sr3csmenable => cpu_sr3csmenable,
      psw_in => cpu_psw_in,
      psw_out => cpu_psw,
      psw_in_we_even => cpu_psw_we_even,
      psw_in_we_odd => cpu_psw_we_odd,
      pir_in => cpu_pir_in,
      modelcode => modelcode,
      init_r7 => init_r7,
      init_psw => init_psw,
      clk => cpuclk,
      reset => reset
   );

   mmu0: entity work.mmu port map(
      cpu_addr_v => cpu_addr,
      cpu_datain => cpu_datain,
      cpu_dataout => cpu_dataout,
      cpu_rd => cpu_rd,
      cpu_wr => cpu_wr,
      cpu_dw8 => cpu_dw8,
      cpu_cp => cpu_cp,
      sr0_ic => cpu_sr0_ic,
      sr1_in => cpu_sr1,
      sr2_in => cpu_sr2,
      dstfreference => cpu_dstfreference,
      sr3csmenable => cpu_sr3csmenable,
      ifetch => ifetchcopy,
      mmutrap => mmu_trap,
      ack_mmutrap => cpu_ack_mmutrap,
      mmuabort => mmu_abort,
      ack_mmuabort => cpu_ack_mmuabort,

      mmuoddabort => mmu_oddabort,

      bus_unibus_mapped => bus_unibus_mapped,

      bus_addr => bus_addr,
      bus_dati => bus_dati,
      bus_dato => bus_dato,
      bus_control_dati => bus_control_dati,
      bus_control_dato => bus_control_dato,
      bus_control_datob => bus_control_datob,

      unibus_addr => unibus_addr,
      unibus_dati => unibus_dati,
      unibus_dato => unibus_dato,
      unibus_control_dati => unibus_control_dati,
      unibus_control_dato => unibus_control_dato,
      unibus_control_datob => unibus_control_datob,

      unibus_busmaster_addr => unibus_busmaster_addr,
      unibus_busmaster_dati => unibus_busmaster_dati,
      unibus_busmaster_dato => unibus_busmaster_dato,
      unibus_busmaster_control_dati => unibus_busmaster_control_dati,
      unibus_busmaster_control_dato => unibus_busmaster_control_dato,
      unibus_busmaster_control_datob => unibus_busmaster_control_datob,
      unibus_busmaster_control_npg => unibus_busmaster_control_npg,

      modelcode => modelcode,

      psw => cpu_psw,
      id => cpu_id,
      reset => cpu_init,
      lookup_clk => clk50mhz,
      clk => nclk
   );

   cr0: entity work.cr11 port map(
      bus_addr_match => cr_addr_match,
      bus_addr => unibus_addr,
      bus_dati => cr_dati,
      bus_dato => unibus_dato,
      bus_control_dati => unibus_control_dati,
      bus_control_dato => unibus_control_dato,
      bus_control_datob => unibus_control_datob,

      psw_in => cpu_psw_in,
      psw_in_we_even => cpu_psw_we_even,
      psw_in_we_odd => cpu_psw_we_odd,
      psw_out => cpu_psw,

      cpu_stack_limit => cpu_stack_limit,

      pir_in => cpu_pir_in,

      cpu_illegal_halt => illhalt,
      cpu_address_error => oddabort,
      cpu_nxm => cer_nxmabort,
      cpu_iobus_timeout => cer_ioabort,
      cpu_ysv => ysv,
      cpu_rsv => rsv,

      cpu_kmillhalt => cpu_kmillhalt,

      modelcode => modelcode,

      reset => cpu_init,
      clk => nclk
   );

  kl0: entity work.kl11 port map(
      base_addr => o"777560",
      ivec => o"060",
      ovec => o"064",

      br => cpu_br4,
      bg => cpu_bg4,
      int_vector => cpu_int_vector4,

      bus_addr_match => kl0_addr_match,
      bus_addr => unibus_addr,
      bus_dati => kl0_dati,
      bus_dato => unibus_dato,
      bus_control_dati => unibus_control_dati,
      bus_control_dato => unibus_control_dato,
      bus_control_datob => unibus_control_datob,

      tx => tx,
      rx => rx,
      cts => '0',
      have_kl11 => 1,
      have_kl11_bps => bps,
      have_kl11_force7bit => force7bit,
      have_kl11_rtscts => rtscts,
      clk50mhz => clk50mhz,
      reset => cpu_init,
      clk => nclk
   );

   vtbr0: entity work.vtbr port map(
      base_addr => o"000000",

      bus_addr_match => ram_addr_match,
      bus_addr => bus_addr(17 downto 0),
      bus_dati => ram_dati,
      bus_dato => bus_dato,
      bus_control_dati => bus_control_dati,
      bus_control_dato => bus_control_dato,
      bus_control_datob => bus_control_datob,

      reset => reset,
      clk => nclk
   );

   vga0: entity work.vga port map(
      base_addr => o"100000",

      bus_addr_match => vga_addr_match,
      bus_addr => bus_addr(17 downto 0),
      bus_dati => vga_dati,
      bus_dato => bus_dato,
      bus_control_dati => bus_control_dati,
      bus_control_dato => bus_control_dato,
      bus_control_datob => bus_control_datob,

      vga_cursor => vga_cursor,
      vga_shade0 => vga_shade0,
      vga_shade1 => vga_shade1,
      vga_xp => vga_xp,
      vga_graphics => vga_graphics,
      vga_graph0 => vga_graph0,
      vga_graph1 => vga_graph1,
      vga_hist0 => vga_hist0,
      vga_hist1 => vga_hist1,
      vga_hlines => vga_hlines,
      vga_vlines => vga_vlines,
      vga_vcur => vga_vcur,
      vga_marker0 => vga_marker0,
      vga_marker1 => vga_marker1,
      vga_graph0s => vga_graph0s,
      vga_graph1s => vga_graph1s,
      vga_strip0 => vga_strip0,
      vga_strip1 => vga_strip1,
      vga_square => vga_square,
      vga_doublewidth => vga_doublewidth,
      vga_doubleheight => vga_doubleheight,
      vga_doubleheight_low => vga_doubleheight_low,

      vga_acth => vga_acth,
      vga_actl => vga_actl,

      vga_hsync => vga_hsync,
      vga_vsync => vga_vsync,
		vga_hblank => vga_hblank,
		vga_vblank => vga_vblank,
		ce_pix     => ce_pix,
      vga_fb => vga_fb,
      vga_ht => vga_ht,

      teste => teste,
      testf => testf,

      vga_cursor_block => vga_cursor_block,
      vga_cursor_blink => vga_cursor_blink,

      vttype => vttype,
      have_act_seconds => have_act_seconds,
      have_act => have_act,

      reset => reset,
      clk50mhz => clk50mhz,
      clk => nclk
   );

   vgacr0: entity work.vgacr port map(
      base_addr => o"140000",

      bus_addr_match => vgacr_addr_match,
      bus_addr => bus_addr(17 downto 0),
      bus_dati => vgacr_dati,
      bus_dato => bus_dato,
      bus_control_dati => bus_control_dati,
      bus_control_dato => bus_control_dato,
      bus_control_datob => bus_control_datob,

      vga_cursor => vga_cursor,
      vga_shade0 => vga_shade0,
      vga_shade1 => vga_shade1,
      vga_xp => vga_xp,
      vga_debug => vga_debug,
      vga_graphics => vga_graphics,
      vga_graph0 => vga_graph0,
      vga_graph1 => vga_graph1,
      vga_hist0 => vga_hist0,
      vga_hist1 => vga_hist1,
      vga_hlines => vga_hlines,
      vga_vlines => vga_vlines,
      vga_vcur => vga_vcur,
      vga_marker0 => vga_marker0,
      vga_marker1 => vga_marker1,
      vga_graph0s => vga_graph0s,
      vga_graph1s => vga_graph1s,
      vga_strip0 => vga_strip0,
      vga_strip1 => vga_strip1,
      vga_square => vga_square,
      vga_doublewidth => vga_doublewidth,
      vga_doubleheight => vga_doubleheight,
      vga_doubleheight_low => vga_doubleheight_low,

      vga_acth => vga_acth,
      vga_actl => vga_actl,

      vttype => vttype,

      reset => reset,
      clk => nclk
   );

   vga_bl(0) <= vga_graphics;
   vga_bl(1) <= vga_square;
   vga_bl(2) <= vga_graph0;
   vga_bl(3) <= vga_graph1;
   vga_bl(4) <= vga_marker0;
   vga_bl(5) <= vga_marker1;
   vga_bl(6) <= vga_graph0s;
   vga_bl(7) <= vga_graph1s;
   vga_bl(8) <= vga_hist0;
   vga_bl(9) <= vga_hist1;

   ps20: entity work.ps2 port map(
      base_addr => o"150000",
      ivec => o"070",

      br => cpu_br5,
      bg => cpu_bg5,
      int_vector => cpu_int_vector5,

      bus_addr_match => ps2_addr_match,
      bus_addr => bus_addr(17 downto 0),
      bus_dati => ps2_dati,
      bus_dato => bus_dato,
      bus_control_dati => bus_control_dati,
      bus_control_dato => bus_control_dato,
      bus_control_datob => bus_control_datob,

      usb_kbd        => usb_kbd,
      kbd_strobe     => kbd_strobe,

      reset => reset,
      clk => nclk
   );

   nclk <= not cpuclk;
   ifetch <= ifetchcopy;

   bus_addr_match <=
      '1' when ram_addr_match = '1'
      or vga_addr_match = '1'
      or vgacr_addr_match = '1'
      or ps2_addr_match = '1'
      else '0';

   bus_dati <=
      ram_dati when ram_addr_match = '1'
      else vga_dati when vga_addr_match = '1'
      else vgacr_dati when vgacr_addr_match = '1'
      else ps2_dati when ps2_addr_match = '1'
      else "0000000000000000";

   unibus_dati <=
      cr_dati when cr_addr_match = '1'
      else kl0_dati when kl0_addr_match = '1'
      else "0000000000000000";

   unibus_addr_match <= '1'
      when cr_addr_match = '1'
      or kl0_addr_match = '1'
      else '0';

   cer_nxmabort <= '1'
      when ram_addr_match = '0'
      and vga_addr_match = '0'
      and vgacr_addr_match = '0'
      and ps2_addr_match = '0'
      and (bus_control_dati = '1' or bus_control_dato = '1')
      and bus_unibus_mapped = '0'
      and cpu_npg = '0'
      else '0';

   cer_ioabort <= '1'
      when unibus_addr_match = '0' and (unibus_control_dati = '1' or unibus_control_dato = '1') and unibus_addr(17 downto 13) = "11111" and cpu_npg = '0'
      else '1' when ram_addr_match = '0' and bus_unibus_mapped = '1' and (bus_control_dati = '1' or bus_control_dato = '1') and cpu_npg = '0'
      else '0';

   nxmabort <= '1' when cer_nxmabort = '1' or cer_ioabort = '1' else '0';

   oddabort <=
      '1' when bus_control_dato = '1' and bus_control_datob = '0' and bus_addr(0) = '1'
      else '1' when ifetchcopy = '1' and unibus_control_dati = '1' and unibus_addr(17 downto 13) = "11111" and ram_addr_match /= '1'  -- FIXME???
      else '1' when mmu_oddabort = '1'
      else '0';

   busmaster_nxmabort <= '0';
   unibus_busmaster_addr <= "000000000000000000";
   unibus_busmaster_dato <= "0000000000000000";
   unibus_busmaster_control_dati <= '0';
   unibus_busmaster_control_dato <= '0';
   unibus_busmaster_control_datob <= '0';
   unibus_busmaster_control_npg <= '0';

   cpu_npr <= '0';

end implementation;
