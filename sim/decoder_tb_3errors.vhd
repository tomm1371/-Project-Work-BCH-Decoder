LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.std_logic_textio.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;


LIBRARY STD;
USE STD.textio.ALL;

ENTITY decoder_tb_3errors IS
END ENTITY decoder_tb_3errors;

ARCHITECTURE decoder_tb_3errors_arch OF decoder_tb_3errors IS
	CONSTANT M : INTEGER := 8; -- 2**m = length
	CONSTANT T : INTEGER := 2; -- error correction capability
	CONSTANT CLK_PERIOD : TIME := 20 ns;

	COMPONENT decoder IS
		PORT (
			clk, rst : IN STD_LOGIC;
			data_in : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
			data_valid : IN STD_LOGIC;
			code_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
			code_valid : OUT STD_LOGIC;
			errors_found : OUT STD_LOGIC_VECTOR(1 DOWNTO 0)
		);
	END COMPONENT decoder;

	SIGNAL clockTB, resetTB, data_validTB : STD_LOGIC := '0';
	SIGNAL data_inTB : STD_LOGIC_VECTOR (2 ** M - 1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL code_outTB : STD_LOGIC_VECTOR (2 ** M - 1 DOWNTO 0);
	SIGNAL code_validTB : STD_LOGIC;
	SIGNAL errors_foundTB : STD_LOGIC_VECTOR (1 DOWNTO 0);
	--SIGNAL errors_foundTB : STD_LOGIC_VECTOR(1 DOWNTO 0);

	--file input_file : TEXT open READ_MODE is "TestFiles/encoderOutput.txt";
	
    file output_file : TEXT open WRITE_MODE is "TestFiles/decoder3ErrorTestOutput.txt";

BEGIN

	DUT : decoder PORT MAP(
		clk => clockTB,
		rst => resetTB,
		data_in => data_inTB,
		data_valid => data_validTB,
		code_out => code_outTB,
		code_valid => code_validTB,
		errors_found => errors_foundTB
	);
	clk_process : PROCESS
	BEGIN
		clockTB <= '0';
		WAIT FOR CLK_PERIOD / 2;
		clockTB <= '1';
		WAIT FOR CLK_PERIOD / 2;
	END PROCESS;

	STIMULUS : PROCESS

		VARIABLE line_in : line;
		VARIABLE vec : STD_LOGIC_VECTOR(255 DOWNTO 0) := x"5b09a12ca21cb76711873db80ff4faf355575e6acacebbb26c08063a0190bb29" ;
		VARIABLE eVec1, eVec2, eVec3 : STD_LOGIC_VECTOR(259 DOWNTO 0) := (OTHERS => '0');

	BEGIN

		resetTB <= '1';
		WAIT FOR CLK_PERIOD * 2;
		resetTB <= '0';
		WAIT FOR CLK_PERIOD * 2;

		data_validTB <= '1';
		eVec1 := x"0_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000001";
		--These nested loops test the decoder on every error pattern with 3 errors
		-- there are 2.763.520 different ways to do this, so making separate data files is not a good idea
		while (eVec1(256) = '0') loop
			eVec2 := eVec1(258 downto 0) & '0' ;

			while (eVec2(256) = '0') loop
				eVec3 := eVec2(258 downto 0) & '0' ;

				while (eVec3(256) = '0') loop
					data_inTB <= vec xor eVec1(255 downto 0) xor eVec2(255 downto 0) xor eVec3(255 downto 0);
					WAIT FOR CLK_PERIOD;
			
					eVec3 := eVec3(258 downto 0) & '0';
				end LOOP;

				eVec2 := eVec2(258 downto 0) & '0';
			end LOOP;
		
			eVec1 := eVec1(258 downto 0) & '0';
		end loop;
		data_inTB <= (OTHERS => '0');
		data_validTB <= '0';
	wait;

	END PROCESS;

	
	capture_output : PROCESS
        variable output_line : line;
		variable testedLines : INTEGER := 0;
    BEGIN
        WAIT UNTIL RISING_EDGE(clockTB);
		

        if code_validTB = '1' then
			testedLines := testedLines + 1;
			if errors_foundTB /= "11" then 
            	hwrite(output_line, code_outTB(255 DOWNTO 0));

            	writeline(output_file, output_line);
			end if;
		elsif testedLines /= 0 then 
			write(output_line, testedLines);
			writeline(output_file, output_line);
			testedLines := 0;
        end if;
    END PROCESS;


END ARCHITECTURE decoder_tb_3errors_arch;