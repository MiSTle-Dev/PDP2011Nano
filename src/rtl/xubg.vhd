
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

entity xubg is
   port(
      base_addr : in std_logic_vector(17 downto 0);

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

      xubg_cs : out std_logic;
      xubg_mosi : out std_logic;
      xubg_sclk : out std_logic;
      xubg_miso : in std_logic;

      have_xu_enc : in integer range 0 to 1 := 0;

      reset : in std_logic;
      clk : in std_logic
   );
end xubg;

architecture implementation of xubg is


-- regular bus interface

signal base_addr_match : std_logic;

signal xubg_xf : std_logic_vector(15 downto 0);            -- xmit from
signal xubg_xl : std_logic_vector(11 downto 0);            -- xmit length
signal xubg_rt : std_logic_vector(15 downto 0);            -- receive to
signal xubg_rl : std_logic_vector(11 downto 0);            -- receive length

signal xf : std_logic_vector(15 downto 0);                 -- xmit from
signal xl : std_logic_vector(11 downto 0);                 -- xmit length
signal rt : std_logic_vector(15 downto 0);                 -- receive to
signal rl : std_logic_vector(11 downto 0);                 -- receive length

signal xubg_work: std_logic_vector(15 downto 0);

signal work: std_logic_vector(15 downto 0);
signal workr: std_logic_vector(15 downto 0);

signal run : std_logic;
signal cs : std_logic;
signal noclock : std_logic;
signal mynpr : std_logic;
signal bmr : std_logic;
signal bmw : std_logic;

signal bitcount : integer range 0 to 15;

signal clkcounter : std_logic_vector(4 downto 0);
signal xubg_clk : std_logic;

type cmd_state_type is (
   cmd_prestart,
   cmd_start,
   cmd_xmit,
   cmd_recv,
   cmd_done,
   cmd_wait
);
signal cmd_state : cmd_state_type := cmd_done;

begin


-- regular bus interface

   base_addr_match <= '1' when have_xu_enc = 1 and base_addr(17 downto 4) = bus_addr(17 downto 4) else '0';
   bus_addr_match <= base_addr_match;

   xubg_cs <= cs;
   xubg_sclk <= not xubg_clk when cs = '0' and noclock = '0' else '0';

   npr <= mynpr;

-- regular bus interface : handle register contents and dependent logic

   process(clk, reset)
   begin
      if clk = '1' and clk'event then
         if reset = '1' then
            mynpr <= '0';
            bmr <= '0';
            bmw <= '0';
         else
            if have_xu_enc = 1 then
               if base_addr_match = '1' and bus_control_dato = '1' then
                  case bus_addr(3 downto 1) is
                     when "000" =>                                   -- address 0 - read control register
                        xubg_xl <= "000000001000";                             -- transmit 8 bits
                        xubg_rl <= "000000001000";                             -- receive 8 bits
                        xubg_work <= bus_dato(7 downto 0) & "00000000";        -- bits to transmit
                        mynpr <= '1';                                          -- go, the state machine takes it from here while the cpu is stopped

                     when "001" =>                                   -- address 2 - read mac register
                        xubg_xl <= "000000010000";                             -- transmit 16 bits
                        xubg_rl <= "000000001000";                             -- receive 8 bits
                        xubg_work <= bus_dato(7 downto 0) & "00000000";        -- bits to transmit
                        mynpr <= '1';                                          -- go, the state machine takes it from here while the cpu is stopped

                     when "010" =>                                   -- address 4 - write register or buffer memory
                        xubg_xl <= "000000010000";                             -- transmit 16 bits
                        xubg_rl <= "000000000000";                             -- receive 0 bits
                        xubg_work <= bus_dato;                                 -- bits to transmit
                        mynpr <= '1';                                          -- go, the state machine takes it from here while the cpu is stopped

                     when "011" =>                                   -- address 6, write 8, read 16 bits from the buffer memory
                        xubg_xl <= "000000001000";                             -- transmit 8 bits
                        xubg_rl <= "000000010000";                             -- receive 16 bits
                        xubg_work <= bus_dato(7 downto 0) & "00000000";        -- bits to transmit
                        mynpr <= '1';                                          -- go, the state machine takes it from here while the cpu is stopped

                     when "100" =>                                   -- address 10 - setup transmit from address for busmaster
                        xubg_xf <= bus_dato;

                     when "101" =>                                   -- address 12 - setup transmit length for busmaster
                        xubg_xl <= bus_dato(8 downto 0) & "000";               -- payload length, the command byte is not included but added by the state machine
                        xubg_rl <= (others => '0');                            -- nothing to receive
                        xubg_work <= "0111101000000000";                       -- bits to transmit; implicitly, bus master transmit means a wbm
                        bmw <= '1';                                            -- flag bus master write
                        mynpr <= '1';                                          -- go; setting the length also kicks off the transaction

                     when "110" =>                                   -- address 14 - setup receive to address for busmaster
                        xubg_rt <= bus_dato;

                     when "111" =>                                   -- address 16 - setup receive length for busmaster
                        xubg_rl <= bus_dato(8 downto 0) & "000";               -- payload length
                        xubg_xl <= "000000001000";                             -- transmit 8 bits, the rbm command
                        xubg_work <= "0011101000000000";                       -- bits to transmit; implicitly, bus master receive means an rbm
                        bmr <= '1';                                            -- flag bus master receive
                        mynpr <= '1';                                          -- go; setting up the length also kicks off the transaction

                     when others =>
                        null;

                  end case;
               end if;

               if base_addr_match = '1' and bus_control_dati = '1' then
                  case bus_addr(3 downto 1) is
                     when "000" =>                                   -- read work register
                        bus_dati <= workr;

                     when "001" =>                                   -- read work register, byte swapped
                        bus_dati <= workr(7 downto 0) & workr(15 downto 8);

                     when others =>
                        bus_dati <= workr;
                  end case;
               end if;


               if mynpr = '1' and npg = '1' then
                  if cmd_state = cmd_done then
                     mynpr <= '0';
                     bmr <= '0';
                     bmw <= '0';
                  end if;

               end if;

            end if;

         end if;
      end if;

   end process;

