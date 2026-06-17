LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.codeword_file_pkg.ALL;

ENTITY top_de10lite_decoder IS
    PORT (
        MAX10_CLK1_50  : IN STD_LOGIC; -- connect to board clock
        KEY : IN STD_LOGIC_VECTOR(1 DOWNTO 0); -- rst and start(data_valid)
        HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- display codeword
        LEDR : OUT STD_LOGIC_VECTOR(9 DOWNTO 0) -- error visualization, each bit represents an error type (no error, 1 error, 2 errors, 3 errors)
    );
END ENTITY top_de10lite_decoder;

ARCHITECTURE rtl OF top_de10lite_decoder IS

    component pll
        PORT
        (
            inclk0		: IN STD_LOGIC  := '0';
            c0		: OUT STD_LOGIC 
        );
    end component;
    
    SIGNAL clk : STD_LOGIC;
    SIGNAL data_in : STD_LOGIC_VECTOR(CODEWORD_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL data_valid : STD_LOGIC := '0';
    SIGNAL code_out : STD_LOGIC_VECTOR(255 DOWNTO 0) := (OTHERS => '0');
    SIGNAL code_valid : STD_LOGIC := '0';
    SIGNAL errors_found : STD_LOGIC_VECTOR(1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL reader_done : STD_LOGIC := '0';
    SIGNAL key1_sync_0 : STD_LOGIC := '1';
    SIGNAL key1_sync_1 : STD_LOGIC := '1';
    SIGNAL reader_start : STD_LOGIC := '0';

    -- signals for counting error types and visualization
    SIGNAL total_decoded : std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL no_error_count : std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL one_error_count : std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL two_error_count : std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL three_error_count : std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');

    -- map hex to 7-seg for visualization
    FUNCTION hex_to_7seg(hex : STD_LOGIC_VECTOR(3 DOWNTO 0)) RETURN STD_LOGIC_VECTOR IS
        VARIABLE seg : STD_LOGIC_VECTOR(7 DOWNTO 0);
    BEGIN
        CASE hex IS
            WHEN "0000" => seg := NOT "00111111"; -- 0
            WHEN "0001" => seg := NOT "00000110"; -- 1
            WHEN "0010" => seg := NOT "01011011"; -- 2
            WHEN "0011" => seg := NOT "01001111"; -- 3
            WHEN "0100" => seg := NOT "01100110"; -- 4
            WHEN "0101" => seg := NOT "01101101"; -- 5
            WHEN "0110" => seg := NOT "01111101"; -- 6
            WHEN "0111" => seg := NOT "00000111"; -- 7
            WHEN "1000" => seg := NOT "01111111"; -- 8
            WHEN "1001" => seg := NOT "01101111"; -- 9
            WHEN "1010" => seg := NOT "01110111"; -- A
            WHEN "1011" => seg := NOT "01111100"; -- b
            WHEN "1100" => seg := NOT "00111001"; -- C
            WHEN "1101" => seg := NOT "01011110"; -- d
            WHEN "1110" => seg := NOT "01111001"; -- E
            WHEN "1111" => seg := NOT "01110001"; -- F
            WHEN OTHERS => seg := (OTHERS => '1'); -- blank / safety
        END CASE;
        RETURN seg;
    END FUNCTION;
BEGIN
    -- Instantiate the codeword stream reader to read codewords from ROM
    -- Reads codewords from a ROM initialized with "bch_decoder_codewords.mif" and outputs them sequentially when start is triggered
    reader_inst : ENTITY work.codeword_stream_reader
        GENERIC MAP (
            DATA_WIDTH => CODEWORD_WIDTH,
            ROM_DEPTH => CODEWORD_COUNT,
            ROM_ADDR_WIDTH => CODEWORD_ADDR_WIDTH
        )
        PORT MAP(
            clk => clk,
            rst => NOT KEY(0),
            start => reader_start,
            data_out => data_in,
            data_valid => data_valid,
            done => reader_done
        );

    clk_inst : ENTITY work.pll
        PORT MAP (inclk0 => MAX10_CLK1_50, c0 => clk);

    -- Synchronize the KEY1 release so the reader starts once per button release.
    PROCESS (clk, KEY(0))
    BEGIN
        IF KEY(0) = '0' THEN
            key1_sync_0 <= '1';
            key1_sync_1 <= '1';
            reader_start <= '0';
        ELSIF rising_edge(clk) THEN
            key1_sync_0 <= KEY(1);
            key1_sync_1 <= key1_sync_0;
            reader_start <= key1_sync_0 AND NOT key1_sync_1;
        END IF;
    END PROCESS;


    -- Instantiate the decoder to decode the codewords read from ROM
    decoder_inst : entity work.decoder
        GENERIC MAP (
            M => 8,
            T => 2
        )
        PORT MAP(
            clk => clk,
            rst => NOT KEY(0),
            data_in => data_in,
            data_valid => data_valid,
            code_out => code_out,
            code_valid => code_valid,
            errors_found => errors_found
        );

    -- Process to count error types and update HEX displays for visualization
    PROCESS (clk, KEY(0))
    BEGIN
        IF KEY(0) = '0' THEN
        -- reset counts and displays when reset is pressed
            HEX0 <= (OTHERS => '1');
            HEX1 <= (OTHERS => '1');
            HEX2 <= (OTHERS => '1');
            HEX3 <= (OTHERS => '1');
            HEX4 <= (OTHERS => '1');
            HEX5 <= (OTHERS => '1');
            total_decoded <= (OTHERS => '0');
            no_error_count <= (OTHERS => '0');
            one_error_count <= (OTHERS => '0');
            two_error_count <= (OTHERS => '0');
            three_error_count <= (OTHERS => '0');
        ELSIF rising_edge(clk) THEN
        -- 
            IF code_valid = '1' THEN
                total_decoded <= std_logic_vector(unsigned(total_decoded) + 1);
                IF errors_found = "00" THEN
                    no_error_count <= std_logic_vector(unsigned(no_error_count) + 1);
                ELSIF errors_found = "01" THEN
                    one_error_count <= std_logic_vector(unsigned(one_error_count) + 1);
                ELSIF errors_found = "10" THEN
                    two_error_count <= std_logic_vector(unsigned(two_error_count) + 1);
                ELSIF errors_found = "11" THEN
                    three_error_count <= std_logic_vector(unsigned(three_error_count) + 1);
                END IF;
            END IF;

            HEX0 <= hex_to_7seg(two_error_count(3 DOWNTO 0));
            HEX1 <= hex_to_7seg(two_error_count(7 DOWNTO 4));
            HEX2 <= hex_to_7seg(one_error_count(3 DOWNTO 0));
            HEX3 <= hex_to_7seg(one_error_count(7 DOWNTO 4));
            HEX4 <= hex_to_7seg(no_error_count(3 DOWNTO 0));
            HEX5 <= hex_to_7seg(no_error_count(7 DOWNTO 4));
            LEDR(7 DOWNTO 0) <= three_error_count; -- visualize 3 error count on LEDs
            LEDR(9 DOWNTO 8) <= "00";
        END IF;
    END PROCESS;
END ARCHITECTURE;


--component pll
--	PORT
--	(
--		inclk0		: IN STD_LOGIC  := '0';
--		c0		: OUT STD_LOGIC 
--	);
--end component;
