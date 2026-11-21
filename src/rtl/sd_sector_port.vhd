-- Sector port for the disk controllers. It keeps the sdspi controller-side
-- protocol (start/ack/done, sector transfer words) and drives one slot of
-- sd_card.v directly, without an SPI link or a virtual SD card.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sd_bus_pkg.all;

entity sd_sector_port is
   port(
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
      sdcard_xfer_out : out std_logic_vector(15 downto 0);
      sdcard_xfer_write : in std_logic;
      sdcard_xfer_in : in std_logic_vector(15 downto 0);
      enable : in integer range 0 to 1 := 0;
      sd_clk : in std_logic;
      controller_clk : in std_logic;
      reset : in std_logic;
      sd_req : out sd_req_t;
      sd_rsp : in sd_rsp_t
   );
end sd_sector_port;

architecture rtl of sd_sector_port is

   type buffer_type is array(0 to 255) of std_logic_vector(15 downto 0);
   signal rbuf : buffer_type;
   signal wbuf : buffer_type;

   type port_state_t is (ST_IDLE, ST_REQ, ST_XFER, ST_DONE);
   signal st : port_state_t := ST_IDLE;

   signal is_write : std_logic := '0';
   signal aborted  : std_logic := '0';
   signal sector_r : std_logic_vector(31 downto 0) := (others => '0');
   signal done_r   : std_logic := '0';
   signal err_r    : std_logic := '0';
   signal request_meta, request_sd : std_logic := '0';
   signal grant_meta, grant_cpu : std_logic := '0';
   signal ready_meta, ready_cpu : std_logic := '0';
   signal grant_prev, complete_sd, error_sd : std_logic := '0';
   signal complete_meta, complete_cpu : std_logic := '0';
   signal error_meta, error_cpu : std_logic := '0';

   -- byte n of a sector is the low byte of word n/2 for even n, high byte for odd n
   signal wbyte_idx : integer range 0 to 255;

begin

   wbyte_idx <= to_integer(unsigned(sd_rsp.outaddr(8 downto 1)));

   sd_req.rstart <= request_sd and not is_write;
   sd_req.wstart <= request_sd and is_write;
   sd_req.sector <= sector_r;
   sd_req.wbyte  <= wbuf(wbyte_idx)(7 downto 0) when sd_rsp.outaddr(0) = '0' else
                    wbuf(wbyte_idx)(15 downto 8);

   sdcard_idle <= '1' when st = ST_IDLE and enable = 1 and reset = '0' and
                           ready_cpu = '1' and grant_cpu = '0' else '0';
   sdcard_read_done  <= done_r and not is_write;
   sdcard_write_done <= done_r and is_write;
   sdcard_error <= err_r;


   sdcard_debug <= "0000" when st = ST_IDLE else
                   "0001" when st = ST_REQ else
                   "0010" when st = ST_XFER else
                   "0011";

   -- Byte-valid pulses belong to sd_card.v's clock, not the slower CPU clock.
   -- The sector buffer is read by the CPU only after synchronized completion.
   process(sd_clk)
   begin
      if rising_edge(sd_clk) then
         request_meta <= '1' when st = ST_REQ else '0';
         request_sd <= request_meta;
         grant_prev <= sd_rsp.grant;
         if sd_rsp.grant = '1' and grant_prev = '0' then
            complete_sd <= '0';
            error_sd <= '0';
         elsif sd_rsp.done = '1' or (grant_prev = '1' and sd_rsp.grant = '0') then
            complete_sd <= '1';
            error_sd <= error_sd or sd_rsp.wr_err;
         end if;

         if sd_rsp.grant = '1' and sd_rsp.outen = '1' then
            if sd_rsp.outaddr(0) = '0' then
               rbuf(wbyte_idx)(7 downto 0) <= sd_rsp.outbyte;
            else
               rbuf(wbyte_idx)(15 downto 8) <= sd_rsp.outbyte;
            end if;
         end if;
      end if;
   end process;

   process(controller_clk)
   begin
      if rising_edge(controller_clk) then
         grant_meta <= sd_rsp.grant;
         grant_cpu <= grant_meta;
         ready_meta <= sd_rsp.ready;
         ready_cpu <= ready_meta;
         complete_meta <= complete_sd;
         complete_cpu <= complete_meta;
         error_meta <= error_sd;
         error_cpu <= error_meta;

         -- registered read, one controller_clk latency as in the original sdspi.vhd
         sdcard_xfer_out <= rbuf(sdcard_xfer_addr);

         if sdcard_xfer_write = '1' then
            wbuf(sdcard_xfer_addr) <= sdcard_xfer_in;
         end if;

         case st is
            when ST_IDLE =>
               -- a previous transfer of this slot may still be running after a
               -- controller reset, so wait until sd_card.v has released the slot
               if enable = 1 and reset = '0' and ready_cpu = '1' and grant_cpu = '0' and
                  done_r = '0' and sdcard_read_ack = '0' and sdcard_write_ack = '0' then
                  if sdcard_read_start = '1' or sdcard_write_start = '1' then
                     sector_r <= x"00" & sdcard_addr;
                     is_write <= sdcard_write_start and not sdcard_read_start;
                     err_r <= '0';
                     aborted <= '0';
                     st <= ST_REQ;
                  end if;
               end if;

            when ST_REQ =>
               -- request is held until sd_card.v accepts it (grant). A controller
               -- reset before that cancels the request.
               if reset = '1' then
                  st <= ST_IDLE;
               elsif grant_cpu = '1' then
                  st <= ST_XFER;
               end if;

            when ST_XFER =>
               if reset = '1' then
                  aborted <= '1';
               end if;
               -- Completion is sticky in the SD domain, including grant-fall
               -- completion, so a one-SD-clock done pulse cannot be missed.
               if complete_cpu = '1' then
                  done_r <= '1';
                  err_r <= is_write and error_cpu;
                  st <= ST_DONE;
               end if;

            when ST_DONE =>
               if sdcard_read_ack = '1' or sdcard_write_ack = '1' or aborted = '1' or reset = '1' then
                  done_r <= '0';
                  aborted <= '0';
                  st <= ST_IDLE;
               end if;
         end case;
      end if;
   end process;

end rtl;
