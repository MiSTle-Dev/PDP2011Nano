
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

entity xu28m is
   port(
      base_addr : in std_logic_vector(17 downto 0);

      bus_addr_match : out std_logic;
      bus_addr : in std_logic_vector(17 downto 0);
      bus_dati : out std_logic_vector(15 downto 0);
      bus_dato : in std_logic_vector(15 downto 0);
      bus_control_dati : in std_logic;
      bus_control_dato : in std_logic;
      bus_control_datob : in std_logic;

      enc28_mac_1 : in std_logic_vector(7 downto 0) := x"08";
      enc28_mac_2 : in std_logic_vector(7 downto 0) := x"00";
      enc28_mac_3 : in std_logic_vector(7 downto 0) := x"2b";
      enc28_mac_4 : in std_logic_vector(7 downto 0) := x"20";
      enc28_mac_5 : in std_logic_vector(7 downto 0) := x"11";
      enc28_mac_6 : in std_logic_vector(7 downto 0) := x"00";

      enc28_force_fdx : in integer range 0 to 1 := 0;
      enc28_force_hdx : in integer range 0 to 1 := 0;

      have_xu_enc : in integer range 0 to 1 := 0;

      reset : in std_logic;
      clk : in std_logic
   );
end xu28m;

architecture implementation of xu28m is


-- regular bus interface

signal base_addr_match : std_logic;

signal fdx : std_logic;
signal hdx : std_logic;

begin

-- regular bus interface

   base_addr_match <= '1' when have_xu_enc = 1 and base_addr(17 downto 3) = bus_addr(17 downto 3) else '0';
   bus_addr_match <= base_addr_match;

-- input mangling

   with enc28_force_fdx select fdx <=
      '0' when 0,
      '1' when 1,
      '0' when others;

   with enc28_force_hdx select hdx <=
      '0' when 0,
      '1' when 1,
      '0' when others;

-- regular bus interface : handle register contents and dependent logic

   process(clk, reset)
   begin
      if clk = '1' and clk'event then
         if reset = '1' then
         else
            if have_xu_enc = 1 then

               if base_addr_match = '1' and bus_control_dati = '1' then
                  case bus_addr(2 downto 1) is
                     when "00" =>                                    -- read mac address bytes 1/2
                        bus_dati <= enc28_mac_2 & enc28_mac_1;

                     when "01" =>                                    -- read mac address bytes 3/4
                        bus_dati <= enc28_mac_4 & enc28_mac_3;

                     when "10" =>                                    -- read mac address bytes 5/6
                        bus_dati <= enc28_mac_6 & enc28_mac_5;

                     when "11" =>                                    -- read flags
                        bus_dati <= "00000000000000" & hdx & fdx;

                     when others =>
                        null;
                  end case;
               end if;

            end if;

         end if;
      end if;

   end process;

end implementation;
