--one_hot_encoder
--binary_in takes a 8 bit vector in
--next clk the one hot encoding of binary_in is retuned on one_hot_out 
--NOTE: if binary_in is x"FF" (255) the output is all zeroes

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY one_hot_encoder IS 
	GENERIC (
		M : INTEGER := 8); -- 2**M = length

	PORT (
		clk, rst : IN STD_LOGIC;

		-- Binary error-position input.
		-- For M = 8, this can represent values 0 to 255.
		binary_in : IN STD_LOGIC_VECTOR(M - 1 DOWNTO 0);

		-- One-hot error vector.
		-- For M = 8, this becomes STD_LOGIC_VECTOR(254 DOWNTO 0). This corresponds to the 255 BCH bits. 
		-- Note: parity is excluded and handled separately.
		one_hot_out : OUT STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0') 
	);
END ENTITY;

-- Note:
-- This is not always "one-hot", because the default/no-error state (binary_in = 255 (x"FF")) is all zeroes.
ARCHITECTURE RTL OF one_hot_encoder IS
BEGIN
    PROCESS (clk, rst)
	BEGIN
		IF rst = '1' THEN
			one_hot_out <= (OTHERS => '0');

		ELSIF (rising_edge(clk)) THEN 
			 -- For every index (i) in one_hot_out.
            for i in 0 to 2**M-2 LOOP

				-- If binary_in equals i, then output bit i is set to 1.
				-- All other output bits are set to 0.
                if (binary_in = std_logic_vector(to_unsigned(i, M))) then 
                    one_hot_out(i) <= '1';
                else
                    one_hot_out(i) <= '0';
                end if;

            end LOOP;

        END IF;
	END PROCESS;

END ARCHITECTURE;