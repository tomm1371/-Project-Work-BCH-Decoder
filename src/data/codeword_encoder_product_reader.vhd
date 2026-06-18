LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.codeword_encoder_pkg.ALL;

ENTITY codeword_encoder_product_reader IS
    GENERIC (
        DATA_WIDTH      : POSITIVE := CODEWORD_WIDTH;
        ROM_DEPTH       : POSITIVE := CODEWORD_COUNT;
        ROM_ADDR_WIDTH  : POSITIVE := CODEWORD_ADDR_WIDTH
    );
    PORT (
        clk       : IN  STD_LOGIC;
        rst       : IN  STD_LOGIC;
        start     : IN  STD_LOGIC;
        busy      : IN  STD_LOGIC; -- New busy signal to control reading
        data_out  : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        data_valid: OUT STD_LOGIC;
        done      : OUT STD_LOGIC
    );
END ENTITY codeword_encoder_product_reader;

ARCHITECTURE rtl OF codeword_encoder_product_reader IS
    SIGNAL address : UNSIGNED(ROM_ADDR_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL active : STD_LOGIC := '0';
BEGIN
    PROCESS (clk, rst)
    BEGIN
        IF rst = '1' THEN
            address <= (OTHERS => '0');
            active <= '0';
            done <= '0';
            data_valid <= '0';
            data_out <= (OTHERS => '0');

        ELSIF RISING_EDGE(clk) THEN
            done <= '0';
            data_valid <= '0';

            IF start = '1' AND busy = '0' THEN
                address <= (OTHERS => '0');
                active <= '1';

            ELSIF active = '1' THEN
                IF busy = '0' THEN -- pause when busy, hold address
                    data_out <= CODEWORD_ENCODER_ROM(TO_INTEGER(address));
                    data_valid <= '1';

                    IF TO_INTEGER(address) = ROM_DEPTH - 1 THEN
                        active <= '0';
                        done <= '1';
                    ELSE
                        address <= address + 1;
                    END IF;
                END IF;
                -- busy = '1': address holds, data_valid stays '0', encoder stalls
            END IF;

        END IF;
    END PROCESS;
END ARCHITECTURE rtl;