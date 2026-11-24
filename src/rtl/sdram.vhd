
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
-- 2026 adjusted for GW2AR TN20k Stefan Voss
-- $Revision$

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity sdram is
   generic(
      sdram_data_width : positive := 32
   );
   port(
      addr: in std_logic_vector(21 downto 0);
      dati: out std_logic_vector(15 downto 0);
      dato: in std_logic_vector(15 downto 0);
      control_dati : in std_logic;
      control_dato : in std_logic;
      control_datob : in std_logic;
      dram_match : in std_logic;
      mmu_ready : in std_logic;
      
      dram_addr : out std_logic_vector(14 - sdram_data_width / 8 downto 0);
      dram_dq : inout std_logic_vector(sdram_data_width - 1 downto 0);
      dram_dqm : out std_logic_vector(sdram_data_width / 8 - 1 downto 0);
      O_sdram_ba : out std_logic_vector(1 downto 0);
      dram_ras_n : out std_logic;
      dram_cas_n : out std_logic;
      dram_we_n : out std_logic;
      dram_cs_n : out std_logic;
      dram_clk : out std_logic;
      dram_cke : out std_logic;
      
      reset : in std_logic;
      ext_reset : in std_logic;
      cpureset : out std_logic;
      cpuclk : out std_logic;
      c0 : in std_logic;
      clk_25 : in std_logic
   );
end sdram;

architecture implementation of sdram is

   component ODDR
      generic (
         TXCLK_POL : bit := '0';
         INIT : std_logic := '0'
      );
      port (
         Q0 : out std_logic;
         Q1 : out std_logic;
         D0 : in std_logic;
         D1 : in std_logic;
         TX : in std_logic;
         CLK : in std_logic
      );
   end component;

