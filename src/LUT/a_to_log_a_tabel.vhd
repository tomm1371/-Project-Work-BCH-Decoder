LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;


ENTITY a_to_log_a_tabel IS
  PORT (
    address  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0); -- GF(256) element
    contents : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- log_alpha(address)

    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC
  );
END ENTITY a_to_log_a_tabel;


ARCHITECTURE rtl OF a_to_log_a_tabel IS

  TYPE LUT_type IS ARRAY (0 TO 255) OF STD_LOGIC_VECTOR(7 DOWNTO 0);

  -- Multiply by alpha in GF(2^8).
  --
  -- The field used here is the common GF(256) field with primitive
  -- polynomial:
  --
  --   p(x) = x^8 + x^4 + x^3 + x^2 + 1
  --
  -- In hexadecimal this is 0x11D.
  -- When the shifted-out bit is 1, the lower 8-bit reduction value is 0x1D.
  -- We are basically alpha^i+1 from alpha^i to use in the generation of the table
  FUNCTION multiply_by_alpha(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE shifted_v : UNSIGNED(7 DOWNTO 0);
  BEGIN

    shifted_v := a(6 DOWNTO 0) & '0';

    IF a(7) = '1' THEN
      shifted_v := shifted_v XOR TO_UNSIGNED(16#1D#, 8);
    END IF;

    RETURN shifted_v;

  END FUNCTION;


  -- Build log table.
  --
  -- This creates:
  --
  --   LUT(alpha^0)   = 0
  --   LUT(alpha^1)   = 1
  --   LUT(alpha^2)   = 2
  --   ...
  --   LUT(alpha^254) = 254
  --
  -- Address 0 is not a real alpha-power in GF(256), so it is kept as 0.
  FUNCTION build_log_lut RETURN LUT_type IS
    VARIABLE lut_v : LUT_type := (OTHERS => (OTHERS => '0'));
    VARIABLE a_v   : UNSIGNED(7 DOWNTO 0) := TO_UNSIGNED(1, 8);
  BEGIN

    FOR log_i IN 0 TO 254 LOOP
      lut_v(TO_INTEGER(a_v)) := STD_LOGIC_VECTOR(TO_UNSIGNED(log_i, 8));
      a_v := multiply_by_alpha(a_v);
    END LOOP;

    RETURN lut_v;

  END FUNCTION;


  CONSTANT LUT : LUT_type := build_log_lut;

BEGIN

  PROCESS (clk, rst)
  BEGIN

    IF rst = '1' THEN

      contents <= (OTHERS => '0');

    ELSIF rising_edge(clk) THEN

      contents <= LUT(TO_INTEGER(UNSIGNED(address)));

    END IF;

  END PROCESS;

END ARCHITECTURE rtl;