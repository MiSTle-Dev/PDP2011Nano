
--
-- Copyright (c) 2023-2025 Jan Secker
--
-- Permission is hereby granted to any person obtaining a copy of these VHDL source files and
-- other language source files and associated documentation files ("the materials") to use
-- these materials solely for personal, non-commercial purposes.
-- You are also granted permission to make changes to the materials, on the condition that this
-- copyright notice is retained unchanged.
--
-- The materials are distributed in the hope that they will be useful, but WITHOUT ANY WARRANTY;
-- without even the implibs_ied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ibv11_sh is
   port(
      dav_rcv : in std_logic;
      write_to_ibd : in std_logic;
      atn_rcv : in std_logic;
      ton : in std_logic;
      atn : in std_logic;
      ndac_rcv : in std_logic;
      nrfd_rcv : in std_logic;

      tkr : out std_logic;
      cmd : out std_logic;
      enb_xfer : out std_logic;
      er2 : out std_logic;
      dav : out std_logic;

      reset : in std_logic;
      clk50mhz : in std_logic
   );
end ibv11_sh;

architecture implementation of ibv11_sh is

signal send_byte : std_logic;
signal clr_dav : std_logic :='1';
signal err2 : std_logic;


type state_type is (
   idle,                               -- gpib timed state machine controller ( Pedroni page 392 )
   send,
   delay,
   check_nrfd,
   valid,
   error2
);

signal state : state_type;
signal nextstate : state_type;
signal t, tmax : natural range 0 to 1000;


begin

   -- sh state machine timer
   process(clk50mhz, state)
   begin
      case state is
         when delay =>
            tmax <= 12;                -- FIXME delay is too short really, but longer than this won't pass vibb
         when others =>
            tmax <= 0;
      end case;
      if clk50mhz = '1'and clk50mhz' event then
         if state /= nextstate then
            t <= 0;
         elsif t /= tmax then
            t <= t + 1;
         end if;
      end if;
   end process;

   -- register for state
   process(clk50mhz, reset)
   begin
      if reset = '1' then
         state <= idle;
      elsif clk50mhz = '1'and clk50mhz'event then
         state <= nextstate;
      end if;
   end process;

   -- logic for state
   process(state, send_byte, err2, dav_rcv, t, tmax, nrfd_rcv, clr_dav,ton)
   begin
      case state is

         when idle =>
            if send_byte = '1' and err2 = '0' then
               nextstate <= send;
            elsif dav_rcv = '1' then
               nextstate <= idle;
            elsif send_byte = '1' and err2 = '1'then
               nextstate <= error2;
            else
               nextstate <= idle;
            end if;

         when send =>
               nextstate <= delay;

         when delay =>
            if t = tmax then
               nextstate <= valid;
            else
               nextstate <= delay;
            end if;

         when check_nrfd =>
            if nrfd_rcv = '0' then
               nextstate <= valid;
            else
               nextstate <= check_nrfd;
            end if;

         when valid =>
            if clr_dav = '1' then
               nextstate <= idle;
            else
               nextstate <= valid;
            end if;

         when error2 =>
            if ton = '0' then          -- FIXME the ibv11 doc says that er2 resets if ton=0 and tcs=0
               nextstate <= idle;
            else
               nextstate <= error2;
            end if;

      end case;
   end process;

   -- logic for outputs
   process(state)
   begin
      case state is
         when idle =>
            dav <= '0';
            enb_xfer <= '0';
            er2 <= '0';

         when send =>
            dav <= '0';
            enb_xfer <= '1';
            er2 <= '0';

         when delay =>
            dav <= '0';
            enb_xfer <= '1';
            er2 <= '0';

         when check_nrfd =>
            dav <= '0';
            enb_xfer <= '1';
            er2 <= '0';

         when valid =>
            dav <= '1';
            enb_xfer <= '1';
            er2 <= '0';

         when error2 =>
            dav <= '0';
            enb_xfer <= '0';
            er2 <= '1';
      end case;
   end process;


   -- other logic
   send_byte <= '1' when (ton = '1' or atn = '1') and dav_rcv = '0' and write_to_ibd = '1' else '0';
   err2 <= '1' when (ndac_rcv = '0'and nrfd_rcv = '0' and write_to_ibd = '1') else '0';
   clr_dav  <= '1' when ((ton = '0' and atn = '0') or ndac_rcv = '0') else '0';
   cmd <= '1' when (dav_rcv = '0' and nrfd_rcv = '0' and state = idle and atn = '1') else '0';
   tkr <= '1' when (dav_rcv = '0' and nrfd_rcv = '0' and state = idle and ton = '1' and atn_rcv = '0') else '0';

end;