signal dram_refresh_count : integer range 0 to 255;
signal dram_row_addr : std_logic_vector(dram_addr'range);
signal dram_column_addr : std_logic_vector(dram_addr'range);
signal dram_bank_addr : std_logic_vector(1 downto 0);
signal dram_write_data : std_logic_vector(dram_dq'range);
signal dram_write_dqm : std_logic_vector(dram_dqm'range);
signal dram_read_data : std_logic_vector(15 downto 0);
signal cpuresetlength : integer range 0 to 126 := 63;
signal dram_addr_bit1 : std_logic;

signal dram_counter : integer range 0 to 32767;
signal dram_wait : integer range 0 to 15;

type dram_fsm_type is (
   dram_init,
   dram_poweron,
   dram_pwron_pre, dram_pwron_prew,
   dram_pwron_ref, dram_pwron_refw,
   dram_pwron_mrs, dram_pwron_mrsw,
   dram_c1,
   dram_c2,
   dram_c3,
   dram_c4,
   dram_c5,
   dram_c6,
   dram_c7,
   dram_c8,
   dram_c9,
   dram_c10,
   dram_c11,
   dram_c12,
   dram_c13,
   dram_c14,
   dram_idle
);
signal dram_fsm : dram_fsm_type := dram_init;
signal reset_c0_s1 : std_logic := '1';
signal reset_c0_s2 : std_logic := '1';
signal pix_s1 : std_logic := '0';
signal pix_s2 : std_logic := '0';
signal phase_cnt : std_logic_vector(1 downto 0) := (others => '0');
signal phase_locked : std_logic := '0';
signal fsm_run : std_logic := '0';
signal fsm_reset : std_logic;

begin

   phase_align : process(c0)
   begin
      if rising_edge(c0) then
         reset_c0_s1 <= reset;
         reset_c0_s2 <= reset_c0_s1;
         pix_s1 <= clk_25;
         pix_s2 <= pix_s1;

         if reset_c0_s2 = '1' then
            phase_locked <= '0';
            fsm_run <= '0';
         else
            if pix_s1 = '1' and pix_s2 = '0' then
               phase_cnt <= (others => '0');
               phase_locked <= '1';
            else
               phase_cnt <= phase_cnt + 1;
            end if;
            if phase_locked = '1' and phase_cnt = 0 then
               fsm_run <= '1';
            end if;
         end if;
      end if;
   end process;

   dram_cke <= '1';

   assert sdram_data_width = 16 or sdram_data_width = 32
      report "sdram_data_width must be 16 or 32"
      severity failure;

   sdram_16bit: if sdram_data_width = 16 generate
      fsm_reset <= reset;
      dram_row_addr <= "00" & addr(19 downto 9);
      dram_bank_addr <= addr(21 downto 20);
      dram_column_addr <= "00110" & addr(8 downto 1);
      dram_write_data <= dato;
      dram_write_dqm <= "00" when control_datob = '0' else
                        "10" when addr(0) = '0' else "01";
      dram_read_data <= dram_dq;
   end generate;

   sdram_32bit: if sdram_data_width = 32 generate
      fsm_reset <= reset_c0_s2;
      dram_row_addr <= "0" & addr(19 downto 10);
      dram_bank_addr <= addr(21 downto 20);
      dram_column_addr <= "110" & addr(9 downto 2);
      dram_write_data <= dato & dato;
      dram_read_data <= dram_dq(15 downto 0) when dram_addr_bit1 = '0' else
                        dram_dq(31 downto 16);

      process(all)
      begin
         if control_datob = '1' then
            case addr(1 downto 0) is
               when "00" => dram_write_dqm <= "1110";
               when "01" => dram_write_dqm <= "1101";
               when "10" => dram_write_dqm <= "1011";
               when others => dram_write_dqm <= "0111";
            end case;
         elsif addr(1) = '0' then
            dram_write_dqm <= "1100";
         else
            dram_write_dqm <= "0011";
         end if;
      end process;
   end generate;

   process(c0)
   begin
      if rising_edge(c0) then
         if fsm_reset = '1' or fsm_run = '0' then
            dram_fsm <= dram_init;
            dram_cs_n <= '0';
            dram_ras_n <= '1';
            dram_cas_n <= '1';
            dram_we_n <= '1';
            dram_addr <= (others => '0');
            dram_dqm <= (others => '0');
            O_sdram_ba <= "00";

            cpuclk <= '0';
            cpureset <= '1';
            cpuresetlength <= 126;
            dram_refresh_count <= 1;
         else

            case dram_fsm is

               when dram_init =>
                  dram_cs_n <= '0';
                  dram_ras_n <= '1';
                  dram_cas_n <= '1';
                  dram_we_n <= '1';
                  dram_addr <= (others => '0');
                  dram_dqm <= (others => '0');

                  O_sdram_ba <= "00";

                  cpureset <= '1';
                  cpuresetlength <= 126;
                  dram_counter <= 32767;
                  dram_fsm <= dram_poweron;

               when dram_poweron =>
                  dram_cs_n <= '0';
                  dram_ras_n <= '1';
                  dram_cas_n <= '1';
                  dram_we_n <= '1';
                  dram_addr <= (others => '0');
                  dram_dqm <= (others => '0');

                  O_sdram_ba <= "00";

                  if dram_counter = 0 then
                     dram_fsm <= dram_pwron_pre;
                  else
                     dram_counter <= dram_counter - 1;
                  end if;

               when dram_pwron_pre =>
                  dram_cs_n <= '0';
                  dram_ras_n <= '0';
                  dram_cas_n <= '1';
                  dram_we_n <= '0';
                  dram_addr(10) <= '1';

                  O_sdram_ba <= "00";
                  dram_addr(9 downto 0) <= (others => '0');
                  dram_dqm <= (others => '0');

                  dram_wait <= 4;
                  dram_fsm <= dram_pwron_prew;

               when dram_pwron_prew =>
                  dram_cs_n <= '1';
                  if dram_wait = 0 then
                     dram_fsm <= dram_pwron_ref;
                     dram_counter <= 20;
                  else
                     dram_wait <= dram_wait - 1;
                  end if;

               when dram_pwron_ref =>
                  dram_cs_n <= '0';
                  dram_ras_n <= '0';
                  dram_cas_n <= '0';
                  dram_we_n <= '1';
                  dram_addr <= (others => '0');
                  dram_dqm <= (others => '0');

                  O_sdram_ba <= "00";

                  dram_wait <= 15;
                  dram_fsm <= dram_pwron_refw;

               when dram_pwron_refw =>
                  dram_cs_n <= '1';
                  if dram_wait = 0 then
                     if dram_counter = 0 then
                        dram_fsm <= dram_pwron_mrs;
                     else
                        dram_counter <= dram_counter - 1;
                        dram_fsm <= dram_pwron_ref;
                     end if;
                  else
                     dram_wait <= dram_wait - 1;
                  end if;

               when dram_pwron_mrs =>
                  dram_cs_n <= '0';
                  dram_ras_n <= '0';
                  dram_cas_n <= '0';
                  dram_we_n <= '0';

                  dram_addr(dram_addr'high downto 7) <= (others => '0');
                  dram_addr(6 downto 4) <= "011";          -- cas length 3
                  dram_addr(3) <= '0';                     -- sequential
                  dram_addr(2 downto 0) <= "000";          -- length 0
                  dram_dqm <= (others => '0');

                  O_sdram_ba <= "00";

                  dram_wait <= 4;
                  dram_fsm <= dram_pwron_mrsw;

               when dram_pwron_mrsw =>
                  dram_cs_n <= '1';
                  if dram_wait = 0 then
                     dram_fsm <= dram_idle;
                  else
                     dram_wait <= dram_wait - 1;
                  end if;

               when dram_idle =>
                  dram_cs_n <= '1';
                  dram_ras_n <= '1';
                  dram_cas_n <= '1';
                  dram_we_n <= '1';
                  dram_addr(10) <= '0';

                  O_sdram_ba <= "00";
                  dram_addr(9 downto 0) <= (others => '0');
                  dram_dqm <= (others => '0');

                  dram_fsm <= dram_c1;

               when dram_c1 =>

                  if cpuresetlength = 0 then
                     cpureset <= '0';
                  else
                     cpuresetlength <= cpuresetlength - 1;
                  end if;
                  if ext_reset = '1' then
                     cpuresetlength <= 126;
                     cpureset <= '1';
                  end if;

               cpuclk <= '1';

                  dram_fsm <= dram_c2;

               when dram_c2 =>
                  dram_dq <= (others => 'Z');
                  dram_fsm <= dram_c3;

               when dram_c3 =>
                  dram_fsm <= dram_c4;         -- 5, for more agressive timing

               when dram_c4 =>
                  dram_fsm <= dram_c5;

               when dram_c5 =>
                  dram_fsm <= dram_c6;

               when dram_c6 =>

                  if mmu_ready = '1' then
                     -- read, t1-t2

                     if dram_match = '1' and control_dati = '1' then
                        -- activate command
                        dram_cs_n <= '0';
                        dram_ras_n <= '0';
                        dram_cas_n <= '1';
                        dram_we_n <= '1';
                        dram_addr <= dram_row_addr;
                        dram_dqm <= (others => '0');

                        O_sdram_ba <= dram_bank_addr;
                     end if;

                     -- write, t1-t2
                     if dram_match = '1' and control_dato = '1' then
                        -- activate command
                        dram_cs_n <= '0';
                        dram_ras_n <= '0';
                        dram_cas_n <= '1';
                        dram_we_n <= '1';
                        dram_addr <= dram_row_addr;
                        dram_dqm <= (others => '0');

                        O_sdram_ba <= dram_bank_addr;
                     end if;

                     if dram_match = '0' or (control_dato = '0' and control_dati = '0') then
                        -- auto refresh command
                        if dram_refresh_count = 0 then
                           dram_cs_n <= '0';
                           dram_ras_n <= '0';
                           dram_cas_n <= '0';
                           dram_we_n <= '1';
                           dram_refresh_count <= 255;
                        else
                           dram_refresh_count <= dram_refresh_count - 1;
                        end if;
                     end if;

                     dram_fsm <= dram_c7;
                  end if;

               when dram_c7 =>
                  -- t2-t3 - set nop command
                  dram_cs_n <= '1';
                  dram_ras_n <= '1';
                  dram_cas_n <= '1';
                  dram_we_n <= '1';

                  dram_fsm <= dram_c8;

               when dram_c8 =>

                  -- read, t3-t4
                  if dram_match = '1' and control_dati = '1' then
                     -- reada command
                     dram_cs_n <= '0';
                     dram_ras_n <= '1';
                     dram_cas_n <= '0';
                     dram_we_n <= '1';
                     dram_addr <= dram_column_addr;
                     dram_dqm <= (others => '0');

                     O_sdram_ba <= dram_bank_addr;

                  end if;

                  -- write, t3-t4
                  if dram_match = '1' and control_dato = '1' then
                     -- writea command
                     dram_cs_n <= '0';
                     dram_ras_n <= '1';
                     dram_cas_n <= '0';
                     dram_we_n <= '0';
                     dram_addr <= dram_column_addr;
                     dram_dqm <= dram_write_dqm;
                     dram_dq <= dram_write_data;
                     O_sdram_ba <= dram_bank_addr;
                  end if;

                  dram_fsm <= dram_c9;
                  dram_addr_bit1 <= addr(1);

               cpuclk <= '0';

               when dram_c9 =>

                  -- read/write, t4-t5 - set nop command and deselect
                  dram_cs_n <= '1';
                  dram_ras_n <= '1';
                  dram_cas_n <= '1';
                  dram_we_n <= '1';

                  dram_fsm <= dram_c10;

               when dram_c10 =>
                  dram_fsm <= dram_c11;

               when dram_c11 =>
                  dram_fsm <= dram_c12;

               when dram_c12 =>
                  dram_fsm <= dram_c13;

               when dram_c13 =>
                  -- read, t5-t6
                  if dram_match = '1' and control_dati = '1' then
                     dati <= dram_read_data;
                  end if;
                  dram_fsm <= dram_c14;

               when dram_c14 =>
                  dram_fsm <= dram_c1;

               when others =>
                  null;

            end case;

         end if;
      end if;
   end process;

oddr_inst: ODDR
generic map(
    TXCLK_POL => '0',
    INIT => '0'
   )
port map
   (
    Q0 => dram_clk,             -- DDR output clock to SDRAM pin
    Q1 => open,
    D0 => '0',               -- value for one half-cycle
    D1 => '1',               -- value for the other half-cycle
    TX => '0',               -- output always enabled
    CLK => c0
);

end implementation;
