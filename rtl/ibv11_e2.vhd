
--
-- Copyright (c) 2023-2025 Jan Secker and Sytse van Slooten
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

-- $Revision$

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ibv11_io is
   port (
      eoi : inout std_logic;
      atn : inout std_logic;
      ifc : inout std_logic;
      ren : inout std_logic;
      srq : inout std_logic;
      nrfd : inout std_logic;
      dav : inout std_logic;
      ndac : inout std_logic;
      dio : inout std_logic_vector(8 downto 1);

      eoi_in : in std_logic;
      atn_in : in std_logic;
      ifc_in : in std_logic;
      ren_in : in std_logic;
      srq_in : in std_logic;
      nrfd_in : in std_logic;
      dav_in : in std_logic;
      ndac_in : in std_logic;
      dio_in : in std_logic_vector(8 downto 1);

      eoi_out : out std_logic;
      atn_out : out std_logic;
      ifc_out : out std_logic;
      ren_out : out std_logic;
      srq_out : out std_logic;
      nrfd_out : out std_logic;
      dav_out : out std_logic;
      ndac_out : out std_logic;
      dio_out : out std_logic_vector(8 downto 1);

      oe : in std_logic;
      clk : in std_logic
   );
end ibv11_io;

architecture rtl of ibv11_io is

signal r1, r2 : std_logic_vector(15 downto 0);      -- synchronizer registers
signal unsynced : std_logic_vector(15 downto 0);
signal din : std_logic_vector(15 downto 0);

begin
   eoi_out <= not r2(15);
   atn_out <= not r2(14);
   ifc_out <= not r2(13);
   ren_out <= not r2(12);
   srq_out <= not r2(11);
   nrfd_out <= not r2(10);
   dav_out <= not r2(9);
   ndac_out <= not r2(8);
   dio_out <= not r2(7 downto 0);

   eoi <= not eoi_in;
   atn <= not atn_in;
   ifc <= not ifc_in;
   ren <= not ren_in;
   srq <= 'Z';
   nrfd <= not nrfd_in when nrfd_in = '1' else 'Z';
   dav <= not dav_in when dav_in = '1' else 'Z';
   ndac <= not ndac_in when ndac_in = '1' else 'Z';
   dio <= not dio_in when oe = '1' else "ZZZZZZZZ";

   sync: process(clk)
   begin
      if clk = '1' and clk'event then
         r1 <= eoi & atn & ifc & ren & srq & nrfd & dav & ndac & dio;
         r2 <= r1;
      end if;
   end process;

end rtl;