-- clock divider for spi clock

   process(clk, reset)
   begin
      if clk = '1' and clk'event then
         clkcounter <= clkcounter + 1;
         xubg_clk <= clkcounter(0);
      end if;
   end process;

-- state machine for spi communication to enc28j60


   process(xubg_clk, reset)
   begin
      if xubg_clk = '1' and xubg_clk'event then

         if reset = '1' then
            if have_xu_enc = 1 then
               cs <= '1';
               noclock <= '0';
               cmd_state <= cmd_wait;

               bus_master_addr <= (others => '0');
               bus_master_dato <= (others => '0');
               bus_master_control_dati <= '0';
               bus_master_control_dato <= '0';

            end if;

         else
            if have_xu_enc = 1 then
               if mynpr = '1' and npg = '1' then

                  case cmd_state is

                     when cmd_prestart =>
                        cs <= '0';
                        noclock <= '1';
                        cmd_state <= cmd_start;

                     when cmd_start =>
                        cs <= '0';
                        noclock <= '0';
                        xubg_mosi <= xubg_work(15);
                        work <= xubg_work(14 downto 0) & '0';
                        cmd_state <= cmd_xmit;
                        if bmw = '1' then
                           xf <= xubg_xf;
                           xl <= xubg_xl + 7;
                           bitcount <= 6;
                        else
                           xl <= xubg_xl - 1;
                        end if;
                        if bmr = '1' then
                           rt <= xubg_rt;
                        end if;

                     when cmd_xmit =>
                        xubg_mosi <= work(15);
                        work <= work(14 downto 0) & work(15);
                        if bmw = '1' then
                           bitcount <= bitcount - 1;
                           if bitcount = 0 then
                              bus_master_control_dati <= '0';
                              work <= bus_master_dati(7 downto 0) & bus_master_dati(15 downto 8);
--                              xubg_mosi <= bus_master_dati(7);
                              bitcount <= 15;
                           end if;
                           if bitcount = 1 then
                              bus_master_addr <= "00" & xf;
                              xf <= xf + 2;
                              bus_master_control_dati <= '1';
                           end if;
                        end if;
                        xl <= xl - 1;
                        if xl = "000000000000" then
                           if xubg_rl = "000000000000" then
                              cmd_state <= cmd_done;
--                              cs <= '1';
                              noclock <= '1';
                           else
                              cmd_state <= cmd_recv;
                              rl <= xubg_rl - 1;
                              bitcount <= 14;
                              workr <= "000000000000000" & xubg_miso;
                           end if;
                           bus_master_control_dati <= '0';
                        end if;

                     when cmd_recv =>
                        workr <= workr(14 downto 0) & xubg_miso;
                        rl <= rl - 1;
                        bitcount <= bitcount - 1;
                        if bitcount = 0 then
                           bitcount <= 15;
                        end if;
                        if bitcount = 15 and bmr = '1' then
                           bus_master_addr <= "00" & rt;
                           bus_master_dato <= workr(6 downto 0) & xubg_miso & workr(14 downto 7);
                           bus_master_control_dato <= '1';
                           rt <= rt + 2;
                        else
                           bus_master_control_dato <= '0';
                        end if;
                        if rl = "000000000000" then
                           cmd_state <= cmd_done;
--                           cs <= '1';
                           noclock <= '1';
                        end if;

                     when cmd_done =>
                        bus_master_control_dato <= '0';
                        noclock <= '0';
                        cs <= '1';

                     when cmd_wait =>
                        cs <= '1';
                        cmd_state <= cmd_prestart;

                     when others =>
                        null;
                  end case;

               else
                  cs <= '1';
                  bus_master_control_dato <= '0';
                  cmd_state <= cmd_wait;
               end if;

            end if;

         end if;
      end if;

   end process;

end implementation;
