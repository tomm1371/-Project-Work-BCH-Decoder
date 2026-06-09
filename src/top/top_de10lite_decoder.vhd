LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY top_de10lite_decoder IS
    PORT (
        MAX10_CLK1_50  : IN STD_LOGIC; -- connect to board clock
        KEY : IN STD_LOGIC_VECTOR(1 DOWNTO 0); -- rst and start(data_valid)
        HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) -- display codeword
    );
END ENTITY top_de10lite_decoder;

ARCHITECTURE rtl OF top_de10lite_decoder IS
    SIGNAL data_in : STD_LOGIC_VECTOR(255 DOWNTO 0) := (x"00000000_00000000_00000000_00000000_00000000_00000000_00000000_0002DEC1"); -- 256 bits, initialize with all zeros for testing
    SIGNAL data_valid : STD_LOGIC := '0';
    SIGNAL code_out : STD_LOGIC_VECTOR(255 DOWNTO 0) := (OTHERS => '0');
    SIGNAL code_valid : STD_LOGIC := '0';
    SIGNAL errors_found : STD_LOGIC_VECTOR(1 DOWNTO 0) := (OTHERS => '0');


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
    decoder_inst : entity work.decoder
        GENERIC MAP (
            M => 8,
            T => 2
        )
        PORT MAP(
            clk => MAX10_CLK1_50,
            rst => NOT KEY(0),
            data_in => data_in,
            data_valid => NOT KEY(1),
            code_out => code_out,
            code_valid => code_valid,
            errors_found => errors_found
        );

    PROCESS (MAX10_CLK1_50, KEY(0))
    BEGIN
        IF KEY(0) = '0' THEN
            HEX0 <= (OTHERS => '1');
            HEX1 <= (OTHERS => '1');
            HEX2 <= (OTHERS => '1');
            HEX3 <= (OTHERS => '1');
            HEX4 <= (OTHERS => '1');
            HEX5 <= (OTHERS => '1');
        ELSIF (code_valid = '1' and rising_edge(MAX10_CLK1_50)) THEN
            HEX0 <= hex_to_7seg(code_out(3 DOWNTO 0));
            HEX1 <= hex_to_7seg(code_out(7 DOWNTO 4));
            HEX2 <= hex_to_7seg(code_out(11 DOWNTO 8));
            HEX3 <= hex_to_7seg(code_out(15 DOWNTO 12));
            HEX4 <= hex_to_7seg(code_out(19 DOWNTO 16));
            HEX5 <= hex_to_7seg("00" & errors_found);
        END IF;
    END PROCESS;
END ARCHITECTURE;
