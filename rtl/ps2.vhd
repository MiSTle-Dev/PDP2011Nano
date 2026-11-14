
--
-- Copyright (c) 2008-2021 Sytse van Slooten
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

entity ps2 is
   port(
      base_addr : in std_logic_vector(17 downto 0);
      ivec : in std_logic_vector(8 downto 0);

      br : out std_logic;
      bg : in std_logic;
      int_vector : out std_logic_vector(8 downto 0);

      bus_addr_match : out std_logic;
      bus_addr : in std_logic_vector(17 downto 0);
      bus_dati : out std_logic_vector(15 downto 0);
      bus_dato : in std_logic_vector(15 downto 0);
      bus_control_dati : in std_logic;
      bus_control_dato : in std_logic;
      bus_control_datob : in std_logic;

      usb_kbd        : in std_logic_vector (7 downto 0);
      kbd_strobe     : in std_logic;

      reset : in std_logic;
      clk : in std_logic
   );
end ps2;

architecture implementation of ps2 is


-- regular bus interface

signal base_addr_match : std_logic;
signal interrupt_trigger : std_logic := '0';
type interrupt_state_type is (
   i_idle,
   i_req,
   i_wait
);
signal interrupt_state : interrupt_state_type := i_idle;


-- local data

-- usb_kbd carries one HID byte per event (bit 7 = release); kbd_strobe toggles per new byte
signal ps2_scancode : std_logic_vector(7 downto 0);
signal ps2_rxdone : std_logic;
signal ps2_rxie : std_logic;

signal kbd_strobe_s1 : std_logic;
signal kbd_strobe_s2 : std_logic;
signal kbd_event : std_logic;

-- the firmware expects PS/2 set-2 bytes: [E0] [F0] code, sent one byte per interrupt
-- buffer bursts while the CPU services the current receive byte
constant ps2_queue_depth : positive := 8;
type ps2_queue_type is array (natural range <>) of std_logic_vector(7 downto 0);
signal ps2_queue : ps2_queue_type(0 to ps2_queue_depth - 1);
signal ps2_queue_n : integer range 0 to ps2_queue_depth;

