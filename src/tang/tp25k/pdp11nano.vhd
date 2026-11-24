library ieee;
use ieee.std_logic_1164.all;
use  IEEE.STD_LOGIC_ARITH.all;
use  IEEE.STD_LOGIC_UNSIGNED.all;
use work.sd_bus_pkg.all;

entity pdp11nano is
port(
    bl616_jtagsel   : in std_logic;
    jtagseln        : out std_logic;

    clk_in          : in std_logic;

    reset           : in std_logic; -- S2 button
    user            : in std_logic; -- S1 button

    leds_n          : out std_logic_vector(1 downto 0);

    -- UART pins via USB_A connector
    uart_rx         : in std_logic;
    uart_tx         : out std_logic;

    tmds_clk_p      : out std_logic;
    tmds_clk_n      : out std_logic;
    tmds_d_p        : out std_logic_vector(2 downto 0);
    tmds_d_n        : out std_logic_vector(2 downto 0);

    spi_sclk        : in std_logic;
    spi_csn         : in std_logic;
    spi_dir         : out std_logic;
    spi_dat         : in std_logic;
    spi_irqn        : out std_logic;

    -- SPI interface external uC
    pmod_companion_din : in std_logic;
    pmod_companion_dout : out std_logic;
    pmod_companion_ss : in std_logic;
    pmod_companion_clk : in std_logic;
    pmod_companion_intn : out std_logic;

    sd_clk          : out std_logic;
    sd_cmd          : inout std_logic;
    sd_dat          : inout std_logic_vector(3 downto 0);

    O_sdram_clk     : out std_logic;
    O_sdram_cs_n    : out std_logic; -- chip select
    O_sdram_cas_n   : out std_logic;
    O_sdram_ras_n   : out std_logic; -- row address select
    O_sdram_wen_n   : out std_logic; -- write enable
    IO_sdram_dq     : inout std_logic_vector(15 downto 0); -- 16 bit bidirectional data bus
    O_sdram_addr    : out std_logic_vector(12 downto 0); -- 13 bit multiplexed address bus
    O_sdram_ba      : out std_logic_vector(1 downto 0); -- two banks
    O_sdram_dqm     : out std_logic_vector(1 downto 0) -- 16/2
    );
end pdp11nano;

architecture struct of pdp11nano is
signal ws2812       : std_logic;

