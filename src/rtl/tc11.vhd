library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.sd_bus_pkg.all;

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

      sdcard_req : out sd_req_t;
      sdcard_rsp : in sd_rsp_t;
      sdcard_clk : in std_logic;
      sdcard_debug : out std_logic_vector(3 downto 0);

      have_tc : in integer range 0 to 1;
      reset : in std_logic;
      nclk : in std_logic;
      clk : in std_logic
   );
end tc11;

architecture implementation of tc11 is

-- Block position across commands: the current design keeps the block address across commands until reset. 
-- Should a new command restart at block 0 or at TCDT instead?


signal base_addr_match : std_logic;
signal command_reg : std_logic_vector(15 downto 0) := (others => '0');
signal word_count_reg : std_logic_vector(15 downto 0) := (others => '0');
signal bus_address_reg : std_logic_vector(15 downto 0) := (others => '0');
signal tcdt_reg : std_logic_vector(15 downto 0) := (others => '0');
signal interrupt_enable : std_logic := '0';
signal go_toggle : std_logic := '0';
signal go_sync : std_logic := '0';
signal done_mark : std_logic := '0';
signal command_done : std_logic;
signal cmd_write : std_logic := '0';
signal command_error : std_logic := '0';
signal controller_error : std_logic := '0';
signal interrupt_pending : std_logic := '0';

signal sdcard_addr : std_logic_vector(23 downto 0) := (others => '0');
signal sdcard_idle : std_logic;
signal sdcard_read_start : std_logic := '0';
signal sdcard_read_ack : std_logic := '0';
signal sdcard_read_done : std_logic;
signal sdcard_write_start : std_logic := '0';
signal sdcard_write_ack : std_logic := '0';
signal sdcard_write_done : std_logic;
signal sdcard_error : std_logic;
signal sdcard_xfer_addr : integer range 0 to 255 := 0;
signal sdcard_xfer_out : std_logic_vector(15 downto 0);
signal sdcard_xfer_write : std_logic := '0';
signal sdcard_xfer_in : std_logic_vector(15 downto 0) := (others => '0');

signal dma_word_count : std_logic_vector(15 downto 0) := (others => '0');
signal dma_address : std_logic_vector(17 downto 0) := (others => '0');
signal sector_word_count : integer range 0 to 256 := 0;

type tape_state_t is (
   tape_idle,
   tape_request_sector,
   tape_wait_sector,
   tape_request_bus,
   tape_wait_grant,
   tape_read_prep,
   tape_read_wait,
   tape_read_words,
   tape_write_req,
   tape_write_cap,
   tape_write_zero,
   tape_write_flush,
   tape_write_flush_wait,
   tape_write_ack,
   tape_read_ack,
   tape_next_block,
   tape_finish
);
signal tape_state : tape_state_t := tape_idle;

