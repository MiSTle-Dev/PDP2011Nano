
--
-- Copyright (c) 2008-2025 Jan Secker and Sytse van Slooten
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

entity ibv11 is
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

      eoi : inout std_logic;
      atn : inout std_logic;
      ifc : inout std_logic;
      ren : inout std_logic;
      srq : inout std_logic;
      nrfd : inout std_logic;
      dav : inout std_logic;
      ndac : inout std_logic;
      dio : inout std_logic_vector(8 downto 1);

      have_ibv11 : in integer range 0 to 1 := 0;

      reset : in std_logic;

      clk50mhz : in std_logic;
      clk : in std_logic
   );
end ibv11;

architecture implementation of ibv11 is

-- IEEE488 controller
component ibv11_c
   port(
      atn_rcv : in std_logic;
      ifc_rcv : in std_logic;
      ren_rcv : in std_logic;
      dav_rcv : in std_logic;
      tcs : in std_logic;

      atn : out std_logic;
      assrt_nrfd : out std_logic;

      reset : in std_logic;
      clk : in std_logic
   );
end component;

-- IEEE488 Acceptor Handshake
component ibv11_ah
   port(
      dav_rcv : in std_logic;
      lon : in std_logic;
      write_to_ibd : in std_logic;
      read_from_ibd : in std_logic;
      acc : in std_logic;
      assrt_nrfd : in std_logic;
      ton : in std_logic;
      atn : in std_logic;

      lnr : buffer std_logic;
      ndac : buffer std_logic;
      nrfd : out std_logic;

      reset : in std_logic;
      clk : in std_logic
   );
end component;

-- IEEE488 Source Handshake
component ibv11_sh is
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
end component;

component ibv11_io is
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
end component;

-- bus interface
signal base_addr_match : std_logic;

-- interrupt system
type interrupt_state_type is (
   i_idle,
   i_req,
   i_wait
);

signal interrupt_state : interrupt_state_type := i_idle;
-- signal interrupt_trigger : std_logic := '0';
signal interrupt_trigger0 : std_logic := '0';
signal interrupt_trigger4 : std_logic := '0';
signal interrupt_trigger10 : std_logic := '0';
signal interrupt_trigger14 : std_logic := '0';

      -- ibs register --
signal ibs : std_logic_vector(15 downto 0);

      -- ibs, read only   --
signal ibs_er2 : std_logic;
signal ibs_er1 : std_logic;
signal ibs_cmd : std_logic;
signal ibs_tkr : std_logic;
signal ibs_lnr : std_logic;

      -- ibs read/write = control buffer
signal ibs_acc : std_logic;
signal ibs_ie : std_logic;
signal ibs_ton : std_logic;
signal ibs_lon : std_logic;
signal ibs_ibc : std_logic;
signal ibs_rem : std_logic;
signal ibs_eop : std_logic;
signal ibs_tcs : std_logic;

   -- ibd register   --
signal ibd : std_logic_vector(15 downto 0);

   -- ibd, read only   --
signal ibd_eoi : std_logic;
signal ibd_atn : std_logic;
signal ibd_ifc : std_logic;
signal ibd_ren : std_logic;
signal ibd_srq : std_logic;
signal ibd_nrfd : std_logic;
signal ibd_dav : std_logic;
signal ibd_ndac : std_logic;

   -- ibd read/write = command/talker output buffer
signal ibd_dio : std_logic_vector(8 downto 1) := "00000000";

   --instrument bus in
signal eoi_rcv : std_logic;
signal atn_rcv : std_logic;
signal ifc_rcv : std_logic;
signal ren_rcv : std_logic;
signal srq_rcv : std_logic;
signal nrfd_rcv : std_logic;
signal dav_rcv : std_logic;
signal ndac_rcv : std_logic;
signal dio_rcv : std_logic_vector(8 downto 1);

   --instrument bus out
signal ib_eoi : std_logic;
signal ib_atn : std_logic;
signal ib_ifc : std_logic;
signal ib_ren : std_logic;
signal ib_srq : std_logic;
signal ib_nrfd : std_logic;
signal ib_dav : std_logic;
signal ib_ndac : std_logic;
signal ib_dio : std_logic_vector(8 downto 1);
signal enb_xfer : std_logic := '1';

signal ifc_counter : integer range 0 to 10000;
signal ibc : std_logic;
signal tcs_counter : integer range 0 to 1000;

signal write_to_ibd : std_logic;
signal read_from_ibd : std_logic;
signal assrt_nrfd : std_logic;
signal er1 : std_logic := '0';
signal er2 : std_logic := '0';

