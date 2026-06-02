LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY one_hot_encoder IS 
	GENERIC (
		M : INTEGER := 8); -- 2**m = length

	PORT (
		clk, rst : IN STD_LOGIC;
		binary_in : IN STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
		one_hot_out : OUT STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0') --length should be 254 
	);
END ENTITY;

--note: 
--not really one hot, since the defalut state is (OTHERS => '0')
ARCHITECTURE RTL OF one_hot_encoder IS
BEGIN
    PROCESS (clk, rst)
	BEGIN
		IF rst = '1' THEN
			one_hot_out <= (OTHERS => '0');

		ELSIF (rising_edge(clk)) THEN 
            for i in 0 to 2**M-2 LOOP

                --im pretty sure this is not the best vhdl way to do this, should work tho...
                if (binary_in = std_logic_vector(to_unsigned(i, M))) then 
                    one_hot_out(i) <= '1';
                else
                    one_hot_out(i) <= '0';
                end if;

            end LOOP;

        END IF;
	END PROCESS;

END ARCHITECTURE;