signal hSync          : std_logic;
signal vSync          : std_logic;
signal vblank         : std_logic;
signal hblank         : std_logic;
signal clk_pixel_x10  : std_logic;
signal clk_pixel_x5   : std_logic;
signal clk_pixel_x4   : std_logic;
signal clk_pixel_x2   : std_logic;
signal clk_pixel      : std_logic;
signal pll_lock       : std_logic;
signal spi_io_din     : std_logic;
signal spi_io_ss      : std_logic;
signal spi_io_clk     : std_logic;
attribute syn_keep    : integer;
attribute syn_keep of spi_io_clk : signal is 1;
signal spi_io_dout    : std_logic;
signal int_out_n      : std_logic;
signal mcu_data_out   : std_logic_vector(7 downto 0);
signal hid_data_out   : std_logic_vector(7 downto 0);
signal osd_data_out   : std_logic_vector(7 downto 0) :=  X"55";
signal sys_data_out   : std_logic_vector(7 downto 0);
signal sdc_data_out   : std_logic_vector(7 downto 0);
signal hid_int        : std_logic;
signal usb_kbd        : std_logic_vector(7 downto 0);
signal int_ack        : std_logic_vector(7 downto 0) := X"00";
signal mcu_sys_strobe : std_logic;
signal mcu_hid_strobe : std_logic;
signal mcu_osd_strobe : std_logic;
signal mcu_start      : std_logic;
signal kbd_strobe     : std_logic;
signal ws2812_color   : std_logic_vector(23 downto 0);
signal sdc_int        : std_logic :='0';
signal sdc_iack       : std_logic;
signal mcu_sdc_strobe : std_logic;
signal system_reset   : std_logic_vector(1 downto 0);
signal sd_lba         : std_logic_vector(31 downto 0);
signal sd_done        : std_logic;
signal sd_rd_byte_strobe : std_logic;
signal sd_byte_index  : std_logic_vector(8 downto 0);
signal sd_rd_data     : std_logic_vector(7 downto 0);
signal sd_wr_data     : std_logic_vector(7 downto 0);
signal sd_img_size    : std_logic_vector(31 downto 0);
signal sd_img_mounted : std_logic_vector(7 downto 0);
signal sd_rd          : std_logic_vector(7 downto 0);
signal sd_wr          : std_logic_vector(7 downto 0);
signal sd_rsrc        : std_logic_vector(2 downto 0);
signal sd_core_busy   : std_logic;
signal sd_card_ready  : std_logic;
signal sd_wr_err      : std_logic;
-- slot 0: RK11, slot 1: RL11, slot 2: RH11, slot 3: TC11
type sd_req_array_t is array (0 to 3) of sd_req_t;
type sd_rsp_array_t is array (0 to 3) of sd_rsp_t;
signal disk_req : sd_req_array_t;
signal disk_rsp : sd_rsp_array_t;
signal rk_sddebug : std_logic_vector(3 downto 0);
signal rl_sddebug : std_logic_vector(3 downto 0);
signal rh_sddebug : std_logic_vector(3 downto 0);
signal tc_sddebug : std_logic_vector(3 downto 0);
signal leds           : std_logic_vector(5 downto 0);
signal sys_reset       : std_logic := '0';
signal cpu_reset : std_logic;
signal cpu_reset_async : std_logic;
signal cpu_reset_s1 : std_logic := '1';
signal cpu_reset_s2 : std_logic := '1';
constant powerup_reset_cycles : positive := 2 * 25200000;
signal powerup_reset_count : natural range 0 to powerup_reset_cycles := 0;
signal powerup_reset : std_logic := '1';
signal spi_ext          : std_logic := '0';
signal vsd_sel_rk : std_logic := '0';
signal vsd_sel_rl : std_logic := '0';
signal vsd_sel_rh : std_logic := '0';
signal vsd_sel_tc : std_logic := '0';
signal have_rk    : integer := 0;
signal have_rl    : integer := 0;
signal have_rh    : integer := 0;
signal have_tc    : integer := 0;
signal modelcode  : integer;
signal system_cpu : std_logic_vector(2 downto 0);
signal img_present : std_logic_vector(7 downto 0) := (others => '0');
signal boot_button_detected : std_logic := '1';
signal btn_captured : std_logic := '0';
signal vga_fb     : std_logic;
signal vga_ht     : std_logic;
signal vga_red    : std_logic_vector(7 downto 0);
signal vga_green  : std_logic_vector(7 downto 0);
signal vga_blue   : std_logic_vector(7 downto 0);
signal have_act   : std_logic_vector(1 downto 0);
signal color      : std_logic_vector(1 downto 0);
signal system_terminal_type : std_logic;
signal system_cursor_type : std_logic;
signal system_cursor_blink : std_logic;
signal vttype     : integer;
signal rh_type    : integer range 1 to 7;
signal system_rh_type : std_logic_vector(2 downto 0);
signal system_console : std_logic;

component CLKDIV
    generic (
        DIV_MODE : STRING := "2"
    );
    port (
        CLKOUT: out std_logic;
        HCLKIN: in std_logic;
        RESETN: in std_logic;
        CALIB: in std_logic
    );
end component;

COMPONENT GSR 
    PORT (
         GSRI : in std_logic
    );
end COMPONENT;

begin

GSR_inst: GSR
    port map (
        GSRI => '1'
    );

  process (clk_in)
  begin
    if rising_edge(clk_in) then
      if btn_captured = '0' and pll_lock = '1' then
        boot_button_detected <= user or reset;
        btn_captured <= '1';
      end if;
    end if;
  end process;

