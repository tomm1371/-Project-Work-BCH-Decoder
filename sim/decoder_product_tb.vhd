LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.std_logic_textio.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;


LIBRARY STD;
USE STD.textio.ALL;

ENTITY decoder_product_tb IS
END ENTITY decoder_product_tb;

ARCHITECTURE decoder_product_tb_arch OF decoder_product_tb IS
	CONSTANT M : INTEGER := 8; -- 2**m = length
	CONSTANT T : INTEGER := 2; -- error correction capability
	CONSTANT CLK_PERIOD : TIME := 20 ns;

	COMPONENT decoder_product IS
		PORT (
			clk, reset : IN STD_LOGIC;

			column_valid : IN STD_LOGIC;
			column_in : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
			column_ready : OUT STD_LOGIC;

			codeword_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
			codeword_valid : OUT STD_LOGIC;
			block_done : OUT STD_LOGIC	
		);
	END COMPONENT decoder_product;

	SIGNAL clockTB, resetTB, column_validTB, column_readyTB : STD_LOGIC := '0';
	SIGNAL column_inTB : STD_LOGIC_VECTOR (2 ** M - 1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL codeword_outTB : STD_LOGIC_VECTOR (2 ** M - 1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL codeword_validTB : STD_LOGIC := '0';
	SIGNAL block_doneTB : STD_LOGIC := '0';
	--SIGNAL errors_foundTB : STD_LOGIC_VECTOR(1 DOWNTO 0);

	file input_file : TEXT open READ_MODE is "TestFiles/codes_with_errors.txt";
	--file input_file : TEXT open READ_MODE is "TestFiles/encoderOutput.txt";
	--file input_file : TEXT open READ_MODE is "TestFiles/codes_with_errors.txt";
	--file input_file : TEXT open READ_MODE is "ImageTesting/encodedParrotErrors.txt";
    file output_file : TEXT open WRITE_MODE is "TestFiles/decoderProductOutput.txt";

BEGIN

	DUT : decoder_product 
	PORT MAP(
		clk => clockTB,
		reset => resetTB,
		
		column_valid => column_validTB,
		column_in => column_inTB,
		column_ready => column_readyTB,
		
		codeword_valid => codeword_validTB,
		codeword_out => codeword_outTB,

		block_done => block_doneTB
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

		--column_readyTB <= '1';
		while not endfile(input_file) loop
			if column_readyTB = '1' then
				readline(input_file, line_in); 
				--next when line_in'length = 0;           
				--read(line_in, vec);
				read(line_in, vec);
				column_validTB <= '1';
				column_inTB <= vec;
			end if;
			WAIT FOR CLK_PERIOD;
		end loop;
		column_validTB <= '0';
	wait;
		
	END PROCESS;
	
	capture_output : PROCESS
        variable output_line : line;
    BEGIN
        WAIT UNTIL RISING_EDGE(clockTB);
        if codeword_validTB = '1' then
            write(output_line, codeword_outTB(255 DOWNTO 0));
            writeline(output_file, output_line);
        end if;
    END PROCESS;
END ARCHITECTURE decoder_product_tb_arch;