begin

   ibv11_io0 : ibv11_io port map(
      eoi => eoi,
      atn => atn,
      ifc => ifc,
      ren => ren,
      srq => srq,
      nrfd => nrfd,
      dav => dav,
      ndac => ndac,
      dio => dio,

      eoi_in => ib_eoi,
      atn_in => ib_atn,
      ifc_in => ib_ifc,
      ren_in => ib_ren,
      srq_in => ib_srq,
      nrfd_in => ib_nrfd,
      dav_in => ib_dav,
      ndac_in => ib_ndac,
      dio_in => ib_dio,

      eoi_out => eoi_rcv,
      atn_out => atn_rcv,
      ifc_out => ifc_rcv,
      ren_out => ren_rcv,
      srq_out => srq_rcv,
      nrfd_out => nrfd_rcv,
      dav_out => dav_rcv,
      ndac_out => ndac_rcv,
      dio_out => dio_rcv,

      oe => enb_xfer,
      clk => clk
   );

   ibv11_controller : ibv11_c port map(
      atn_rcv => atn_rcv,
      ifc_rcv => ifc_rcv,
      ren_rcv => ren_rcv,
      dav_rcv => dav_rcv,
      tcs => ibs_tcs,

      atn => ib_atn,
      assrt_nrfd => assrt_nrfd,

      reset => reset,
      clk => clk
   );

   ibv11_source_handshake : ibv11_sh port map(
      dav_rcv => dav_rcv,
      write_to_ibd => write_to_ibd,
      atn_rcv => atn_rcv,
      ton => ibs_ton,
      atn => ib_atn,
      ndac_rcv => ndac_rcv,
      nrfd_rcv => nrfd_rcv,

      tkr => ibs_tkr,
      cmd => ibs_cmd,
      enb_xfer => enb_xfer,
      er2 => ibs_er2,
      dav => ib_dav,

      reset => reset,
      clk50mhz => clk50mhz
   );

   ibv11_acceptor_handshake : ibv11_ah port map(
      dav_rcv => dav_rcv,
      lon => ibs_lon,
      write_to_ibd => write_to_ibd,
      read_from_ibd => read_from_ibd,
      acc => ibs_acc,
      assrt_nrfd => assrt_nrfd,
      ton => ibs_ton,
      atn => atn_rcv,

      lnr => ibs_lnr,
      ndac => ib_ndac,
      nrfd => ib_nrfd,

      reset => reset,
      clk => clk
   );


   base_addr_match <= '1' when base_addr(17 downto 3) = bus_addr(17 downto 3) and have_ibv11 = 1 else '0';
   bus_addr_match <= base_addr_match;

   read_from_ibd <= '1' when base_addr_match = '1' and bus_control_dati = '1' and bus_addr(2 downto 1) = "01" else '0';
   write_to_ibd <= '1' when base_addr_match = '1' and (bus_control_dato = '1'or bus_control_datob = '1') and bus_addr(2 downto 1) = "01" else '0';

   ibs <= srq_rcv & ibs_er2 & ibs_er1 & '0' & '0' & ibs_cmd & ibs_tkr & ibs_lnr & ibs_acc & ibs_ie & ibs_ton & ibs_lon & ibs_ibc & ibs_rem & ibs_eop & ibs_tcs;
   ibd <= eoi_rcv & atn_rcv & ifc_rcv & ren_rcv & srq_rcv &  not nrfd_rcv & dav_rcv &  not ndac_rcv & dio_rcv;

   ib_srq <= '0';                      -- ibv11 will not set srq for now, there's no gpib client software in minc
   ib_eoi <= ibs_eop;
   ib_ifc <= ibc;
   ib_ren <= ibs_rem;
   ib_dio <= ibd_dio;

   ibs_er1 <= '0';                     -- er1 logic not implemented for now.

   process(clk, base_addr_match, reset, have_ibv11)
   begin
      if clk = '1' and clk'event then
         if have_ibv11 = 1 then
            if reset = '1' then
               interrupt_state <= i_idle;
               br <= '0';
            else

               case interrupt_state is

                  when i_idle =>
                     br <= '0';

                     if ibs_er2 = '0' and ibs_er1 = '0' then
                        interrupt_trigger0 <= '0';
                     end if;
                     if srq_rcv = '0' then
                        interrupt_trigger4 <= '0';
                     end if;
                     if ibs_tkr = '0' and ibs_cmd = '0' then
                        interrupt_trigger10 <= '0';
                     end if;
                     if ibs_lnr = '0' then
                        interrupt_trigger14 <= '0';
                     end if;

                     if ibs_ie = '1' then

                        if (ibs_er2 = '1' or ibs_er1 = '1') and interrupt_trigger0 = '0' then
                           interrupt_state <= i_req;
                           br <= '1';
                        elsif srq_rcv = '1' and interrupt_trigger4 = '0' then
                           interrupt_state <= i_req;
                           br <= '1';
                        elsif (ibs_tkr = '1' or ibs_cmd = '1') and interrupt_trigger10 = '0' then
                           interrupt_state <= i_req;
                           br <= '1';
                        elsif ibs_lnr = '1' and interrupt_trigger14 = '0' then
                           interrupt_state <= i_req;
                           br <= '1';
                        end if;

                     else
                        interrupt_trigger0 <= '0';
                        interrupt_trigger4 <= '0';
                        interrupt_trigger10 <= '0';
                        interrupt_trigger14 <= '0';
                     end if;

                  when i_req =>
                     if bg = '1' then
                        if (ibs_er2 = '1' or ibs_er1 = '1') and interrupt_trigger0 = '0' then
                           int_vector <= ivec;
                           br <= '0';
                           interrupt_state <= i_wait;
                           interrupt_trigger0 <= '1';
                        elsif srq_rcv = '1' and interrupt_trigger4 = '0' then
                           int_vector <= ivec + o"004";
                           br <= '0';
                           interrupt_state <= i_wait;
                           interrupt_trigger4 <= '1';
                        elsif (ibs_tkr = '1' or ibs_cmd = '1') and interrupt_trigger10 = '0' then
                           int_vector <= ivec + o"010";
                           br <= '0';
                           interrupt_state <= i_wait;
                           interrupt_trigger10 <= '1';
                        else  -- if ibs_lnr = '1' and interrupt_trigger14 = '0' then
                           int_vector <= ivec + o"014";
                           br <= '0';
                           interrupt_state <= i_wait;
                           interrupt_trigger14 <= '1';
                        end if;
                     end if;

                  when i_wait =>
                     if bg = '0' then
                        interrupt_state <= i_idle;
                     end if;

                   when others =>
                     interrupt_state <= i_idle;

               end case;

            end if;

         else
            br <= '0';
         end if;



         if have_ibv11 = 1 then
            if reset = '1' or ifc_rcv = '1' then
               ibs_acc <= '0';
               ibs_ton <= '0';
               ibs_lon <= '0';
               ibs_ibc <= '0';
               ibs_rem <= '0';
               ibs_eop <= '0';
               ibs_tcs <= '0';
            end if;
            if reset = '1' then
               ibd_dio <= (others => '0');
               ibs_ie <= '0';
            end if;


            if base_addr_match = '1' and bus_control_dati = '1' then
               case bus_addr(2 downto 1) is
                  when "00" =>
                     bus_dati <= ibs;
                  when "01" =>
                     bus_dati <= ibd;
                  when others =>
                     bus_dati <= (others => '0');
               end case;
            end if;

            if base_addr_match = '1' and bus_control_dato = '1' then

               if bus_control_datob = '0' or (bus_control_datob = '1' and bus_addr(0) = '0') then
                  case bus_addr(2 downto 1) is
                     when "00" =>
                        ibs_acc <= bus_dato(7);
                        ibs_ie <= bus_dato(6);
                        ibs_ton <= bus_dato(5);
                        ibs_lon <= bus_dato(4);
                        if bus_dato(3) = '1'then
                           ibc <= '1';
                           ifc_counter <= 200;      -- ifc =
                        end if;
                        ibs_rem <= bus_dato(2);
                        ibs_eop <= bus_dato(1);
                        ibs_tcs <= bus_dato(0);

                     when "01" =>
                        ibd_dio <= bus_dato(7 downto 0);
                     when others =>
                        null;
                  end case;
               end if;

               if bus_control_datob = '0' or (bus_control_datob = '1' and bus_addr(0) = '1') then
                  case bus_addr(2 downto 1) is
                     when "00" =>
                     when "01" =>
                     when others =>
                        null;
                  end case;
               end if;

            end if;

            if ifc_counter > 1 then
               ifc_counter <= ifc_counter - 1;
            elsif ifc_counter = 1 then
               ibc <= '0';
               tcs_counter <= 5;   -- t =
               ifc_counter <= 0;
            end if;

            if tcs_counter > 1 then
               tcs_counter <= tcs_counter -1;
            elsif tcs_counter = 1 then
               ibs_tcs <= '1';
               tcs_counter <= 0;
            end if;


         end if;

         ibs_ibc <= ibc;

     end if;

   end process;

end implementation;
