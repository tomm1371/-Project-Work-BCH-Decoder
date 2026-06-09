library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_textio.all;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;

library STD;
use STD.textio.all;

entity decoder_tb is
end entity decoder_tb;

architecture decoder_tb_arch of decoder_tb is
    constant M : INTEGER := 8; -- 2**m = length
    constant T : INTEGER := 2; -- error correction capability
	constant half_a_clk : TIME := 25 ns;

    Component decoder IS
	PORT (
		clk, rst : IN STD_LOGIC;
		data_in : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
		data_valid : IN STD_LOGIC;
		code_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
		code_valid : OUT STD_LOGIC
	);
    END Component decoder;

	signal clockTB,resetTB, data_validTB : std_logic := '0';
	signal data_inTB                     : std_logic_vector (2**M-1 downto 0) := (OTHERS => '0');

begin
	
	DUT : decoder port map (
		clk	          => clockTB,
		rst           => resetTB,
		data_in       => data_inTB,
		data_valid	  => data_validTB,			
		code_out  => open,
		code_valid  => open
		);
													
	STIMULUS : process

		--file Fin: TEXT open  READ_MODE is  "input_file.txt";
		--file Fout:TEXT open WRITE_MODE is "output_file.txt";
	
		--variable current_readLine   : line;
		--variable readField0         : std_logic;
		--variable readField1         : std_logic_vector (2**M-1 downto 0);
		--variable current_writeLine  : line;
	
		begin
			--readline(Fin, current_readLine); --ingore the first line of the file
			resetTB <= '1';
			clockTB <= not clockTB;
			wait for half_a_clk;
			clockTB <= not clockTB;
			wait for half_a_clk;
			resetTB <= '0';

            clockTB <= not clockTB;
			wait for half_a_clk;
			clockTB <= not clockTB;
			wait for half_a_clk;
            --data_inTB    <= x"00050000_00000000_00000000_00000000_00000000_00000000_00000000_00000000";
			--data_inTB    <= x"80000000_00000000_00000000_00000000_00000000_00000000_00000000_00016F63";
			data_inTB    <=   x"A0000000_00000000_00000000_00000000_00000000_00000000_00000000_0002DEC7";
            data_validTB <= '1';

			clockTB <= not clockTB;
			wait for half_a_clk;
			clockTB <= not clockTB;
			wait for half_a_clk;
			data_inTB <= x"80000000_00000000_00010000_00000000_00000000_00000000_00000000_00016F63";
			
			clockTB <= not clockTB;
			wait for half_a_clk;
			clockTB <= not clockTB;
			wait for half_a_clk;

			data_inTB <= x"00000000_00000000_00000000_00000000_00000000_00000000_00000000_0002DEC7";


			--while (not endfile(Fin)) loop
            
				--readline(Fin, current_readLine);
				
				--hread(current_readLine, readField0); -- do this work?
				--read(current_readLine, readField1);
				
				--data_inTB       <= readField0;
				--data_validTB <= readField1;
				
				--clockTB <= not clockTB;
				--wait for half_a_clk ns;
				--clockTB <= not clockTB;
				--wait for half_a_clk ns;

				
				--write(current_writeLine, string'("Test with INPUT: Up="));
				--write(current_writeLine, goUpTB);
				--write(current_writeLine, string'(" Reset="));
				--write(current_writeLine, resetTB);
				
				--write(current_writeLine, string'(" OUTPUT: count="));
				--write(current_writeLine, countTB);
				--if countTB = desiredCountTB 
				--then 
					--passed test
					--write(current_writeLine, string'("    TEST: OK"));
					
				--else
					--failed test
					--write(current_writeLine, string'("    TEST: FAILED "));
					
					--writeline(Fout, current_writeLine);
					--write(current_writeLine, string'("TEST ABOVE EXPECTED: count="));
					--write(current_writeLine, desiredCountTB);
			
				--end if;
				
				--writeline(Fout, current_writeLine);
				
			--end loop;
            clockTB <= not clockTB;
			wait for half_a_clk;
			clockTB <= not clockTB;
			wait for half_a_clk;

            data_inTB    <= (OTHERS => '0');
			data_validTB <= '0';

            while true loop
                clockTB <= not clockTB;
				wait for half_a_clk;
            end loop;
			--write(current_writeLine, string'("TEST OK/GOD = "));
			--writeline(current_writeLine, cksum_ok_cntTB)
			--write(current_writeLine, string'("TEST KO/BAD ="));
			--writeline(current_writeLine, cksum_ko_cntTB)
			
	end process;

end architecture decoder_tb_arch;