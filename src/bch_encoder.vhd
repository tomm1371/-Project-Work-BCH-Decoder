-- bch_encoder
-- Feeds data in, appends remainder as parity bits
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bch_encoder is
	generic (M : integer := 4; T : integer := 2);
		-- Primitive polynomial used
		-- 
	port (
		clk, rst    : in  std_logic;
		data_in     : in  std_logic_vector(M-1 downto 0);
		data_valid  : in  std_logic;
		code_out    : out std_logic_vector(M-1 downto 0);
		code_valid  : out std_logic
	);
end entity;

architecture RTL of bch_encoder is

	-- internal signals


begin

end architecture;