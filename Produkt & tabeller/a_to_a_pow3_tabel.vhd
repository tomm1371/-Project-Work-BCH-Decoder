LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY a_to_a_pow3_tabel IS
  PORT (
    address  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0); -- GF(256) element A
    contents : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- A^3

    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC
  );
END ENTITY a_to_a_pow3_tabel;

ARCHITECTURE a_to_a_pow3_tabel_arch OF a_to_a_pow3_tabel IS

  TYPE LUT_type IS ARRAY (0 TO 255) OF STD_LOGIC_VECTOR(7 DOWNTO 0);

  -- Multiplication by alpha in GF(2^8).
  -- We use the primitive polynomial:
  --   p(x) = x^8 + x^4 + x^3 + x^2 + 1
  -- Hex representation: 0x11D.
  -- Multiplying by alpha corresponds to shifting left.
  -- If the shift creates an x^8 term, we reduce modulo p(x),
  -- which corresponds to XOR with 0x1D.
  FUNCTION multiply_by_alpha(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE shifted_v : UNSIGNED(7 DOWNTO 0);
  BEGIN
    shifted_v := a(6 DOWNTO 0) & '0';

    IF a(7) = '1' THEN
      shifted_v := shifted_v XOR TO_UNSIGNED(16#1D#, 8);
    END IF;

    RETURN shifted_v;
  END FUNCTION;


  -- General multiplication in GF(2^8).
  -- To do binary multiplication, we look at one of the bit-vectors
  -- Every time this vector (b in our case) is 1, it means we have to "add" a value of a
  -- but not just the same value of a. Every time b is shifted once, it means the "weight" (binary value) is different
  -- therefore we must shift the a-value to match the specific nonzero b-value.
  -- Normally in binary multiplication, we add with carry, but here we have GF(2^8) so we use XOR
  -- That way there is no carry.
  FUNCTION gf_multiply(
    a : UNSIGNED(7 DOWNTO 0);
    b : UNSIGNED(7 DOWNTO 0)
  ) RETURN UNSIGNED IS
    VARIABLE aa_v     : UNSIGNED(7 DOWNTO 0) := a;
    VARIABLE bb_v     : UNSIGNED(7 DOWNTO 0) := b;
    VARIABLE result_v : UNSIGNED(7 DOWNTO 0) := (OTHERS => '0');
  BEGIN
    FOR bit_i IN 0 TO 7 LOOP

      IF bb_v(0) = '1' THEN -- Check if the current value is a 1 (meaning it should be XORed in)
        result_v := result_v XOR aa_v;
      END IF;

      bb_v := '0' & bb_v(7 DOWNTO 1); -- shift b to the right (next bit to LSB which is what we are checking above)
      aa_v := multiply_by_alpha(aa_v); -- "shift" a by multiplying it by alpha, which is exactly the same as a left-shift mod p(x)

    END LOOP;

    RETURN result_v;
  END FUNCTION;


  -- Cube a field element.
  -- This is rather self-explanatory.
  FUNCTION gf_pow3(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE square_v : UNSIGNED(7 DOWNTO 0);
    VARIABLE cube_v   : UNSIGNED(7 DOWNTO 0);
  BEGIN
    square_v := gf_multiply(a, a);
    cube_v   := gf_multiply(square_v, a);

    RETURN cube_v;
  END FUNCTION;


  -- Build table:
  --   LUT(A) = A^3
  -- Here A is not a log/exponent.
  -- A is the concrete 8-bit GF(256) representation used as an address given to the module.
  FUNCTION build_a_pow3_lut RETURN LUT_type IS
    VARIABLE lut_v : LUT_type := (OTHERS => (OTHERS => '0'));
    VARIABLE a_v   : UNSIGNED(7 DOWNTO 0);
  BEGIN
    FOR address_i IN 0 TO 255 LOOP
      a_v := TO_UNSIGNED(address_i, 8); -- make the adress (integer) an 8-bit representation (field-element)
      lut_v(address_i) := STD_LOGIC_VECTOR(gf_pow3(a_v)); -- that address then has the cubed field-element.
    END LOOP;

    RETURN lut_v; -- Example: address=29 -> a_v=00011101 -> alpha^8 -> LUT(29)=(00011101)^3=(alpha^8)^3=alpha^24 
  END FUNCTION;


  CONSTANT LUT : LUT_type := build_a_pow3_lut;

BEGIN

  PROCESS (clk, rst)
  BEGIN
    IF rst = '1' THEN
      contents <= (OTHERS => '0');

    ELSIF rising_edge(clk) THEN
      contents <= LUT(TO_INTEGER(UNSIGNED(address))); -- in practice the input adress is given as a 8-bit field element, and the return will just be the cubed field-element (8-bit rep that is).

    END IF;
  END PROCESS;

END ARCHITECTURE a_to_a_pow3_tabel_arch;