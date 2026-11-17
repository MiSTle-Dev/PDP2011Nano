
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

entity ibv11_ah is
   port(
      dav_rcv : in std_logic;
      lon : in std_logic;
      write_to_ibd : in std_logic;
      read_from_ibd : in std_logic;
      acc : in std_logic;
      assrt_nrfd : in std_logic;
      ton : in std_logic;
      atn : std_logic;

      lnr : buffer std_logic;
      ndac : buffer std_logic;
      nrfd : out std_logic;

      reset : in std_logic;
      clk : in std_logic
   );
end ibv11_ah;

architecture implementation of ibv11_ah is

signal dac_ff : std_logic;


begin

   process(clk)
   begin
      if clk = '1'and clk'event then
         if dav_rcv = '1'and write_to_ibd = '1'then
            dac_ff <= '1';
         elsif dav_rcv = '0' or reset = '1'then
            dac_ff <= '0';
         elsif read_from_ibd = '1'and acc = '0' then
            if lnr = '1'then
               dac_ff <= '1';
            elsif lnr = '0'then
               dac_ff <= '0';
            end if;
         end if;
      end if;
   end process;

   ndac <= '1' when (lon = '1' and dac_ff = '0') else '0';
   lnr <= '1' when (ndac = '1'and dav_rcv = '1') else '0';
--   nrfd <= '1' when (dac_ff = '1' or (lon = '0' and acc = '1'and ton = '0' and atn = '0') or assrt_nrfd = '0') else '0';
   nrfd <= '1' when (dac_ff = '1' or (lon = '0' and acc = '1'and ton = '0' and atn = '0')) else '0';      -- needed to pass vibb test

end;
