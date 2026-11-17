library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity tc11 is
   port(
      base_addr : in std_logic_vector(17 downto 0);

      br : out std_logic;
      bg : in std_logic;
      ivec : in std_logic_vector(8 downto 0);
      int_vector : out std_logic_vector(8 downto 0);

      npr : out std_logic;
      npg : in std_logic;

      bus_addr_match : out std_logic;
      bus_addr : in std_logic_vector(17 downto 0);
      bus_dati : out std_logic_vector(15 downto 0);
      bus_dato : in std_logic_vector(15 downto 0);
      bus_control_dati : in std_logic;
      bus_control_dato : in std_logic;
      bus_control_datob : in std_logic;

      bus_master_addr : out std_logic_vector(17 downto 0);
      bus_master_dati : in std_logic_vector(15 downto 0);
      bus_master_dato : out std_logic_vector(15 downto 0);
      bus_master_control_dati : out std_logic;
      bus_master_control_dato : out std_logic;
      bus_master_nxm : in std_logic;

      sdcard_cs : out std_logic;
      sdcard_mosi : out std_logic;
      sdcard_sclk : out std_logic;
      sdcard_miso : in std_logic;
      sdcard_debug : out std_logic_vector(3 downto 0);

      have_tc : in integer range 0 to 1;
      reset : in std_logic;
      clk50mhz : in std_logic;
      nclk : in std_logic;
      clk : in std_logic
   );
end tc11;

architecture implementation of tc11 is

component sdspi is
   port(
      sdcard_cs : out std_logic;
      sdcard_mosi : out std_logic;
      sdcard_sclk : out std_logic;
      sdcard_miso : in std_logic := '0';
      sdcard_debug : out std_logic_vector(3 downto 0);
      sdcard_addr : in std_logic_vector(23 downto 0);
      sdcard_idle : out std_logic;
      sdcard_read_start : in std_logic;
      sdcard_read_ack : in std_logic;
      sdcard_read_done : out std_logic;
      sdcard_write_start : in std_logic;
      sdcard_write_ack : in std_logic;
      sdcard_write_done : out std_logic;
      sdcard_error : out std_logic;
      sdcard_xfer_addr : in integer range 0 to 255;
      sdcard_xfer_read : in std_logic;
      sdcard_xfer_out : out std_logic_vector(15 downto 0);
      sdcard_xfer_write : in std_logic;
      sdcard_xfer_in : in std_logic_vector(15 downto 0);
      enable : in integer range 0 to 1 := 0;
      controller_clk : in std_logic;
      reset : in std_logic;
      clk50mhz : in std_logic
   );
end component;

signal base_addr_match : std_logic;
signal command_reg : std_logic_vector(15 downto 0) := (others => '0');
signal word_count_reg : std_logic_vector(15 downto 0) := (others => '0');
signal bus_address_reg : std_logic_vector(15 downto 0) := (others => '0');
signal interrupt_enable : std_logic := '0';
signal read_command : std_logic := '0';
signal reverse_command : std_logic := '0';
signal command_ready : std_logic := '0';
signal command_error : std_logic := '0';
signal controller_ready : std_logic := '1';
signal controller_error : std_logic := '0';
signal interrupt_pending : std_logic := '0';

signal sdcard_addr : std_logic_vector(23 downto 0) := (others => '0');
signal sdcard_idle : std_logic;
signal sdcard_read_start : std_logic := '0';
signal sdcard_read_ack : std_logic := '0';
signal sdcard_read_done : std_logic;
signal sdcard_error : std_logic;
signal sdcard_xfer_addr : integer range 0 to 255 := 0;
signal sdcard_xfer_read : std_logic := '0';
signal sdcard_xfer_out : std_logic_vector(15 downto 0);

signal dma_word_count : std_logic_vector(15 downto 0) := (others => '0');
signal dma_address : std_logic_vector(17 downto 0) := (others => '0');
signal sector_word_count : integer range 0 to 255 := 0;

