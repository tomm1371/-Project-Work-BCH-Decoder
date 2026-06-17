LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;


ENTITY log_a_to_a_tabel IS
  PORT (
    -- Exponent/log input.
    -- For example:
    -- address = 0 means alpha^0
    -- address = 1 means alpha^1
    -- address = 37 means alpha^37
    address  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);

    -- GF(256) element output.
    -- For example:
    -- contents = alpha^address represented as an 8-bit vector.
    contents : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);

    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC
  );
END ENTITY log_a_to_a_tabel;


ARCHITECTURE rtl OF log_a_to_a_tabel IS

  TYPE LUT_type IS ARRAY (0 TO 255) OF STD_LOGIC_VECTOR(7 DOWNTO 0);

  -- Multiply by alpha in GF(2^8).
  --
  -- Primitive polynomial:
  --
  --   p(x) = x^8 + x^4 + x^3 + x^2 + 1
  --
  -- Hex representation: 0x11D
  -- After shifting left, if the x^8 term appears,
  -- we reduce back to 8 bits by XORing with 0x1D.
  FUNCTION multiply_by_alpha(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE shifted_v : UNSIGNED(7 DOWNTO 0);
  BEGIN

    shifted_v := a(6 DOWNTO 0) & '0';

    IF a(7) = '1' THEN
      shifted_v := shifted_v XOR TO_UNSIGNED(16#1D#, 8);
    END IF;

    RETURN shifted_v;

  END FUNCTION;


  -- Build alpha-power table.
  --
  -- This creates:
  --
  --   LUT(0)   = alpha^0
  --   LUT(1)   = alpha^1
  --   LUT(2)   = alpha^2
  --   ...
  --   LUT(254) = alpha^254
  --
  -- LUT(255) is not normally used for a real alpha-power in this code,
  -- so it is left as zero by default.
  FUNCTION build_alpha_lut RETURN LUT_type IS
    VARIABLE lut_v : LUT_type := (OTHERS => (OTHERS => '0'));
    VARIABLE a_v   : UNSIGNED(7 DOWNTO 0) := TO_UNSIGNED(1, 8);
  BEGIN

    FOR log_i IN 0 TO 254 LOOP
      lut_v(log_i) := STD_LOGIC_VECTOR(a_v);
      a_v := multiply_by_alpha(a_v);
    END LOOP;

    RETURN lut_v;

  END FUNCTION;


  CONSTANT LUT : LUT_type := build_alpha_lut;

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