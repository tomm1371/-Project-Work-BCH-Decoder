LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;


ENTITY one_hot_encoder IS
  GENERIC (
    M : INTEGER := 8
  );
  PORT (
    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC;

    -- Binary error-position input.
    -- For M = 8, this can represent values 0 to 255.
    binary_in : IN STD_LOGIC_VECTOR(M - 1 DOWNTO 0);

    -- One-hot error vector.
    -- For M = 8, this becomes STD_LOGIC_VECTOR(254 DOWNTO 0),
    -- so it has 255 bits.
    --
    -- This corresponds to the 255 BCH bits.
    -- The extended parity bit is handled separately in the decoder.
    one_hot_out : OUT STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0')
  );
END ENTITY one_hot_encoder;


-- Note:
-- This is not strictly always "one-hot", because the default/no-error state
-- is all zeroes. For example, if binary_in = 255, no output bit matches,
-- so one_hot_out becomes all zeroes.
ARCHITECTURE RTL OF one_hot_encoder IS
BEGIN

  PROCESS (clk, rst)
  BEGIN

    IF rst = '1' THEN

      one_hot_out <= (OTHERS => '0');

    ELSIF rising_edge(clk) THEN

      -- Check every possible BCH bit position.
      -- For M = 8, this loop goes from 0 to 254.
      --
      -- If binary_in equals i, then output bit i is set to 1.
      -- All other output bits are set to 0.
      FOR i IN 0 TO 2 ** M - 2 LOOP

        IF binary_in = STD_LOGIC_VECTOR(to_unsigned(i, M)) THEN
          one_hot_out(i) <= '1';
        ELSE
          one_hot_out(i) <= '0';
        END IF;

      END LOOP;

    END IF;

  END PROCESS;

END ARCHITECTURE RTL;