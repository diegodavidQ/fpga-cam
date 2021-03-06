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
use work.filter_pack.all ;
use work.image_pack.all ;
use work.feature_pack.all ;
-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity logibone_harris is
port( OSC_FPGA : in std_logic;
		PB : in std_logic_vector(1 downto 0);
		LED : out std_logic_vector(1 downto 0);	
		
		--gpmc interface
		GPMC_CSN : in std_logic_vector(2 downto 0);
		GPMC_WEN, GPMC_OEN, GPMC_ADVN, GPMC_CLK, GPMC_BE0N, GPMC_BE1N:	in std_logic;
		GPMC_AD :	inout std_logic_vector(15 downto 0)	
);
end logibone_harris;

architecture Behavioral of logibone_harris is

	COMPONENT clock_gen
	PORT(
		CLK_IN1 : IN std_logic;          
		CLK_OUT1 : OUT std_logic;
		CLK_OUT2 : OUT std_logic;
		CLK_OUT3 : OUT std_logic;
		CLK_OUT4 : OUT std_logic;
		LOCKED : OUT std_logic
		);
	END COMPONENT;

	
	signal clk_sys, clk_100, clk_24, clk_48, clk_locked : std_logic ;
	signal resetn , sys_resetn : std_logic ;
	
	signal counter_output : std_logic_vector(31 downto 0);
	signal fifo_output : std_logic_vector(15 downto 0);
	signal fifo_input : std_logic_vector(15 downto 0);
	signal latch_output : std_logic_vector(15 downto 0);
	signal fifoB_wr, fifoA_rd, fifoA_rd_old, fifoA_empty, fifoA_full, fifoB_empty, fifoB_full : std_logic ;
	signal fifo_full_rising_edge, fifo_full_old : std_logic ;
	signal bus_data_in, bus_data_out : std_logic_vector(15 downto 0);
	signal bus_fifo_out, bus_latch_out : std_logic_vector(15 downto 0);
	signal bus_addr : std_logic_vector(15 downto 0);
	signal bus_wr, bus_rd, bus_cs : std_logic ;
	signal cs_fifo, cs_latch : std_logic ;
	
	
	signal cam_data : std_logic_vector(7 downto 0);
	signal cam_sioc, cam_siod : std_logic ;
	signal cam_xclk, cam_pclk, cam_vsync, cam_href, cam_reset : std_logic ;
	
	signal rom_addr : std_logic_vector(7 downto 0);
	signal rom_data : std_logic_vector(15 downto 0);
	
	signal pixel_from_interface : std_logic_vector(7 downto 0);
	signal pxclk_from_interface, href_from_interface, vsync_from_interface : std_logic ;

	signal pixel_from_sobel : std_logic_vector(7 downto 0);
	signal pxclk_from_sobel, href_from_sobel, vsync_from_sobel : std_logic ;

	signal pixel_from_harris : std_logic_vector(7 downto 0);
	signal raw_from_harris : std_logic_vector(15 downto 0);
	signal pxclk_from_harris, href_from_harris, vsync_from_harris : std_logic ;
	
	signal output_pxclk, output_href , output_vsync : std_logic ;
	signal output_pixel : std_logic_vector(7 downto 0);
	signal hsync_rising_edge, vsync_rising_edge, pxclk_rising_edge, hsync_old, vsync_old, pxclk_old, write_pixel_old : std_logic ;
	signal pixel_buffer : std_logic_vector(15 downto 0);	
	signal pixel_count :std_logic_vector(7 downto 0);
	signal write_pixel : std_logic ;
begin
	
	resetn <= PB(0) ;
	sys_clocks_gen: clock_gen 
	PORT MAP(
		CLK_IN1 => OSC_FPGA,
		CLK_OUT1 => clk_100,
		CLK_OUT2 => clk_24,
		CLK_OUT3 => clk_sys, --120Mhz system clock
		CLK_OUT4 => clk_48, --120Mhz system clock
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
LED(1) <= NOT GPMC_CSN(1) ;
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

cs_fifo <= '1' when bus_addr(15 downto 10) = "000000" else
			  '0' ;	  

bus_data_in <= bus_fifo_out when cs_fifo = '1' else
					(others => '1');

bi_fifo0 : fifo_peripheral 
		generic map(ADDR_WIDTH => 16,WIDTH => 16, SIZE => 2048, BURST_SIZE => 512)--16384)
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
		
		
	pixel_from_fifo : fifo2pixel
	generic map(WIDTH => 320 , HEIGHT => 240)
	port map(
		clk => clk_sys, resetn => sys_resetn ,

		-- fifo side
		fifo_empty => fifoA_empty ,
		fifo_rd => fifoA_rd ,
		fifo_data =>fifo_output,
		
		-- pixel side 
		pixel_clk => clk_24,
		y_data =>  pixel_from_interface , 
 		pixel_clock_out => pxclk_from_interface, 
		hsync_out => href_from_interface, 
		vsync_out =>vsync_from_interface 
	
	);

harris0 : HARRIS
generic map(WIDTH => 320, HEIGHT => 240, WINDOW_SIZE => 5, DS_FACTOR => 2)
port map(
		clk => clk_sys , 
 		resetn => sys_resetn,  
 		pixel_clock => pxclk_from_interface, hsync => href_from_interface, vsync => vsync_from_interface, 
 		pixel_clock_out => pxclk_from_harris, hsync_out => href_from_harris, vsync_out => vsync_from_harris,
 		pixel_data_in => pixel_from_interface,
 		harris_out => raw_from_harris
);

pixel_from_harris <= X"00" when raw_from_harris(15) ='1' else
							raw_from_harris(14 downto 7);	

output_pxclk <= pxclk_from_harris ;
output_href <= href_from_harris ;
output_vsync <= vsync_from_harris ;
output_pixel <= pixel_from_harris ;

pixel2fifo0 :  pixel2fifo
port map(
	clk => clk_sys, resetn => sys_resetn ,
	pixel_clock => output_pxclk, hsync => output_href, vsync => output_vsync,
	pixel_data_in => output_pixel ,
	fifo_data => fifo_input,
	fifo_wr => fifoB_wr
);

end Behavioral;

