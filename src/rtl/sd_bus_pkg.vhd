-- Interface between the disk controllers (RK11, RL11, RH11, TC11) and the
-- sd_card.v request interface. Each controller owns one slot of sd_card.v.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package sd_bus_pkg is

   -- controller -> sd_card.v (per slot)
   type sd_req_t is record
      rstart : std_logic;                             -- read request, held until granted
      wstart : std_logic;                             -- write request, held until granted
      sector : std_logic_vector(31 downto 0);         -- sector number for the request
      wbyte  : std_logic_vector(7 downto 0);          -- write data byte for sd_card.v outaddr
   end record;

   -- sd_card.v -> controller (broadcast, the grant/done/outen fields are per slot)
   type sd_rsp_t is record
      grant   : std_logic;                            -- request has been accepted by sd_card.v
      done    : std_logic;                            -- transfer for this slot has finished
      wr_err  : std_logic;                            -- write failed (valid with done)
      outen   : std_logic;                            -- read byte valid for this slot
      outaddr : std_logic_vector(8 downto 0);         -- byte offset within the sector
      outbyte : std_logic_vector(7 downto 0);         -- read byte
      ready   : std_logic;                            -- SD card initialized
   end record;

   constant SD_REQ_IDLE : sd_req_t := (
      rstart => '0', wstart => '0', sector => (others => '0'), wbyte => (others => '0'));

   constant SD_RSP_IDLE : sd_rsp_t := (
      grant => '0', done => '0', wr_err => '0', outen => '0',
      outaddr => (others => '0'), outbyte => (others => '0'), ready => '0');

end package sd_bus_pkg;