-- enable JTAG if any button has been pressed during boot and also once
-- the external FPGA Companion has been seen
  jtagseln <= not (not pll_lock or boot_button_detected or spi_ext or bl616_jtagsel);

  process (clk_in)
  begin
    if rising_edge(clk_in) then
      if pll_lock = '0' then
        spi_ext <= '0';
      elsif pmod_companion_ss = '0' then
        spi_ext <= '1';
      end if;
    end if;
  end process;

  spi_io_din <= pmod_companion_din when spi_ext = '1' else spi_dat;
  spi_io_ss <= pmod_companion_ss when spi_ext = '1' else spi_csn;
  spi_io_clk <= pmod_companion_clk when spi_ext = '1' else spi_sclk;
  spi_dir <= spi_io_dout;
  spi_irqn <= int_out_n;
  pmod_companion_dout <= spi_io_dout;
  pmod_companion_intn <= int_out_n;

  leds_n(1 downto 0) <= not leds(1 downto 0);
  leds(3 downto 0) <= rk_sddebug;
  leds(5 downto 4) <= "00";

-- 252Mhz and 126Mhz
pll_inst: entity work.Gowin_PLL_126mhz
    port map (
        clkout0 => clk_pixel_x10, -- 252.0 Mhz
        clkout1 => clk_pixel_x5,  -- 126.0 Mhz
        clkout2 => clk_pixel_x4,  -- 100.8 Mhz
        clkout3 => clk_pixel_x2,  --  50.4 Mhz
        clkout4 => clk_pixel,     --  25.2 Mhz
        lock    => pll_lock,
        clkin   => clk_in,
        mdclk   => clk_in
    );

mcu_spi_inst: entity work.mcu_spi 
port map (
  clk            => clk_pixel,
  reset          => not pll_lock,
  -- SPI interface to BL616 MCU
  spi_io_ss      => spi_io_ss,      -- SPI CSn
  spi_io_clk     => spi_io_clk,     -- SPI SCLK
  spi_io_din     => spi_io_din,     -- SPI MOSI
  spi_io_dout    => spi_io_dout,    -- SPI MISO
  -- byte interface to the various core components
  mcu_sys_strobe => mcu_sys_strobe, -- byte strobe for system control target
  mcu_hid_strobe => mcu_hid_strobe, -- byte strobe for HID target  
  mcu_osd_strobe => mcu_osd_strobe, -- byte strobe for OSD target
  mcu_sdc_strobe => mcu_sdc_strobe, -- byte strobe for SD card target
  mcu_start      => mcu_start,
  mcu_sys_din    => sys_data_out,
  mcu_hid_din    => hid_data_out,
  mcu_osd_din    => osd_data_out,
  mcu_sdc_din    => sdc_data_out,
  mcu_dout       => mcu_data_out
);

-- decode SPI/MCU data received for human input devices (HID) 
hid_inst: entity work.hid
 port map 
 (
  clk             => clk_pixel,
  reset           => not pll_lock,
  -- interface to receive user data from MCU (mouse, kbd, ...)
  data_in_strobe  => mcu_hid_strobe,
  data_in_start   => mcu_start,
  data_in         => mcu_data_out,
  data_out        => hid_data_out,

  -- output HID data received from USB
  usb_kbd         => usb_kbd,
  kbd_strobe      => kbd_strobe
  );

