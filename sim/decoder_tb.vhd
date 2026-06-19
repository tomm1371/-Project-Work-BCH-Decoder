LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.std_logic_textio.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;


LIBRARY STD;
USE STD.textio.ALL;

ENTITY decoder_tb IS
END ENTITY decoder_tb;

ARCHITECTURE decoder_tb_arch OF decoder_tb IS
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
	--SIGNAL errors_foundTB : STD_LOGIC_VECTOR(1 DOWNTO 0);

	file input_file : TEXT open READ_MODE is "TestFiles/codes_with_errors.txt";
	--file input_file : TEXT open READ_MODE is "TestFiles/encoderOutput.txt";
	--file input_file : TEXT open READ_MODE is "TestFiles/codes_with_errors.txt";
	--file input_file : TEXT open READ_MODE is "ImageTesting/encodedParrotErrors.txt";
    file output_file : TEXT open WRITE_MODE is "TestFiles/decoderOutput.txt";

BEGIN

	DUT : decoder PORT MAP(
		clk => clockTB,
		rst => resetTB,
		data_in => data_inTB,
		data_valid => data_validTB,
		code_out => code_outTB,
		code_valid => code_validTB,
		errors_found => OPEN
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
		VARIABLE vec : STD_LOGIC_VECTOR(255 DOWNTO 0);

	BEGIN

		resetTB <= '1';
		WAIT FOR CLK_PERIOD * 2;
		resetTB <= '0';
		WAIT FOR CLK_PERIOD * 2.5;


		while not endfile(input_file) loop
			readline(input_file, line_in); 
			next when line_in'length = 0;           
			--read(line_in, vec);
			hread(line_in, vec);
			data_validTB <= '1';
			data_inTB <= vec;
			WAIT FOR CLK_PERIOD;
		end loop;
		data_validTB <= '0';
	wait;
		
	END PROCESS;
	
	capture_output : PROCESS
        variable output_line : line;
    BEGIN
        WAIT UNTIL RISING_EDGE(clockTB);
        if code_validTB = '1' then
            write(output_line, code_outTB(255 DOWNTO 0));
            writeline(output_file, output_line);
        end if;
    END PROCESS;
END ARCHITECTURE decoder_tb_arch;