-- HID usage code (7 bits) to PS/2 set-2 code; high byte E0 for extended keys, 0000 if unmapped
function hid2ps2 (code : std_logic_vector(6 downto 0)) return std_logic_vector is
begin
   case code is
      when "0000100" => return x"001C";  -- 04
      when "0000101" => return x"0032";  -- 05
      when "0000110" => return x"0021";  -- 06
      when "0000111" => return x"0023";  -- 07
      when "0001000" => return x"0024";  -- 08
      when "0001001" => return x"002B";  -- 09
      when "0001010" => return x"0034";  -- 0A
      when "0001011" => return x"0033";  -- 0B
      when "0001100" => return x"0043";  -- 0C
      when "0001101" => return x"003B";  -- 0D
      when "0001110" => return x"0042";  -- 0E
      when "0001111" => return x"004B";  -- 0F
      when "0010000" => return x"003A";  -- 10
      when "0010001" => return x"0031";  -- 11
      when "0010010" => return x"0044";  -- 12
      when "0010011" => return x"004D";  -- 13
      when "0010100" => return x"0015";  -- 14
      when "0010101" => return x"002D";  -- 15
      when "0010110" => return x"001B";  -- 16
      when "0010111" => return x"002C";  -- 17
      when "0011000" => return x"003C";  -- 18
      when "0011001" => return x"002A";  -- 19
      when "0011010" => return x"001D";  -- 1A
      when "0011011" => return x"0022";  -- 1B
      when "0011100" => return x"0035";  -- 1C
      when "0011101" => return x"001A";  -- 1D
      when "0011110" => return x"0016";  -- 1E
      when "0011111" => return x"001E";  -- 1F
      when "0100000" => return x"0026";  -- 20
      when "0100001" => return x"0025";  -- 21
      when "0100010" => return x"002E";  -- 22
      when "0100011" => return x"0036";  -- 23
      when "0100100" => return x"003D";  -- 24
      when "0100101" => return x"003E";  -- 25
      when "0100110" => return x"0046";  -- 26
      when "0100111" => return x"0045";  -- 27
      when "0101000" => return x"005A";  -- 28
      when "0101001" => return x"0076";  -- 29
      when "0101010" => return x"0066";  -- 2A
      when "0101011" => return x"000D";  -- 2B
      when "0101100" => return x"0029";  -- 2C
      when "0101101" => return x"004E";  -- 2D
      when "0101110" => return x"0055";  -- 2E
      when "0101111" => return x"0054";  -- 2F
      when "0110000" => return x"005B";  -- 30
      when "0110001" => return x"005D";  -- 31
      when "0110010" => return x"002F";  -- 32
      when "0110011" => return x"004C";  -- 33
      when "0110100" => return x"0052";  -- 34
      when "0110101" => return x"000E";  -- 35
      when "0110110" => return x"0041";  -- 36
      when "0110111" => return x"0049";  -- 37
      when "0111000" => return x"004A";  -- 38
      when "0111001" => return x"0058";  -- 39
      when "0111010" => return x"0005";  -- 3A
      when "0111011" => return x"0006";  -- 3B
      when "0111100" => return x"0004";  -- 3C
      when "0111101" => return x"000C";  -- 3D
      when "0111110" => return x"0003";  -- 3E
      when "0111111" => return x"000B";  -- 3F
      when "1000000" => return x"0083";  -- 40
      when "1000001" => return x"000A";  -- 41
      when "1000010" => return x"0001";  -- 42
      when "1000011" => return x"0009";  -- 43
      when "1000100" => return x"0078";  -- 44
      when "1000111" => return x"007E";  -- 47
      when "1001001" => return x"E070";  -- 49
      when "1001010" => return x"E06C";  -- 4A
      when "1001011" => return x"E07D";  -- 4B
      when "1001100" => return x"E071";  -- 4C
      when "1001101" => return x"E069";  -- 4D
      when "1001110" => return x"E07A";  -- 4E
      when "1001111" => return x"E074";  -- 4F
      when "1010000" => return x"E06B";  -- 50
      when "1010001" => return x"E072";  -- 51
      when "1010010" => return x"E075";  -- 52
      when "1010011" => return x"0077";  -- 53
      when "1010100" => return x"E04A";  -- 54
      when "1010101" => return x"007C";  -- 55
      when "1010110" => return x"007B";  -- 56
      when "1010111" => return x"0079";  -- 57
      when "1011000" => return x"E05A";  -- 58
      when "1011001" => return x"0069";  -- 59
      when "1011010" => return x"0072";  -- 5A
      when "1011011" => return x"007A";  -- 5B
      when "1011100" => return x"006B";  -- 5C
      when "1011101" => return x"0073";  -- 5D
      when "1011110" => return x"0074";  -- 5E
      when "1011111" => return x"006C";  -- 5F
      when "1100000" => return x"0075";  -- 60
      when "1100001" => return x"007D";  -- 61
      when "1100010" => return x"0070";  -- 62
      when "1100011" => return x"0071";  -- 63
      when "1100100" => return x"0061";  -- 64
      when "1101000" => return x"0014";  -- 68
      when "1101001" => return x"0012";  -- 69
      when "1101010" => return x"0011";  -- 6A
      when "1101011" => return x"E01F";  -- 6B
      when "1101100" => return x"E014";  -- 6C
      when "1101101" => return x"0059";  -- 6D
      when "1101110" => return x"E011";  -- 6E
      when "1101111" => return x"E027";  -- 6F
      when others    => return x"0000";
   end case;
end function;