module_inst: entity work.sysctrl 
 port map 
 (
  clk                 => clk_pixel,
  reset               => not pll_lock,
--
  data_in_strobe      => mcu_sys_strobe,
  data_in_start       => mcu_start,
  data_in             => mcu_data_out,
  data_out            => sys_data_out,
  -- values that can be configured by the user
  system_reset        => system_reset,
  system_cpu          => system_cpu,
  system_terminal_type => system_terminal_type,
  system_cursor_type   => system_cursor_type,
  system_cursor_blink  => system_cursor_blink,
  system_color         => color,
  system_rh_type       => system_rh_type,
  system_console       => system_console,

  -- port io (used to expose rs232)
  port_status         => (others=>'0'),
  port_out_available  => (others=>'0'),
  port_out_strobe     => open,
  port_out_data       => (others=>'0'),
  port_in_available   => (others=>'0'),
  port_in_strobe      => open,
  port_in_data        => open,

  int_out_n           => int_out_n,
  int_in              => unsigned'(x"0" & sdc_int & '0' & '0' & '0'),
  int_ack             => int_ack,

  buttons             => unsigned'(user & reset),
  leds                => open,
  color               => open
);

video_inst: entity work.video 
port map(
      pll_lock   => pll_lock,
      clk        => clk_pixel,
      clk_pixel_x5 => clk_pixel_x5,
      audio_div  => (others=>'0'),
      ntscmode  => '1',
      vb_in     => vblank,
      hb_in     => hblank,
      hs_in_n   => hSync,
      vs_in_n   => vSync,

      r_in      => vga_red(7 downto 4),
      g_in      => vga_green(7 downto 4),
      b_in      => vga_blue(7 downto 4),

      audio_l => (others=>'0'),
      audio_r => (others=>'0'),
      osd_status => open,

      mcu_start => mcu_start,
      mcu_osd_strobe => mcu_osd_strobe,
      mcu_data  => mcu_data_out,

      -- values that can be configure by the user via osd
      system_wide_screen => '0',
      system_scanlines => "00",
      system_volume => "00",

      tmds_clk_n => tmds_clk_n,
      tmds_clk_p => tmds_clk_p,
      tmds_d_n   => tmds_d_n,
      tmds_d_p   => tmds_d_p
      );


sdc_iack <= int_ack(3);

sd_card_inst: entity work.sd_card
   generic map (
    CLK_DIV  => 0,
    SIMULATE => 0
   )
    port map (
    rstn            => pll_lock,
    clk             => clk_pixel,
  
    -- SD card signals
    sdclk           => sd_clk,
    sdcmd           => sd_cmd,
    sddat           => sd_dat,

    -- mcu interface
    data_strobe     => mcu_sdc_strobe,
    data_start      => mcu_start,
    data_in         => mcu_data_out,
    data_out        => sdc_data_out,

    -- interrupt to signal communication request
    irq             => sdc_int,
    iack            => sdc_iack,

    -- output file/image information. Image size is e.g. used by fdc to 
    -- translate between sector/track/side and lba sector
    image_size(31 downto 0)      => sd_img_size, -- length of image file
    image_mounted   => sd_img_mounted,

    -- user read sector command interface (sync with clk)
    rstart          => sd_rd,
    wstart          => sd_wr, 
    rsector         => sd_lba,
    rsrc            => sd_rsrc, -- slot (0..3) of the request currently being processed

    core_busy       => sd_core_busy,
    card_ready      => sd_card_ready,
    rwr_err         => sd_wr_err,

    rbusy           => open,
    rdone           => sd_done,           --  done from sd reader acknowledges/clears start

    -- sector data output interface (sync with clk)
    inbyte          => sd_wr_data,        -- sector data output interface (sync with clk)
    outen           => sd_rd_byte_strobe, -- when outen=1, a byte of sector content is read out from outbyte
    outaddr         => sd_byte_index,     -- outaddr from 0 to 511, because the sector size is 512
    outbyte         => sd_rd_data         -- a byte of sector content
);

process(all)
    variable slot_hit : std_logic;
