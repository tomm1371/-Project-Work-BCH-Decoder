
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY gf_mod IS
    GENERIC (
        M : INTEGER := 4;
        T : INTEGER := 2
    );
    PORT (
        clk, rst : IN STD_LOGIC;
        prev_result: IN STD_LOGIC_VECTOR(M * T - 1 DOWNTO 0);
        new_data_bit : IN STD_LOGIC;
        current_parity : IN STD_LOGIC;
        message_pass_in : IN STD_LOGIC_VECTOR(2 ** M - M * T - 1 - 1 DOWNTO 0);


        result : OUT STD_LOGIC_VECTOR(M * T - 1 DOWNTO 0);
        next_parity : OUT STD_LOGIC
        message_pass_out : OUT STD_LOGIC_VECTOR(2 ** M - M * T - 1 - 1 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE RTL OF gf_mod IS
    CONSTANT R : INTEGER := M * T;

    -- BCH(15,7) generator polynomial for m=4, t=2:
    -- g(x) = x^8 + x^7 + x^6 + x^4 + 1
    CONSTANT gen : STD_LOGIC_VECTOR(R DOWNTO 0) := "111010001";

BEGIN

    

    -- if most significant bit of prev_result is 1, we need to XOR with gen otherwise just shift
    PROCESS(clk, rst)
    BEGIN
        IF rst = '1' THEN
            result <= (OTHERS => '0');
            next_parity <= '0';
        ELSIF rising_edge(clk) THEN
            next_parity <= current_parity XOR new_data_bit; -- update parity bit for next round
            message_pass_out <= message_pass_in; -- pass the message bits through unchanged
            
            IF prev_result(R - 1) = '1' THEN
                result <= (prev_result(R - 2 DOWNTO 0) & new_data_bit) XOR gen(R - 1 DOWNTO 0);
            ELSE
                result <= prev_result(R - 2 DOWNTO 0) & new_data_bit;
            END IF;
            
        END IF;
    END PROCESS;

END ARCHITECTURE;