begin

   base_addr_match <= '1' when base_addr(17 downto 2) = bus_addr(17 downto 2) else '0';
   bus_addr_match <= base_addr_match;

   process(clk, reset)
      variable ps2_kbd_code : std_logic_vector(15 downto 0);
      variable ps2_kbd_tmp : ps2_queue_type(0 to 2);
      variable ps2_kbd_n : integer range 0 to 3;
   begin
      if clk = '1' and clk'event then
         if reset = '1' then

            ps2_rxdone <= '0';
            ps2_rxie <= '0';

            kbd_strobe_s1 <= '0';
            kbd_strobe_s2 <= '0';
            kbd_event <= '0';
            ps2_queue_n <= 0;

            ps2_scancode <= (others => '0');

            br <= '0';
            interrupt_trigger <= '0';
            interrupt_state <= i_idle;

         else

            case interrupt_state is

               when i_idle =>

                  br <= '0';
                  if ps2_rxie = '1' and ps2_rxdone = '1' then
                     if interrupt_trigger = '0' then
                        interrupt_state <= i_req;
                        br <= '1';
                        interrupt_trigger <= '1';
                     end if;
                  else
                     interrupt_trigger <= '0';
                  end if;

               when i_req =>
                  if bg = '1' then
                     int_vector <= ivec;
                     br <= '0';
                     interrupt_state <= i_wait;
                  end if;

               when i_wait =>
                  if bg = '0' then
                     interrupt_state <= i_idle;
                  end if;

               when others =>
                  interrupt_state <= i_idle;

            end case;

            if base_addr_match = '1' and bus_control_dati = '1' then
               case bus_addr(2 downto 1) is
                  when "00" =>
                     bus_dati <= "00000000" & ps2_rxdone & ps2_rxie & "000000";
                  when "01" =>
                     ps2_rxdone <= '0';
                     bus_dati <= "00000000" & ps2_scancode;
                  when others =>
                     bus_dati <= "0000000000000000";
               end case;

            end if;

            if base_addr_match = '1' and bus_control_dato = '1' then
               if bus_control_datob = '0' or (bus_control_datob = '1' and bus_addr(0) = '0') then
                  case bus_addr(2 downto 1) is
                     when "00" =>
                        ps2_rxie <= bus_dato(6);
                     when others =>
                        null;
                  end case;
               end if;
            end if;

--
-- synchronize kbd_strobe and detect a toggle; each toggle queues the PS/2 bytes for one HID byte
--

            kbd_strobe_s1 <= kbd_strobe;
            kbd_strobe_s2 <= kbd_strobe_s1;
            kbd_event <= kbd_strobe_s1 xor kbd_strobe_s2;

            if kbd_event = '1' then
               ps2_kbd_code := hid2ps2(usb_kbd(6 downto 0));
               ps2_kbd_n := 0;
               if ps2_kbd_code(15 downto 8) = x"E0" then
                  ps2_kbd_tmp(ps2_kbd_n) := x"E0";
                  ps2_kbd_n := ps2_kbd_n + 1;
               end if;
               if usb_kbd(7) = '1' then
                  ps2_kbd_tmp(ps2_kbd_n) := x"F0";
                  ps2_kbd_n := ps2_kbd_n + 1;
               end if;
               if ps2_kbd_code /= x"0000" then
                  ps2_kbd_tmp(ps2_kbd_n) := ps2_kbd_code(7 downto 0);
                  ps2_kbd_n := ps2_kbd_n + 1;
               end if;
               -- drop the event if the queue cannot hold all of its bytes
               if ps2_kbd_n > 0 and ps2_queue_n + ps2_kbd_n <= ps2_queue_depth then
                  for i in 0 to 2 loop
                     if i < ps2_kbd_n then
                        ps2_queue(ps2_queue_n + i) <= ps2_kbd_tmp(i);
                     end if;
                  end loop;
                  ps2_queue_n <= ps2_queue_n + ps2_kbd_n;
               end if;
            elsif ps2_rxdone = '0' and ps2_queue_n > 0 then
               ps2_scancode <= ps2_queue(0);
               for i in 0 to ps2_queue_depth - 2 loop
                  ps2_queue(i) <= ps2_queue(i + 1);
               end loop;
               ps2_queue_n <= ps2_queue_n - 1;
               ps2_rxdone <= '1';
            end if;

         end if;
      end if;

   end process;


end implementation;