begin
    sd_rd <= (others => '0');
    sd_wr <= (others => '0');
    sd_lba <= (others => '0');
    for i in 0 to 3 loop
        sd_rd(i) <= disk_req(i).rstart;
        sd_wr(i) <= disk_req(i).wstart;
    end loop;
    for i in 3 downto 0 loop
        if disk_req(i).rstart = '1' or disk_req(i).wstart = '1' then
            sd_lba <= disk_req(i).sector;
        end if;
    end loop;

    sd_wr_data <= disk_req(conv_integer(sd_rsrc(1 downto 0))).wbyte;

    for i in 0 to 3 loop
        slot_hit := '1' when sd_rsrc = conv_std_logic_vector(i, 3) else '0';
        disk_rsp(i).grant   <= sd_core_busy and slot_hit;
        disk_rsp(i).done    <= sd_done and slot_hit;
        disk_rsp(i).wr_err  <= sd_wr_err and slot_hit;
        disk_rsp(i).outen   <= sd_rd_byte_strobe and slot_hit;
        disk_rsp(i).outaddr <= sd_byte_index;
        disk_rsp(i).outbyte <= sd_rd_data;
        disk_rsp(i).ready   <= sd_card_ready;
    end loop;
end process;

powerup_reset_delay : process(clk_pixel, pll_lock)
begin
    if pll_lock = '0' then
        powerup_reset_count <= 0;
        powerup_reset <= '1';
    elsif rising_edge(clk_pixel) then
        if powerup_reset_count < powerup_reset_cycles then
            powerup_reset_count <= powerup_reset_count + 1;
            if powerup_reset_count = powerup_reset_cycles - 1 then
                powerup_reset <= '0';
            end if;
        end if;
    end if;
end process;

sys_reset <= system_reset(1) or system_reset(0) or not pll_lock;

-- 25.2 Mhz system clock synchronous reset for the CPU
cpu_reset_sync : process (clk_pixel, pll_lock)
begin
    if pll_lock = '0' then
        cpu_reset_s1 <= '1';
        cpu_reset_s2 <= '1';
    elsif rising_edge(clk_pixel) then
        cpu_reset_s1 <= sys_reset or powerup_reset;
        cpu_reset_s2 <= cpu_reset_s1;
    end if;
end process;

