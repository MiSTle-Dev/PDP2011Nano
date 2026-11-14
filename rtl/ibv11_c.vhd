
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

entity ibv11_c is
   port(
      atn_rcv : in std_logic;
      ifc_rcv : in std_logic;
      ren_rcv : in std_logic;
      dav_rcv : in std_logic;
      tcs : in std_logic;

      atn : out std_logic := '0';
      assrt_nrfd : out std_logic;

      reset : in std_logic;
      clk : in std_logic
   );
end ibv11_c;

architecture implementation of ibv11_c is

type state_type is (
   csbs,                               -- gpib timed state machine controller ( Pedroni page 392 )
   cshs,
   csws,
   caws
);

signal state : state_type;
signal nextstate : state_type;
signal t, tmax : natural range 0 to 100;

begin

   -- timer
   process(clk, state)
   begin
      case state is
         when cshs =>
            tmax <= 3;   -- delay = ca 500ns  --- set smallest value for test
         when csws =>
            tmax <= 3;
         when others =>
            tmax <= 0;
      end case;
      if clk = '1'and clk'event then
         if state /= nextstate then
            t <= 0;
         elsif t /= tmax then
            t <= t + 1;
         end if;
      end if;
   end process;

   -- register for state
   process(clk, reset)
   begin
      if reset = '1' then
         state <= csbs;
      elsif clk = '1'and clk'event then
         state <= nextstate;
      end if;
   end process;

   -- logic for state
   process(state, tcs, t, tmax, dav_rcv)
   begin
      if tcs = '0' then
         nextstate <= csbs;
      else
         case state is
            when csbs =>
               if tcs = '1'then
                  nextstate <= cshs;
               else
                  nextstate <= csbs;
               end if;
            when cshs =>
               if t = tmax and dav_rcv = '0' then
                  nextstate <= csws;
               else
                  nextstate <= cshs;
               end if;
            when csws =>
               if t = tmax then
                  nextstate <= caws;
               else
                  nextstate <= csws;
               end if;
            when caws =>
                  nextstate <= caws;
         end case;
      end if;
   end process;

   -- logic for outputs
   process(state)
   begin
      case state is
         when csbs =>
            assrt_nrfd <= '1';
            atn <= '0';
         when cshs =>
            assrt_nrfd <= '0';
            atn <= '0';
         when csws =>
            assrt_nrfd <= '0';
            atn <= '1';
         when caws =>
            assrt_nrfd <= '1';
            atn <= '1';
      end case;
   end process;

end implementation;





