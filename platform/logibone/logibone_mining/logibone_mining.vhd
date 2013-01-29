----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    14:14:22 06/21/2012 
-- Design Name: 
-- Module Name:    spartcam_beaglebone - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

library work ;
use work.utils_pack.all ;
use work.peripheral_pack.all ;
use work.interface_pack.all ;
-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity logibone_mining is
port( OSC_FPGA : in std_logic;
		PB : in std_logic_vector(1 downto 0);
		LED : out std_logic_vector(1 downto 0);	
		
		--gpmc interface
		GPMC_CSN : in std_logic_vector(2 downto 0);
		GPMC_WEN, GPMC_OEN, GPMC_ADVN, GPMC_CLK, GPMC_BE0N, GPMC_BE1N:	in std_logic;
		GPMC_AD :	inout std_logic_vector(15 downto 0)	
);
end logibone_mining;

architecture Behavioral of logibone_mining is

	COMPONENT clock_gen
	PORT(
		CLK_IN1 : IN std_logic;          
		CLK_OUT1 : OUT std_logic;
		CLK_OUT2 : OUT std_logic;
		CLK_OUT3 : OUT std_logic;
		LOCKED : OUT std_logic
		);
	END COMPONENT;
	
	COMPONENT miner
	generic ( DEPTH : integer );
	PORT(
		clk : IN std_logic;
		step : IN std_logic_vector(5 downto 0);
		data : IN std_logic_vector(95 downto 0);
		state : IN  STD_LOGIC_VECTOR (255 downto 0);
		nonce : IN std_logic_vector(31 downto 0);          
		hit : OUT std_logic
		);
	END COMPONENT;



	
	signal clk_sys, clk_100, clk_miner, clk_locked : std_logic ;
	signal resetn , sys_resetn : std_logic ;
	
	signal counter_output : std_logic_vector(31 downto 0);
	signal fifo_output : std_logic_vector(15 downto 0);
	signal fifo_input : std_logic_vector(15 downto 0);
	signal latch_output : std_logic_vector(15 downto 0);
	signal fifoB_wr, fifoA_rd, fifoA_rd_old, fifoA_empty, fifoA_full, fifoB_empty, fifoB_full : std_logic ;
	signal fifo_full_rising_edge, fifo_full_old : std_logic ;
	signal bus_data_in, bus_data_out : std_logic_vector(15 downto 0);
	signal bus_fifo_out, bus_latch_out, state_register : std_logic_vector(15 downto 0);
	signal bus_addr : std_logic_vector(15 downto 0);
	signal bus_wr, bus_rd, bus_cs : std_logic ;
	signal cs_fifo, cs_latch : std_logic ;


	constant DEPTH : integer := 1;
	signal data : std_logic_vector(95 downto 0);
	signal state : std_logic_vector(255 downto 0);
	signal nonce, currnonce : std_logic_vector(31 downto 0);
	signal step : std_logic_vector(5 downto 0) := "000000";
	signal hit, hit_latched : std_logic;
	signal load : std_logic_vector(335 downto 0);
	signal loadctr : std_logic_vector(5 downto 0);
	signal loading : std_logic := '0';
	signal txdata : std_logic_vector(48 downto 0);
	signal txwidth : std_logic_vector(5 downto 0);
	signal result_latched : std_logic_vector(31 downto 0) ;
	signal en_counter : std_logic ;
	signal count : std_logic_vector(1 downto 0);
	signal toggle : std_logic ;
begin
	
	resetn <= PB(0) ;
	sys_clocks_gen: clock_gen 
	PORT MAP(
		CLK_IN1 => OSC_FPGA,
		CLK_OUT1 => clk_100,
		CLK_OUT2 => clk_sys,--120Mhz system clock
		CLK_OUT3 => clk_miner, --60mhz miner clock
		LOCKED => clk_locked
	);


	reset0: reset_generator 
	generic map(HOLD_0 => 1000)
	port map(clk => clk_sys, 
		resetn => resetn ,
		resetn_0 => sys_resetn
	 );


divider : simple_counter 
	 generic map(NBIT => 32)
    port map( clk => clk_sys, 
           resetn => sys_resetn, 
           sraz => '0',
           en => '1',
			  load => '0' ,
			  E => X"00000000",
			  Q => counter_output
			  );
LED(0) <= counter_output(24);


mem_interface0 : muxed_addr_interface
generic map(ADDR_WIDTH => 16 , DATA_WIDTH =>  16)
port map(clk => clk_sys ,
	  resetn => sys_resetn ,
	  data	=> GPMC_AD,
	  wrn => GPMC_WEN, oen => GPMC_OEN, addr_en_n => GPMC_ADVN, csn => GPMC_CSN(1),
	  data_bus_out	=> bus_data_out,
	  data_bus_in	=> bus_data_in ,
	  addr_bus	=> bus_addr, 
	  wr => bus_wr , rd => bus_rd 
);

