LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.codeword_encoder_pkg.ALL;

ENTITY top_de10lite_encoder IS
    PORT (
        MAX10_CLK1_50 : IN STD_LOGIC; -- clk
        KEY : IN STD_LOGIC_VECTOR(1 DOWNTO 0); -- rst and start(data_valid)
        HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) -- display codeword
    );
END ENTITY top_de10lite_encoder;

ARCHITECTURE rtl OF top_de10lite_encoder IS

    -- Signals for connecting components and internal logic
    -- data input with validation
    SIGNAL data_in : STD_LOGIC_VECTOR(CODEWORD_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL data_valid : STD_LOGIC := '0';

    -- output codeword and validation and ready signals
    SIGNAL code_out : STD_LOGIC_VECTOR(255 DOWNTO 0) := (OTHERS => '0');
    SIGNAL code_valid : STD_LOGIC := '0';
    SIGNAL busy : STD_LOGIC := '0';
    SIGNAL row_ready : STD_LOGIC := '0';

    -- Signals for controlling the codeword stream reader and key synchronization
    SIGNAL reader_done : STD_LOGIC := '0';
    SIGNAL key1_sync_0 : STD_LOGIC := '1';
    SIGNAL key1_sync_1 : STD_LOGIC := '1';
    SIGNAL reader_start : STD_LOGIC := '0';

    -- Signal to analyze data on 7-seg display
    SIGNAL product_total : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL total_encoded : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL block_done : STD_LOGIC := '0';

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
    reader_inst : ENTITY work.codeword_encoder_product_reader
        GENERIC MAP(
            DATA_WIDTH => CODEWORD_WIDTH,
            ROM_DEPTH => CODEWORD_COUNT,
            ROM_ADDR_WIDTH => CODEWORD_ADDR_WIDTH
        )
        PORT MAP(
            clk => MAX10_CLK1_50,
            rst => NOT KEY(0),
            start => reader_start,
            busy => busy,
            data_out => data_in,
            data_valid => data_valid,
            done => reader_done
        );

    -- KEY synchronization, start reader, when KEY(1) is released
    PROCESS (MAX10_CLK1_50, KEY(0))
    BEGIN
        IF KEY(0) = '0' THEN
            key1_sync_0 <= '1';
            key1_sync_1 <= '1';
            reader_start <= '0';
        ELSIF rising_edge(MAX10_CLK1_50) THEN
            key1_sync_0 <= KEY(1);
            key1_sync_1 <= key1_sync_0;
            reader_start <= key1_sync_0 AND NOT key1_sync_1;
        END IF;
    END PROCESS;

    -- Instantiate the encoder
    encoder_inst : ENTITY work.encoder_product
        PORT MAP(
            clk => MAX10_CLK1_50,
            reset => NOT KEY(0),
            -- input
            row_valid => data_valid,
            row_in => data_in,

            row_ready => row_ready,
            -- output
            codeword_valid => code_valid,
            codeword_out => code_out,
            block_done => block_done
        );

    -- HEX4 and HEX5 will display the total number of product codewords encoded
    -- HEX0-HEX3 will display the total number of codewords encoded
    PROCESS (MAX10_CLK1_50, KEY(0))
    BEGIN
        IF KEY(0) = '0' THEN
            HEX0 <= (OTHERS => '1');
            HEX1 <= (OTHERS => '1');
            HEX2 <= (OTHERS => '1');
            HEX3 <= (OTHERS => '1');
            HEX4 <= (OTHERS => '1');
            HEX5 <= (OTHERS => '1');
            total_encoded <= (OTHERS => '0');
            product_total <= (OTHERS => '0');
        ELSIF (rising_edge(MAX10_CLK1_50)) THEN

            IF code_valid = '1' THEN
                total_encoded <= STD_LOGIC_VECTOR(unsigned(total_encoded) + 1);
            END IF;
            IF block_done = '1' THEN
                product_total <= STD_LOGIC_VECTOR(unsigned(product_total) + 1);
            END IF;
            busy <= not row_ready; -- busy when not ready for next row
            HEX0 <= hex_to_7seg(total_encoded(3 DOWNTO 0));
            HEX1 <= hex_to_7seg(total_encoded(7 DOWNTO 4));
            HEX2 <= hex_to_7seg(code_out(11 DOWNTO 8));
            HEX3 <= hex_to_7seg(code_out(15 DOWNTO 12));
            HEX4 <= hex_to_7seg(product_total(3 DOWNTO 0));
            HEX5 <= hex_to_7seg(product_total(7 DOWNTO 4));
        END IF;
    END PROCESS;

END ARCHITECTURE;
--DE10_LITE_Empty_Top: 
--
-------------- CLOCK ----------
--input 		          		ADC_CLK_10,
--input 		          		MAX10_CLK1_50,
--input 		          		MAX10_CLK2_50,
--
-------------- SDRAM ----------
--output		    [12:0]		DRAM_ADDR,
--output		     [1:0]		DRAM_BA,
--output		          		DRAM_CAS_N,
--output		          		DRAM_CKE,
--output		          		DRAM_CLK,
--output		          		DRAM_CS_N,
--inout 		    [15:0]		DRAM_DQ,
--output		          		DRAM_LDQM,
--output		          		DRAM_RAS_N,
--output		          		DRAM_UDQM,
--output		          		DRAM_WE_N,
--
-------------- SEG7 ----------
--output		     [7:0]		HEX0,
--output		     [7:0]		HEX1,
--output		     [7:0]		HEX2,
--output		     [7:0]		HEX3,
--output		     [7:0]		HEX4,
--output		     [7:0]		HEX5,
--
-------------- KEY ----------
--input 		     [1:0]		KEY,
--
-------------- LED ----------
--output		     [9:0]		LEDR,
--
-------------- SW ----------
--input 		     [9:0]		SW,
--
-------------- VGA ----------
--output		     [3:0]		VGA_B,
--output		     [3:0]		VGA_G,
--output		          		VGA_HS,
--output		     [3:0]		VGA_R,
--output		          		VGA_VS,
--
-------------- Accelerometer ----------
--output		          		GSENSOR_CS_N,
--input 		     [2:1]		GSENSOR_INT,
--output		          		GSENSOR_SCLK,
--inout 		          		GSENSOR_SDI,
--inout 		          		GSENSOR_SDO,
--
-------------- Arduino ----------
--inout 		    [15:0]		ARDUINO_IO,
--inout 		          		ARDUINO_RESET_N,
--
-------------- GPIO, GPIO connect to GPIO Default ----------
--inout 		    [35:0]		GPIO