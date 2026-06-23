LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;

ENTITY product_encoder_file_tb IS
END ENTITY product_encoder_file_tb;

ARCHITECTURE Behavioral OF product_encoder_file_tb IS

    -- DUT is changed to use the product_encoder_v2.
 COMPONENT product_encoder_v2
    GENERIC (
        M : INTEGER := 8;
        T : INTEGER := 2
    );
    PORT (
        clk            : IN STD_LOGIC;
        reset          : IN STD_LOGIC;

        row_valid      : IN STD_LOGIC;
        row_in         : IN STD_LOGIC_VECTOR(238 DOWNTO 0);
        row_ready      : OUT STD_LOGIC;

        codeword_valid : OUT STD_LOGIC;
        codeword_out   : OUT STD_LOGIC_VECTOR(255 DOWNTO 0);
        block_done     : OUT STD_LOGIC
    );
 END COMPONENT;

    -- Change signals to be the relevant ones for the new DUT.
    SIGNAL clk            : STD_LOGIC := '0';
	 SIGNAL reset          : STD_LOGIC := '0';

	 SIGNAL row_in         : STD_LOGIC_VECTOR(238 DOWNTO 0) := (OTHERS => '0');
	 SIGNAL row_valid      : STD_LOGIC := '0';
	 SIGNAL row_ready      : STD_LOGIC; -- DUT assigns this, so no standard value

	 SIGNAL codeword_out   : STD_LOGIC_VECTOR(255 DOWNTO 0);-- Same for these final 3. No standard value.
	 SIGNAL codeword_valid : STD_LOGIC; 
	 SIGNAL block_done     : STD_LOGIC;

    file input_file : TEXT open READ_MODE is "testfiles/productTestData.txt";
    file output_file : TEXT open WRITE_MODE is "testfiles/productEncoderOutput.txt";

    constant CLK_PERIOD : TIME := 20 ns;

BEGIN
    -- Instantiate the new DUT.
   dut : product_encoder_v2
    GENERIC MAP (
        M => 8,
        T => 2
    )
    PORT MAP (
        clk            => clk,
        reset          => reset,

        row_valid      => row_valid,
        row_in         => row_in,
        row_ready      => row_ready,

        codeword_valid => codeword_valid,
        codeword_out   => codeword_out,
        block_done     => block_done
    );

    -- Clock generation is the same for this version too.
    clk_process : PROCESS
    BEGIN
        WHILE true LOOP
            clk <= '0';
            WAIT FOR CLK_PERIOD / 2;
            clk <= '1';
            WAIT FOR CLK_PERIOD / 2;
        END LOOP;
    END PROCESS;

    -- New stimulus process to apply test vectors for the product version of the encoder.
	 -- Read input rows from the file generated from python and send them to the DUT.
stimulus_process : PROCESS
    VARIABLE line_in : line;
    VARIABLE row_v   : STD_LOGIC_VECTOR(238 DOWNTO 0);
BEGIN
    reset <= '1';
    row_valid <= '0';

    WAIT FOR CLK_PERIOD * 2;
    reset <= '0';
    WAIT FOR CLK_PERIOD * 2.5;

    -- Skip the first line, which is the file header.
    readline(input_file, line_in);

    WHILE NOT endfile(input_file) LOOP
        readline(input_file, line_in);
        read(line_in, row_v);

        row_in <= row_v;
        row_valid <= '1';

        -- Keep this row stable until the DUT accepts it.
		  -- This handshake logic was not in the other version, but it is needed for this version.
        LOOP
            WAIT UNTIL RISING_EDGE(clk);
            EXIT WHEN row_ready = '1';
        END LOOP;
    END LOOP;

    row_valid <= '0';
    WAIT;
END PROCESS;

 -- Write each valid encoded column codeword to the output file.
	capture_output : PROCESS
		 VARIABLE output_line : line;
	BEGIN
		 WAIT UNTIL RISING_EDGE(clk);

		 IF codeword_valid = '1' THEN
			  write(output_line, codeword_out);
			  writeline(output_file, output_line);
		 END IF;
END PROCESS;
END ARCHITECTURE Behavioral;