begin

   base_addr_match <= '1' when base_addr(17 downto 4) = bus_addr(17 downto 4) and have_tc = 1 else '0';
   bus_addr_match <= base_addr_match;

   -- DONE is hidden from the moment GO is written until the controller finishes
   command_done <= '1' when done_mark = go_toggle else '0';

   int_vector <= ivec;
   br <= interrupt_pending and interrupt_enable;

   sd1: entity work.sd_sector_port port map(
      sd_req => sdcard_req,
      sd_rsp => sdcard_rsp,
      sdcard_debug => sdcard_debug,
      sdcard_addr => sdcard_addr,
      sdcard_idle => sdcard_idle,
      sdcard_read_start => sdcard_read_start,
      sdcard_read_ack => sdcard_read_ack,
      sdcard_read_done => sdcard_read_done,
      sdcard_write_start => sdcard_write_start,
      sdcard_write_ack => sdcard_write_ack,
      sdcard_write_done => sdcard_write_done,
      sdcard_error => sdcard_error,
      sdcard_xfer_addr => sdcard_xfer_addr,
      sdcard_xfer_out => sdcard_xfer_out,
      sdcard_xfer_write => sdcard_xfer_write,
      sdcard_xfer_in => sdcard_xfer_in,
      enable => have_tc,
      controller_clk => clk,
      sd_clk => sdcard_clk,
      reset => reset
   );

      process(base_addr_match, bus_addr, bus_control_dati, command_reg, command_done,
         command_error, controller_error, interrupt_enable,
         word_count_reg, bus_address_reg, tcdt_reg)
   begin
      bus_dati <= (others => '0');
      if base_addr_match = '1' and bus_control_dati = '1' then
         case bus_addr(3 downto 1) is
            when "000" =>
               bus_dati <= controller_error & "0000000" & command_done & interrupt_enable & "000000";
            when "001" =>
               bus_dati <= command_error & command_reg(14 downto 8) & command_done & command_reg(6 downto 0);
            when "010" =>
               bus_dati <= word_count_reg;
            when "011" =>
               bus_dati <= bus_address_reg;
            when "100" =>
               bus_dati <= tcdt_reg;
            when others =>
               null;
         end case;
      end if;
   end process;

   -- GO toggles go_toggle; the controller clock domain detects the change
   process(nclk, reset)
   begin
      if reset = '1' then
         command_reg <= (others => '0');
         word_count_reg <= (others => '0');
         bus_address_reg <= (others => '0');
         tcdt_reg <= (others => '0');
         interrupt_enable <= '0';
         go_toggle <= '0';
      elsif nclk = '1' and nclk'event then
         if base_addr_match = '1' and bus_control_dato = '1' and bus_control_datob = '0' then
            case bus_addr(3 downto 1) is
               when "001" =>
                  command_reg <= bus_dato(15 downto 1) & '0';
                  interrupt_enable <= bus_dato(6);
                  if bus_dato(0) = '1' then
                     go_toggle <= not go_toggle;
                  end if;
               when "010" =>
                  word_count_reg <= bus_dato;
               when "011" =>
                  bus_address_reg <= bus_dato;
               when "100" =>
                  tcdt_reg <= bus_dato;
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
         sdcard_write_start <= '0';
         sdcard_write_ack <= '0';
         sdcard_xfer_addr <= 0;
         sdcard_xfer_in <= (others => '0');
         sdcard_xfer_write <= '0';
         dma_word_count <= (others => '0');
         dma_address <= (others => '0');
         sector_word_count <= 0;
         cmd_write <= '0';
         go_sync <= '0';
         done_mark <= '0';
         controller_error <= '0';
         command_error <= '0';
         interrupt_pending <= '0';
      elsif clk = '1' and clk'event then
         bus_master_control_dati <= '0';
         bus_master_control_dato <= '0';
         go_sync <= go_toggle;

         if bg = '1' then
            interrupt_pending <= '0';
         end if;

         case tape_state is
            when tape_idle =>
               npr <= '0';
               sdcard_read_start <= '0';
               sdcard_read_ack <= '0';
               sdcard_write_start <= '0';
               sdcard_write_ack <= '0';
               sdcard_xfer_write <= '0';
               -- a GO that arrives while busy is not replayed: finish syncs done_mark to go_toggle
               if go_sync /= done_mark then
                  command_error <= '0';
                  controller_error <= '0';
                  dma_address <= command_reg(5 downto 4) & bus_address_reg;
                  dma_word_count <= word_count_reg;
                  case command_reg(3 downto 1) is
                     when "010" | "011" =>
                        cmd_write <= '0';
                        tape_state <= tape_request_sector;
                     when "101" | "110" =>
                        cmd_write <= '1';
                        tape_state <= tape_request_bus;
                     when "001" =>
                        sdcard_addr <= x"00" & tcdt_reg;
                        tape_state <= tape_finish;
                     when others =>
                        tape_state <= tape_finish;
                  end case;
               end if;

            when tape_request_sector =>
               if sdcard_idle = '1' and sdcard_read_done = '0' then
                  sdcard_read_start <= '1';
                  tape_state <= tape_wait_sector;
               end if;

            when tape_wait_sector =>
               if sdcard_read_done = '1' then
                  tape_state <= tape_request_bus;
               end if;

            when tape_request_bus =>
               npr <= '1';
               sector_word_count <= 0;
               tape_state <= tape_wait_grant;

            when tape_wait_grant =>
               if npg = '1' then
                  if cmd_write = '1' then
                     tape_state <= tape_write_req;
                  else
                     tape_state <= tape_read_prep;
                  end if;
               end if;

            -- sdcard_xfer_out lags sdcard_xfer_addr by one controller_clk,
            -- so the address runs one word ahead of the word being sent
            when tape_read_prep =>
               sdcard_xfer_addr <= 0;
               tape_state <= tape_read_wait;

            when tape_read_wait =>
               sdcard_xfer_addr <= 1;
               tape_state <= tape_read_words;

            when tape_read_words =>
               if bus_master_nxm = '1' then
                  command_error <= '1';
                  controller_error <= '1';
                  tape_state <= tape_read_ack;
               else
                  bus_master_addr <= dma_address;
                  bus_master_dato <= sdcard_xfer_out;
                  bus_master_control_dato <= '1';
                  dma_address <= dma_address + 2;
                  dma_word_count <= dma_word_count + 1;
                  sector_word_count <= sector_word_count + 1;
                  sdcard_xfer_addr <= (sdcard_xfer_addr + 1) mod 256;
                  if dma_word_count = x"FFFF" or sector_word_count = 255 then
                     tape_state <= tape_read_ack;
                  end if;
               end if;

            when tape_read_ack =>
               npr <= '0';
               sdcard_read_start <= '0';
               sdcard_read_ack <= '1';
               if sdcard_read_done = '0' then
                  sdcard_read_ack <= '0';
                  tape_state <= tape_next_block;
               end if;

            -- DATI is registered as in rk11.vhd: the data is read in the
            -- cycle after control_dati is asserted
            when tape_write_req =>
               bus_master_addr <= dma_address;
               bus_master_control_dati <= '1';
               tape_state <= tape_write_cap;

            when tape_write_cap =>
               if bus_master_nxm = '1' then
                  command_error <= '1';
                  controller_error <= '1';
                  sdcard_xfer_write <= '0';
                  tape_state <= tape_finish;
               else
                  sdcard_xfer_addr <= sector_word_count;
                  sdcard_xfer_in <= bus_master_dati;
                  sdcard_xfer_write <= '1';
                  sector_word_count <= sector_word_count + 1;
                  dma_address <= dma_address + 2;
                  dma_word_count <= dma_word_count + 1;
                  if dma_word_count = x"FFFF" or sector_word_count = 255 then
                     tape_state <= tape_write_zero;
                  else
                     bus_master_addr <= dma_address + 2;
                     bus_master_control_dati <= '1';
                  end if;
               end if;

            -- the rest of a partial block is zero filled, as SIMH does
            when tape_write_zero =>
               if sector_word_count < 256 then
                  sdcard_xfer_addr <= sector_word_count;
                  sdcard_xfer_in <= (others => '0');
                  sdcard_xfer_write <= '1';
                  sector_word_count <= sector_word_count + 1;
               else
                  sdcard_xfer_write <= '0';
                  npr <= '0';
                  tape_state <= tape_write_flush;
               end if;

            when tape_write_flush =>
               if sdcard_idle = '1' and sdcard_write_done = '0' then
                  sdcard_write_start <= '1';
                  tape_state <= tape_write_flush_wait;
               end if;

            when tape_write_flush_wait =>
               if sdcard_write_done = '1' then
                  if sdcard_error = '1' then
                     command_error <= '1';
                     controller_error <= '1';
                  end if;
                  tape_state <= tape_write_ack;
               end if;

            when tape_write_ack =>
               sdcard_write_start <= '0';
               sdcard_write_ack <= '1';
               if sdcard_write_done = '0' then
                  sdcard_write_ack <= '0';
                  tape_state <= tape_next_block;
               end if;

            when tape_next_block =>
               if command_error = '1' or dma_word_count = x"0000" then
                  tape_state <= tape_finish;
               else
                  sdcard_addr <= sdcard_addr + 1;
                  if cmd_write = '1' then
                     tape_state <= tape_request_bus;
                  else
                     tape_state <= tape_request_sector;
                  end if;
               end if;

            when tape_finish =>
               npr <= '0';
               sdcard_read_start <= '0';
               sdcard_read_ack <= '0';
               sdcard_write_start <= '0';
               sdcard_write_ack <= '0';
               sdcard_xfer_write <= '0';
               done_mark <= go_toggle;
               interrupt_pending <= '1';
               tape_state <= tape_idle;

            when others =>
               tape_state <= tape_idle;
         end case;
      end if;
   end process;

end implementation;