cs_fifo <= '1' when bus_addr(15 downto 3) = "0000000000000" else
			  '0' ;
cs_latch <= '1' when bus_addr(15 downto 3) = "0000000000001" else
			  '0' ;				  

bus_data_in <= bus_fifo_out when cs_fifo = '1' else
					bus_latch_out when cs_latch = '1' else
					(others => '1');

state_latch :latch_peripheral
generic map(ADDR_WIDTH => 16,  WIDTH	=> 16)
port map(
	clk => clk_sys, resetn => sys_resetn,
	addr_bus => bus_addr,
	wr_bus => bus_wr, rd_bus => bus_rd, cs_bus => cs_latch,
	data_bus_in	=> bus_data_out,
	data_bus_out => bus_latch_out,
	latch_input => state_register,
	latch_output => open
);


bi_fifo0 : fifo_peripheral 
		generic map(ADDR_WIDTH => 16,WIDTH => 16, SIZE => 1024, BURST_SIZE => 4)--16384)
		port map(
			clk => clk_sys,
			resetn => sys_resetn,
			addr_bus => bus_addr,
			wr_bus => bus_wr,
			rd_bus => bus_rd,
			cs_bus => cs_fifo,
			wrB => fifoB_wr,
			rdA => fifoA_rd,
			data_bus_in => bus_data_out,
			data_bus_out => bus_fifo_out,
			inputB => fifo_input, 
			outputA => fifo_output,
			emptyA => fifoA_empty,
			fullA => fifoA_full,
			emptyB => fifoB_empty,
			fullB => fifoB_full
		);
		
		miner0: miner
	   generic map ( DEPTH => DEPTH )
		port map (
			clk => clk_miner,
			step => step,
			data => data,
			state => state,
			nonce => nonce,
			hit => hit
		);
		
	currnonce <= nonce - 2 * 2 ** DEPTH;	
	
	fifoA_rd <= toggle ;
	process(clk_miner, sys_resetn)
	begin
		if sys_resetn = '0' then
			toggle <= '0';
			loadctr <= "000000" ;
			state <= (others => '0');
			step <= (others => '0') ;
			nonce <= x"00000000";
			loading <= '0' ;
		elsif rising_edge(clk_miner) then
		
			step <= step + 1;
			if conv_integer(step) = 2 ** (6 - DEPTH) - 1 then
				step <= "000000";
				nonce <= nonce + 1;
			end if;
			if loading = '1' and toggle = '1' then
				if loadctr = "010101" then --21 load on last
					state <= load(335 downto 80);
					data <= load(79 downto 0) & fifo_output(15 downto 0); -- last data to load
					nonce <= x"00000000";
					loadctr <= (others => '0');
					loading <= '0' ;
				else
					load(335 downto 16) <= load(319 downto 0);
					load(15 downto 0) <= fifo_output; -- loading data from fifo, needs to assert fifo_rd ...
					loadctr <= loadctr + 1; -- increase
					loading <= '1' ;
				end if;
				toggle <= '0' ;
			elsif fifoA_empty = '0' and toggle = '0' then
				loading <= '1' ;
				toggle <= '1' ;
			end if;
		end if;
	end process;	
		
	-- manage state register
	process(clk_miner, sys_resetn)
	begin
		if resetn = '0' then
			state_register <= (others => '0') ;
			hit_latched <= '0' ;
		elsif clk_miner'event and clk_miner = '1' then
			state_register(15 downto 10) <= step ;
			state_register(9 downto 1) <= nonce(31 downto  23);
			if loading = '1' then
				state_register(0) <= '0' ;
				hit_latched <= '0' ;
			elsif nonce = X"ffffffff" and  step = "000000"then
				state_register(0) <= '1' ;
			elsif hit = '1' then
				hit_latched <= '1' ;
			end if ;
		end if ;
	end process ;
	
	result_latch : generic_latch 
	 generic map(NBIT => 32)
    port map ( clk => clk_miner,
           resetn => sys_resetn,
           sraz => '0' ,
           en => hit ,
           d => currnonce, 
           q => result_latched );
			  
			  
	shift_words : simple_counter
	 generic map(NBIT => 2)
    Port map( clk => clk_miner, 
           resetn => sys_resetn,
           sraz => loading ,
           en => en_counter,
			  load => '0' ,
			  E => "00",
           Q => count 
			  );
			  
	en_counter <= '1' when hit = '1' else 
					  '1' when count > 0 else
					  '0' ;
					  
	fifo_input <= result_latched(15 downto 0) when count(1) = '0' else
						result_latched(31 downto 16) ;
						
	fifoB_wr	<= count(0) ;
						
	LED(1) <= hit_latched ;	
										
					
end Behavioral;

