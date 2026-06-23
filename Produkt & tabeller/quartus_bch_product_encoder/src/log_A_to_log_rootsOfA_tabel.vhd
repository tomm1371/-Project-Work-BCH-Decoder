LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY log_A_to_log_rootsOfA_tabel IS
  PORT (
    address  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);  -- log(A)
    contents : OUT STD_LOGIC_VECTOR(15 DOWNTO 0); -- log(root1) & log(root2)

    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC
  );
END ENTITY log_A_to_log_rootsOfA_tabel;


ARCHITECTURE log_A_to_log_rootsOfA_tabel_arch OF log_A_to_log_rootsOfA_tabel IS

  TYPE LUT8_type  IS ARRAY (0 TO 255) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
  TYPE LUT16_type IS ARRAY (0 TO 255) OF STD_LOGIC_VECTOR(15 DOWNTO 0);


  -- Multiply by alpha in GF(2^8).
  -- Primitive polynomial:
  --   p(x) = x^8 + x^4 + x^3 + x^2 + 1
  -- Hex representation: 0x11D.
  -- Multiplying by alpha corresponds to shifting left.
  -- If the old MSB was 1, the shift creates an x^8 term,
  -- so we reduce modulo p(x) by XORing with 0x1D.
  FUNCTION multiply_by_alpha(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE shifted_v : UNSIGNED(7 DOWNTO 0);
  BEGIN
    shifted_v := a(6 DOWNTO 0) & '0';

    IF a(7) = '1' THEN
      shifted_v := shifted_v XOR TO_UNSIGNED(16#1D#, 8);
    END IF;

    RETURN shifted_v;
  END FUNCTION;


  -- Build same table we've used earlier.
  -- Input/index is a log/exponent.
  -- Output is the concrete 8-bit GF(256) field element.
  FUNCTION build_alpha_lut RETURN LUT8_type IS
    VARIABLE lut_v : LUT8_type := (OTHERS => (OTHERS => '0'));
    VARIABLE a_v   : UNSIGNED(7 DOWNTO 0) := TO_UNSIGNED(1, 8);
  BEGIN
    FOR log_i IN 0 TO 254 LOOP
      lut_v(log_i) := STD_LOGIC_VECTOR(a_v);
      a_v := multiply_by_alpha(a_v);
    END LOOP;

    RETURN lut_v;
  END FUNCTION;


  -- Build the "other" table we've also made earlier.
  -- Input/index is the concrete 8-bit GF(256) field element interpreted as an integer address.
  -- Output is the log/exponent.
  FUNCTION build_log_lut RETURN LUT8_type IS
    VARIABLE lut_v : LUT8_type := (OTHERS => (OTHERS => '0'));
    VARIABLE a_v   : UNSIGNED(7 DOWNTO 0) := TO_UNSIGNED(1, 8);
  BEGIN
    FOR log_i IN 0 TO 254 LOOP
      lut_v(TO_INTEGER(a_v)) := STD_LOGIC_VECTOR(TO_UNSIGNED(log_i, 8));
      a_v := multiply_by_alpha(a_v);
    END LOOP;

    RETURN lut_v;
  END FUNCTION;


  -- Build table:
  --   LUT(log(A)) = log(root1) & log(root2)
  -- The roots are the two solutions to:
  --   z^2 + z + A = 0
  -- Equivalently, in characteristic 2:
  --   A = z^2 + z
  -- Since addition in GF(2^8) is XOR, this is:
  --   A = z^2 XOR z
  -- If no roots exist for a given A, the table entry remains x"FFFF".
  -- remember that A is defined as:
  -- A = (X*Y)/S_1^2, where X and Y are the field elements of the error positions.
  -- We need the logarithm of X and Y, since they are the error positions.
  FUNCTION build_roots_lut RETURN LUT16_type IS
    VARIABLE lut_v : LUT16_type := (OTHERS => x"FFFF");

    VARIABLE alpha_lut_v : LUT8_type := build_alpha_lut; -- This gives the field element from the log-value
    VARIABLE log_lut_v   : LUT8_type := build_log_lut; -- This gives the log-value from the field element.

    VARIABLE root_v           : UNSIGNED(7 DOWNTO 0); -- this is z
    VARIABLE root_square_v    : UNSIGNED(7 DOWNTO 0); -- this is z^2
    VARIABLE companion_v      : UNSIGNED(7 DOWNTO 0); -- in binary fields, if z is a root, then z+1 is also a root. This is z+1
    VARIABLE A_v              : UNSIGNED(7 DOWNTO 0); -- This is the result of A=z^2+z

    VARIABLE A_log_i          : INTEGER; -- This is log(A)
    VARIABLE companion_log_i  : INTEGER; -- log(z+1)
    VARIABLE square_log_i     : INTEGER; -- z=alpha^k => z^2=alpha^2k
  BEGIN

    -- The useful log values are 0..254 because alpha has order 255.
	 -- Therefore we manually set the final entry to be 0
    lut_v(255) := x"0000";

    -- Try every possible non-zero root z = alpha^root_log_i.
	 -- This is sometimes called Chien search.
    FOR root_log_i IN 0 TO 254 LOOP

      -- root_v = alpha^root_log_i
		-- So root_v will be the field-element corresponding to the exponent we are trying
      root_v := UNSIGNED(alpha_lut_v(root_log_i));

      -- root_square_v = (alpha^root_log_i)^2 = alpha^(2*root_log_i mod 255)
      square_log_i := (2 * root_log_i) MOD 255;
      root_square_v := UNSIGNED(alpha_lut_v(square_log_i));

      -- A = z^2 + z.
      -- In GF(2^8), addition is XOR, and we've defined A = z+z^2:
      A_v := root_square_v XOR root_v; -- now A is a specific field element.

      -- If A = 0, log(A) is undefined, so we do not store it.
		-- But all other cases we should handle, so a smart way is to just check if it is not equal to 0
      IF A_v /= TO_UNSIGNED(0, 8) THEN
        -- Alot of conversion here.
		  -- At this point, A_v is 8-bit field element
		  -- but we need log(A) as integer index
		  -- so we first get the integer address corresponding to the field element
		  -- then we check which index that field element is (the log-value).
		  -- 	example: to_integer(A_v)=29 => log_lut_v(29)=alpha^8=> return 8 as integer.
        A_log_i := TO_INTEGER(UNSIGNED(log_lut_v(TO_INTEGER(A_v))));

        -- For z^2 + z + A = 0, if z is one root, then z + 1 is the other root (as mentioned)
        -- In GF(2^8), +1 means XOR with 00000001, so:
        companion_v := root_v XOR TO_UNSIGNED(1, 8);
        -- Convert the second root from concrete 8-bit field element to its log/exponent (the index).
		  -- This is done in the same way as we did above.
        companion_log_i := TO_INTEGER(UNSIGNED(log_lut_v(TO_INTEGER(companion_v))));

        -- Store only the first root pair found for this A.
		  -- This is because the loop will later find that z+1 is also a solution for that A value
		  -- So to make sure we don't overwrite or change the first root,
		  -- we only write to the table, if it was "invalid" (value FFFF) in the first place.
        IF lut_v(A_log_i) = x"FFFF" THEN
          lut_v(A_log_i) :=
            STD_LOGIC_VECTOR(TO_UNSIGNED(root_log_i, 8)) &
            STD_LOGIC_VECTOR(TO_UNSIGNED(companion_log_i, 8));
				
			-- The result is a table that will have have the format:
			-- 	LUT(log(A)) = [log(z1),log(z2 (which is z1+1))], where the log values are both 8 bits.
        END IF;

      END IF;

    END LOOP;

    RETURN lut_v;
  END FUNCTION;


  CONSTANT LUT : LUT16_type := build_roots_lut;

BEGIN

  PROCESS (clk, rst)
  BEGIN
    IF rst = '1' THEN
      contents <= (OTHERS => '0');

    ELSIF rising_edge(clk) THEN
      contents <= LUT(TO_INTEGER(UNSIGNED(address)));

    END IF;
  END PROCESS;

END ARCHITECTURE log_A_to_log_rootsOfA_tabel_arch;