type tape_state_t is (
   tape_idle,
   tape_request_sector,
   tape_wait_sector,
   tape_wait_grant,
   tape_read_first,
   tape_read_words,
   tape_ack_sector
);
signal tape_state : tape_state_t := tape_idle;

begin

   base_addr_match <= '1' when base_addr(17 downto 3) = bus_addr(17 downto 3) and have_tc = 1 else '0';
   bus_addr_match <= base_addr_match;

   int_vector <= ivec;
   br <= interrupt_pending and interrupt_enable;

   sd1: sdspi port map(
      sdcard_cs => sdcard_cs,
      sdcard_mosi => sdcard_mosi,
      sdcard_sclk => sdcard_sclk,
      sdcard_miso => sdcard_miso,
      sdcard_debug => sdcard_debug,
      sdcard_addr => sdcard_addr,
      sdcard_idle => sdcard_idle,
      sdcard_read_start => sdcard_read_start,
      sdcard_read_ack => sdcard_read_ack,
      sdcard_read_done => sdcard_read_done,
      sdcard_write_start => '0',
      sdcard_write_ack => '0',
      sdcard_write_done => open,
      sdcard_error => sdcard_error,
      sdcard_xfer_addr => sdcard_xfer_addr,
      sdcard_xfer_read => sdcard_xfer_read,
      sdcard_xfer_out => sdcard_xfer_out,
      sdcard_xfer_write => '0',
      sdcard_xfer_in => (others => '0'),
      enable => have_tc,
      controller_clk => clk,
      reset => reset,
      clk50mhz => clk50mhz
   );

      process(base_addr_match, bus_addr, bus_control_dati, command_reg, command_ready,
         command_error, controller_ready, controller_error, interrupt_enable,
         word_count_reg, bus_address_reg)
   begin
      bus_dati <= (others => '0');
      if base_addr_match = '1' and bus_control_dati = '1' then
         case bus_addr(2 downto 1) is
            when "00" =>
               bus_dati <= controller_error & "0000000" & controller_ready & interrupt_enable & "000000";
            when "01" =>
               bus_dati <= command_error & command_reg(14 downto 8) & command_ready & command_reg(6 downto 0);
            when "10" =>
               bus_dati <= word_count_reg;
            when "11" =>
               bus_dati <= bus_address_reg;
            when others =>
               null;
         end case;
      end if;
   end process;

   process(nclk, reset)
   begin
      if reset = '1' then
         command_reg <= (others => '0');
         word_count_reg <= (others => '0');
         bus_address_reg <= (others => '0');
         interrupt_enable <= '0';
         read_command <= '0';
         reverse_command <= '0';
      elsif nclk = '1' and nclk'event then
         read_command <= '0';
         reverse_command <= '0';
         if base_addr_match = '1' and bus_control_dato = '1' and bus_control_datob = '0' then
            case bus_addr(2 downto 1) is
               when "00" =>
                  interrupt_enable <= bus_dato(6);
               when "01" =>
                  command_reg <= bus_dato;
                  if bus_dato(15 downto 12) = "0000" and bus_dato(11) = '1' and bus_dato(2 downto 0) = "011" then
                     reverse_command <= '1';
                  elsif bus_dato(15 downto 12) = "0000" and bus_dato(2 downto 0) = "101" then
                     read_command <= '1';
                  end if;
               when "10" =>
                  word_count_reg <= bus_dato;
               when "11" =>
                  bus_address_reg <= bus_dato;
               when others =>
                  null;
            end case;
         end if;
      end if;
   end process;

   process(clk, reset)
   begin
      if reset = '1' then
         tape_state <= tape_idle;
         npr <= '0';
         bus_master_addr <= (others => '0');
         bus_master_dato <= (others => '0');
         bus_master_control_dati <= '0';
         bus_master_control_dato <= '0';
         sdcard_addr <= (others => '0');
         sdcard_read_start <= '0';
         sdcard_read_ack <= '0';
         sdcard_xfer_addr <= 0;
         sdcard_xfer_read <= '0';
         dma_word_count <= (others => '0');
         dma_address <= (others => '0');
         sector_word_count <= 0;
         command_ready <= '0';
         command_error <= '0';
         controller_ready <= '1';
         controller_error <= '0';
         interrupt_pending <= '0';
      elsif clk = '1' and clk'event then
         bus_master_control_dati <= '0';
         bus_master_control_dato <= '0';

         if bg = '1' then
            interrupt_pending <= '0';
         end if;

         if reverse_command = '1' then
            command_ready <= '1';
            command_error <= '0';
            controller_ready <= '1';
            controller_error <= '0';
         end if;

         if read_command = '1' and tape_state = tape_idle then
            command_ready <= '0';
            command_error <= '0';
            controller_ready <= '0';
            controller_error <= '0';
            if have_tc = 1 then
               dma_word_count <= word_count_reg;
               dma_address <= "00" & bus_address_reg;
               sdcard_addr <= (others => '0');
               tape_state <= tape_request_sector;
            else
               command_error <= '1';
               controller_error <= '1';
               command_ready <= '1';
               controller_ready <= '1';
            end if;
         end if;

         case tape_state is
            when tape_idle =>
               npr <= '0';
               sdcard_read_start <= '0';
               sdcard_read_ack <= '0';
               sdcard_xfer_read <= '0';

            when tape_request_sector =>
               if sdcard_idle = '1' and sdcard_read_done = '0' then
                  sdcard_read_start <= '1';
                  tape_state <= tape_wait_sector;
               end if;

            when tape_wait_sector =>
               if sdcard_error = '1' then
                  command_error <= '1';
                  controller_error <= '1';
                  tape_state <= tape_ack_sector;
               elsif sdcard_read_done = '1' then
                  npr <= '1';
                  tape_state <= tape_wait_grant;
               end if;

            when tape_wait_grant =>
               if npg = '1' then
                  sdcard_xfer_addr <= 0;
                  sdcard_xfer_read <= '1';
                  sector_word_count <= 0;
                  tape_state <= tape_read_first;
               end if;

            when tape_read_first =>
               bus_master_addr <= dma_address;
               bus_master_dato <= sdcard_xfer_out;
               bus_master_control_dato <= '1';
               dma_address <= dma_address + 2;
               dma_word_count <= dma_word_count + 1;
               sdcard_xfer_addr <= 1;
               sector_word_count <= 1;
               tape_state <= tape_read_words;

            when tape_read_words =>
               if bus_master_nxm = '1' then
                  command_error <= '1';
                  controller_error <= '1';
                  tape_state <= tape_ack_sector;
               else
                  bus_master_addr <= dma_address;
                  bus_master_dato <= sdcard_xfer_out;
                  bus_master_control_dato <= '1';
                  dma_address <= dma_address + 2;
                  dma_word_count <= dma_word_count + 1;

                  if dma_word_count = x"FFFF" then
                     tape_state <= tape_ack_sector;
                  elsif sector_word_count = 255 then
                     tape_state <= tape_ack_sector;
                  else
                     sector_word_count <= sector_word_count + 1;
                     sdcard_xfer_addr <= sdcard_xfer_addr + 1;
                  end if;
               end if;

            when tape_ack_sector =>
               npr <= '0';
               bus_master_control_dato <= '0';
               sdcard_xfer_read <= '0';
               sdcard_read_start <= '0';
               sdcard_read_ack <= '1';
               if sdcard_read_done = '0' then
                  sdcard_read_ack <= '0';
                  if command_error = '1' or controller_error = '1' or dma_word_count = x"0000" then
                     command_ready <= '1';
                     controller_ready <= '1';
                     interrupt_pending <= '1';
                     tape_state <= tape_idle;
                  else
                     sdcard_addr <= sdcard_addr + 1;
                     tape_state <= tape_request_sector;
                  end if;
               end if;
         end case;
      end if;
   end process;

end implementation;