LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.codeword_encoder_pkg.ALL;


ENTITY codeword_encoder_reader IS
    GENERIC (
        DATA_WIDTH      : POSITIVE := CODEWORD_WIDTH;
        ROM_DEPTH       : POSITIVE := CODEWORD_COUNT;
        ROM_ADDR_WIDTH  : POSITIVE := CODEWORD_ADDR_WIDTH
    );
    PORT (
        clk       : IN  STD_LOGIC;
        rst       : IN  STD_LOGIC;
        start     : IN  STD_LOGIC;
        data_out  : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        data_valid: OUT STD_LOGIC;
        done      : OUT STD_LOGIC
    );
END ENTITY codeword_encoder_reader;

ARCHITECTURE rtl OF codeword_encoder_reader IS
    SIGNAL address : UNSIGNED(ROM_ADDR_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL active : STD_LOGIC := '0';
BEGIN
    data_out <= CODEWORD_ENCODER_ROM(TO_INTEGER(address));
    data_valid <= active;

    PROCESS (clk, rst)
    BEGIN
        IF rst = '1' THEN
            address <= (OTHERS => '0');
            active <= '0';
            done <= '0';
        ELSIF rising_edge(clk) THEN
            done <= '0';

            IF start = '1' THEN
                address <= (OTHERS => '0');
                active <= '1';
            ELSIF active = '1' THEN
                IF TO_INTEGER(address) = ROM_DEPTH - 1 THEN
                    active <= '0';
                    done <= '1';
                ELSE
                    address <= address + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;
END ARCHITECTURE rtl;
