LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY top_de10lite_decoder IS
    PORT (
        clk  : IN STD_LOGIC; -- connect to board clock
        rst  : IN STD_LOGIC;
        data_in    : IN  STD_LOGIC_VECTOR(255 DOWNTO 0);
        data_valid : IN  STD_LOGIC;
        code_out   : OUT STD_LOGIC_VECTOR(255 DOWNTO 0);
        code_valid : OUT STD_LOGIC
    );
END ENTITY top_de10lite_decoder;

ARCHITECTURE rtl OF top_de10lite_decoder IS
BEGIN
    decoder_inst : entity work.decoder
        GENERIC MAP (
            M => 8,
            T => 2
        )
        PORT MAP(
            clk => clk,
            rst => rst,
            data_in => data_in,
            data_valid => data_valid,
            code_out => code_out,
            code_valid => code_valid
        );
END ARCHITECTURE;