process (clk_pixel)
begin
    if rising_edge(clk_pixel) then
        for i in 0 to 7 loop
            if sd_img_mounted(i) = '1' then
                if sd_img_size /= (sd_img_size'range => '0') then
                    img_present(i) <= '1';
                else
                    img_present(i) <= '0';
                end if;
            end if;
        end loop;
    end if;
end process;

process(clk_pixel)
begin
   if rising_edge(clk_pixel) then
      if pll_lock = '0' then
         vsd_sel_rk <= '0';
         vsd_sel_rl <= '0';
         vsd_sel_rh <= '0';
         vsd_sel_tc <= '0';
      else
         vsd_sel_rk <= img_present(0);
         vsd_sel_rl <= img_present(1);
         vsd_sel_rh <= img_present(2);
         vsd_sel_tc <= img_present(3);
      end if;
   end if;
end process;

have_rk <= 1 when vsd_sel_rk = '1' else 0;
have_rl <= 1 when vsd_sel_rl = '1' else 0;
have_rh <= 1 when vsd_sel_rh = '1' else 0; 
have_tc <= 1 when vsd_sel_tc = '1' else 0; 

modelcode <= 20 when system_cpu = "000" else
             34 when system_cpu = "001" else
             44 when system_cpu = "010" else
             45 when system_cpu = "011" else
             70 when system_cpu = "100" else
             94;

rh_type <= 1 when system_rh_type = "001" else
           2 when system_rh_type = "010" else
           3 when system_rh_type = "011" else
           4 when system_rh_type = "100" else
           5 when system_rh_type = "101" else
           6 when system_rh_type = "110" else
           7 when system_rh_type = "111" else
           6; -- "000" is not a valid type; fall back to RP06

pdp11_inst: entity work.top
  generic map (
    ttype => true,
    sdram_data_width => 16
  )
  port map (
    clk_50         => clk_pixel_x2,-- 50.4 MHz
    clk_100        => clk_pixel_x4,-- 100.8 Mhz
    clk_25         => clk_pixel,   -- 25.2 Mhz
    reset          => cpu_reset_s2,
    vtreset        => not pll_lock,
    modelcode      => modelcode,
    serial_console => system_console,
    have_rk        => have_rk,
    have_rl        => have_rl,
    have_rh        => have_rh,
    have_tc        => have_tc,
    have_xu        => 0,
    rx1            => uart_rx,
    tx1            => uart_tx,
    rts1           => open,
    cts1           => '1',
      -- pidp11 console
    panel_xled       => open,
    panel_col        => open,
    panel_row        => open,

    rk_sdcard_req   => disk_req(0),
    rk_sdcard_rsp   => disk_rsp(0),
    rk_sdcard_debug => rk_sddebug,

    rl_sdcard_req   => disk_req(1),
    rl_sdcard_rsp   => disk_rsp(1),
    rl_sdcard_debug => rl_sddebug,

    rh_sdcard_req   => disk_req(2),
    rh_sdcard_rsp   => disk_rsp(2),
    rh_sdcard_debug => rh_sddebug,
    rh_type         => rh_type,

    tc_sdcard_req   => disk_req(3),
    tc_sdcard_rsp   => disk_rsp(3),
    tc_sdcard_debug => tc_sddebug,

    xu_cs          => open,
    xu_mosi        => open,
    xu_sclk        => open,
    xu_miso        => '1',

    dram_addr      => O_sdram_addr,
    dram_dq        => IO_sdram_dq,
    dram_dqm       => O_sdram_dqm,
    O_sdram_ba     => O_sdram_ba,
    dram_ras_n     => O_sdram_ras_n,
    dram_cas_n     => O_sdram_cas_n,
    dram_cke       => open,
    dram_clk       => O_sdram_clk,
    dram_we_n      => O_sdram_wen_n,
    dram_cs_n      => O_sdram_cs_n,
    greenled       => open,

    usb_kbd        => usb_kbd,
    kbd_strobe     => kbd_strobe,

    vttype         => vttype,
    vga_hsync      => hSync,
    vga_vsync      => vSync,
    vga_hblank     => hblank,
    vga_vblank     => vblank,
    vga_fb         => vga_fb,
    vga_ht         => vga_ht,
    vga_cursor_block=> system_cursor_type,
    vga_cursor_blink=> system_cursor_blink,
    teste          => '0',
    testf          => '0',
    have_act       =>  0
  );

vttype <= 105 when system_terminal_type = '1' else 100;

process(clk_pixel)
begin
   if rising_edge(clk_pixel) then
      case color is
         when "00" =>
            vga_red   <= x"00";
            vga_green <= x"FF" when vga_fb = '1' else x"7F" when vga_ht = '1' else x"00";
            vga_blue  <= x"00";
         when "01" =>
            vga_red   <= x"00";
            vga_green <= x"FF" when vga_fb = '1' else x"7F" when vga_ht = '1' else x"00";
            vga_blue  <= x"FF" when vga_fb = '1' else x"7F" when vga_ht = '1' else x"00";
         when "10" =>
            vga_red   <= x"FF" when vga_fb = '1' else x"7F" when vga_ht = '1' else x"00";
            vga_green <= x"FF" when vga_fb = '1' else x"7F" when vga_ht = '1' else x"00";
            vga_blue  <= x"FF" when vga_fb = '1' else x"7F" when vga_ht = '1' else x"00";
         when "11" =>
            vga_red   <= x"FF" when vga_fb = '1' else x"7F" when vga_ht = '1' else x"00";
            vga_green <= x"BF" when vga_fb = '1' else x"5F" when vga_ht = '1' else x"00";
            vga_blue  <= x"00";
         when others =>
            null;
      end case;
   end if;
end process;

end;
