LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;


ENTITY log_a_to_a_pow3_tabel IS
  PORT (
    -- Exponent/log input.
    --
    -- address = i
    --
    -- Output should then be:
    --
    -- contents = alpha^(3*i)
    --
    -- This is used when calculating S3 in the syndrome calculator.
    address  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);

    -- GF(256) element output.
    contents : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);

    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC
  );
END ENTITY log_a_to_a_pow3_tabel;


ARCHITECTURE rtl OF log_a_to_a_pow3_tabel IS

  TYPE LUT_type IS ARRAY (0 TO 255) OF STD_LOGIC_VECTOR(7 DOWNTO 0);

  -- Multiply by alpha in GF(2^8).
  --
  -- Primitive polynomial:
  --
  --   p(x) = x^8 + x^4 + x^3 + x^2 + 1
  --
  -- Hex representation:
  --
  --   0x11D
  --
  -- If shifting left creates an x^8 term, we reduce back
  -- to 8 bits by XORing with 0x1D.
  FUNCTION multiply_by_alpha(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE shifted_v : UNSIGNED(7 DOWNTO 0);
  BEGIN

    shifted_v := a(6 DOWNTO 0) & '0';

    IF a(7) = '1' THEN
      shifted_v := shifted_v XOR TO_UNSIGNED(x"1D", 8);
    END IF;

    RETURN shifted_v;

  END FUNCTION;


  -- Multiply by alpha^3.
  --
  -- This is the same as multiplying by alpha three times:
  --
  --   a * alpha^3 = (((a * alpha) * alpha) * alpha)
  --
  -- We use this because the S3 syndrome needs alpha^(3*i).
  FUNCTION multiply_by_alpha3(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE result_v : UNSIGNED(7 DOWNTO 0) := a;
  BEGIN

    FOR step IN 1 TO 3 LOOP
      result_v := multiply_by_alpha(result_v);
    END LOOP;

    RETURN result_v;

  END FUNCTION;


  -- Build alpha^(3*i) table.
  --
  -- This creates:
  --
  --   LUT(0)   = alpha^(3*0)   = alpha^0
  --   LUT(1)   = alpha^(3*1)   = alpha^3
  --   LUT(2)   = alpha^(3*2)   = alpha^6
  --   LUT(3)   = alpha^(3*3)   = alpha^9
  --   ...
  --
  -- In other words:
  --
  --   LUT(i) = alpha^(3*i)
  --
  -- The sequence repeats every 85 entries, because alpha has period 255
  -- and stepping by 3 cycles through 255 / gcd(255, 3) = 85 unique values.
  FUNCTION build_alpha_pow3_lut RETURN LUT_type IS
    VARIABLE lut_v : LUT_type := (OTHERS => (OTHERS => '0'));
    VARIABLE a_v   : UNSIGNED(7 DOWNTO 0) := TO_UNSIGNED(1, 8);
  BEGIN

    FOR log_i IN 0 TO 254 LOOP
      lut_v(log_i) := STD_LOGIC_VECTOR(a_v);
      a_v := multiply_by_alpha3(a_v);
    END LOOP;

    RETURN lut_v;

  END FUNCTION;


  CONSTANT LUT : LUT_type := build_alpha_pow3_lut;

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