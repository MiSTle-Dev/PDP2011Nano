
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

component altera_gpio_lite is
   generic (
      PIN_TYPE                                 : string  := "output";
      SIZE                                     : integer := 4;
      REGISTER_MODE                            : string  := "bypass";
      BUFFER_TYPE                              : string  := "single-ended";
      ASYNC_MODE                               : string  := "none";
      SYNC_MODE                                : string  := "none";
      BUS_HOLD                                 : string  := "false";
      OPEN_DRAIN_OUTPUT                        : string  := "false";
      ENABLE_OE_PORT                           : string  := "false";
      ENABLE_NSLEEP_PORT                       : string  := "false";
      ENABLE_CLOCK_ENA_PORT                    : string  := "false";
      SET_REGISTER_OUTPUTS_HIGH                : string  := "false";
      INVERT_OUTPUT                            : string  := "false";
      INVERT_INPUT_CLOCK                       : string  := "false";
      USE_ONE_REG_TO_DRIVE_OE                  : string  := "false";
      USE_DDIO_REG_TO_DRIVE_OE                 : string  := "false";
      USE_ADVANCED_DDR_FEATURES                : string  := "false";
      USE_ADVANCED_DDR_FEATURES_FOR_INPUT_ONLY : string  := "false";
      ENABLE_OE_HALF_CYCLE_DELAY               : string  := "true";
      INVERT_CLKDIV_INPUT_CLOCK                : string  := "false";
      ENABLE_PHASE_INVERT_CTRL_PORT            : string  := "false";
      ENABLE_HR_CLOCK                          : string  := "false";
      INVERT_OUTPUT_CLOCK                      : string  := "false";
      INVERT_OE_INCLOCK                        : string  := "false";
      ENABLE_PHASE_DETECTOR_FOR_CK             : string  := "false"
   );
   port (
      dout            : out   std_logic_vector(15 downto 0);
      din             : in    std_logic_vector(15 downto 0) := (others => 'X');
      pad_io          : inout std_logic_vector(15 downto 0) := (others => 'X');
      oe              : in    std_logic_vector(15 downto 0) := (others => 'X');
      inclocken       : in    std_logic := 'X';
      outclocken      : in    std_logic := 'X';
      inclock         : in    std_logic := 'X';
      fr_clock        : out   std_logic_vector(15 downto 0);
      hr_clock        : out   std_logic;
      invert_hr_clock : in    std_logic := 'X';
      outclock        : in    std_logic := 'X';
      phy_mem_clock   : in    std_logic := 'X';
      mimic_clock     : out   std_logic_vector(15 downto 0);
      pad_io_b        : inout std_logic_vector(15 downto 0) := (others => 'X');
      pad_in          : in    std_logic_vector(15 downto 0) := (others => 'X');
      pad_in_b        : in    std_logic_vector(15 downto 0) := (others => 'X');
      pad_out         : out   std_logic_vector(15 downto 0);
      pad_out_b       : out   std_logic_vector(15 downto 0);
      aset            : in    std_logic := 'X';
      aclr            : in    std_logic := 'X';
      sclr            : in    std_logic := 'X';
      nsleep          : in    std_logic_vector(15 downto 0) := (others => 'X')
   );
end component altera_gpio_lite;

signal r1, r2 : std_logic_vector(15 downto 0);      -- synchronizer registers
signal unsynced : std_logic_vector(15 downto 0);
signal din : std_logic_vector(15 downto 0);

begin

gpib_buffer_inst : component altera_gpio_lite
   generic map (
      PIN_TYPE                                 => "bidir",
      SIZE                                     => 16,
      REGISTER_MODE                            => "bypass",
      BUFFER_TYPE                              => "single-ended",
      ASYNC_MODE                               => "none",
      SYNC_MODE                                => "none",
      BUS_HOLD                                 => "false",
      OPEN_DRAIN_OUTPUT                        => "true",      -- gpib bus has opendrain outputs
      ENABLE_OE_PORT                           => "true",
      ENABLE_NSLEEP_PORT                       => "false",
      ENABLE_CLOCK_ENA_PORT                    => "false",
      SET_REGISTER_OUTPUTS_HIGH                => "false",
      INVERT_OUTPUT                            => "true",      -- gpib bus is negative logic
      INVERT_INPUT_CLOCK                       => "false",
      USE_ONE_REG_TO_DRIVE_OE                  => "false",
      USE_DDIO_REG_TO_DRIVE_OE                 => "false",
      USE_ADVANCED_DDR_FEATURES                => "false",
      USE_ADVANCED_DDR_FEATURES_FOR_INPUT_ONLY => "false",
      ENABLE_OE_HALF_CYCLE_DELAY               => "true",
      INVERT_CLKDIV_INPUT_CLOCK                => "false",
      ENABLE_PHASE_INVERT_CTRL_PORT            => "false",
      ENABLE_HR_CLOCK                          => "false",
      INVERT_OUTPUT_CLOCK                      => "false",
      INVERT_OE_INCLOCK                        => "false",
      ENABLE_PHASE_DETECTOR_FOR_CK             => "false"
   )
   port map (
      dout            => unsynced,
      din             => eoi_in & atn_in & ifc_in & ren_in & srq_in & nrfd_in & dav_in & ndac_in & dio_in,
      pad_io(15)          => eoi,
      pad_io(14)          => atn,
      pad_io(13)          => ifc,
      pad_io(12)          => ren,
      pad_io(11)          => srq,
      pad_io(10)          => nrfd,
      pad_io(9)          => dav,
      pad_io(8)          => ndac,
      pad_io(7 downto 0)          => dio,
      oe(15 downto 8) => (others => '1'),
      oe(7 downto 0) => (others => oe),
      inclocken       => '1',
      outclocken      => '1',
      inclock         => '0',
      fr_clock        => open,
      hr_clock        => open,
      invert_hr_clock => '0',
      outclock        => '0',
      phy_mem_clock   => '0',
      mimic_clock     => open,
      pad_io_b        => open,
      pad_in          => (others => '0'),
      pad_in_b        => (others => '0'),
      pad_out         => open,
      pad_out_b       => open,
      aset            => '0',
      aclr            => '0',
      sclr            => '0',
      nsleep          => (others => '0')
   );

   eoi_out <= not r2(15);
   atn_out <= not r2(14);
   ifc_out <= not r2(13);
   ren_out <= not r2(12);
   srq_out <= not r2(11);
   nrfd_out <= not r2(10);
   dav_out <= not r2(9);
   ndac_out <= not r2(8);
   dio_out <= not r2(7 downto 0);

   sync: process(clk)
   begin
      if clk = '1' and clk'event then
         r1 <= unsynced;
         r2 <= r1;
      end if;
   end process;

end rtl;



