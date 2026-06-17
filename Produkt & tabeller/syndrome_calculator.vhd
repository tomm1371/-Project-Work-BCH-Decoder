-- syndrome_calculator
--
-- Takes one received extended BCH(256,239)-style codeword
-- and calculates:
-- S1 = r(alpha)
-- S3 = r(alpha^3)
-- data_parity = XOR of all 256 received bit
-- The input data is delayed through a small pipeline so that data_out
-- and data_out_valid are aligned with S1, S3 and data_parity.

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;


ENTITY syndrome_calculator IS
  GENERIC (
    M : INTEGER := 8; -- log2(code length), so 2^M = 256
    T : INTEGER := 2  -- error correction capability
  );
  PORT (
    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC;

    data_in    : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
    data_valid : IN STD_LOGIC;

    data_out       : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- Same data we were given (we want to send this along the pipeline)
    data_out_valid : OUT STD_LOGIC;

    -- 0 means even parity, 1 means odd parity.
	 -- This is used to seperate cases in the decoder.
    data_parity : OUT STD_LOGIC;

    -- BCH syndromes used to correct the error(s).
    S1 : OUT STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
    S3 : OUT STD_LOGIC_VECTOR(M - 1 DOWNTO 0)
  );
END ENTITY syndrome_calculator;


ARCHITECTURE RTL OF syndrome_calculator IS

  CONSTANT clk_cycles : INTEGER := 8; -- We use 8 cycles to finish the XOR tree.

  -- Delay line for the received codeword and its valid bit.
  -- The MSB stores data_valid.
  -- The lower 256 bits store data_in.
  TYPE data_array IS ARRAY (1 TO clk_cycles)
    OF STD_LOGIC_VECTOR(2 ** M DOWNTO 0);

  SIGNAL raw_data_array : data_array := (OTHERS => (OTHERS => '0'));


  -- LUT type for GF(256) elements.
  TYPE LUT_type IS ARRAY (0 TO 255) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
  -- Multiply by alpha in GF(2^8).
  -- Primitive polynomial:
  --   p(x) = x^8 + x^4 + x^3 + x^2 + 1
  -- Hex: 0x11D.
  -- After shifting left, if an x^8 term appears, reduce back to 8 bits
  -- by XORing with 0x1D.
  FUNCTION multiply_by_alpha(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE shifted_v : UNSIGNED(7 DOWNTO 0);
  BEGIN
    shifted_v := a(6 DOWNTO 0) & '0';

    IF a(7) = '1' THEN
      shifted_v := shifted_v XOR TO_UNSIGNED(16#1D#, 8);
    END IF;

    RETURN shifted_v;
  END FUNCTION;


  -- Multiply by alpha^3.
  -- This is used for the S3 syndrome.
  FUNCTION multiply_by_alpha3(a : UNSIGNED(7 DOWNTO 0)) RETURN UNSIGNED IS
    VARIABLE result_v : UNSIGNED(7 DOWNTO 0) := a;
  BEGIN
    FOR step IN 1 TO 3 LOOP
      result_v := multiply_by_alpha(result_v);
    END LOOP;

    RETURN result_v;
  END FUNCTION;


  -- Build table:
  --   LOG_A_TO_A_LUT(i) = alpha^i
  -- Used for S1 contributions.
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


  -- Build table:
  --   LOG_A_TO_A_POW3_LUT(i) = alpha^(3*i)
  -- Used for S3 contributions.
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


  CONSTANT LOG_A_TO_A_LUT      : LUT_type := build_alpha_lut;
  CONSTANT LOG_A_TO_A_POW3_LUT : LUT_type := build_alpha_pow3_lut;


  -- Each entry in the XOR tree contains:
  -- bit 16            = parity contribution
  -- bits 15 downto 8  = S1 contribution
  -- bits 7 downto 0   = S3 contribution
  -- For M=8 and T=2, M*T = 16, so each vector is 17 bits.
  TYPE t8 IS ARRAY (2 ** 8 - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(M * T DOWNTO 0);
  TYPE t7 IS ARRAY (2 ** 7 - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(M * T DOWNTO 0);
  TYPE t6 IS ARRAY (2 ** 6 - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(M * T DOWNTO 0);
  TYPE t5 IS ARRAY (2 ** 5 - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(M * T DOWNTO 0);
  TYPE t4 IS ARRAY (2 ** 4 - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(M * T DOWNTO 0);
  TYPE t3 IS ARRAY (2 ** 3 - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(M * T DOWNTO 0);
  TYPE t2 IS ARRAY (2 ** 2 - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(M * T DOWNTO 0);
  TYPE t1 IS ARRAY (2 - 1 DOWNTO 0)      OF STD_LOGIC_VECTOR(M * T DOWNTO 0);

  SIGNAL xor_array8 : t8 := (OTHERS => (OTHERS => '0'));
  SIGNAL xor_array7 : t7 := (OTHERS => (OTHERS => '0'));
  SIGNAL xor_array6 : t6 := (OTHERS => (OTHERS => '0'));
  SIGNAL xor_array5 : t5 := (OTHERS => (OTHERS => '0'));
  SIGNAL xor_array4 : t4 := (OTHERS => (OTHERS => '0'));
  SIGNAL xor_array3 : t3 := (OTHERS => (OTHERS => '0'));
  SIGNAL xor_array2 : t2 := (OTHERS => (OTHERS => '0'));
  SIGNAL xor_array1 : t1 := (OTHERS => (OTHERS => '0'));

BEGIN

  P1 : PROCESS (clk, rst)
  BEGIN

    IF rst = '1' THEN

      data_parity    <= '0';
      data_out       <= (OTHERS => '0');
      data_out_valid <= '0';

      raw_data_array <= (OTHERS => (OTHERS => '0'));

      S1 <= (OTHERS => '0');
      S3 <= (OTHERS => '0');

      xor_array8 <= (OTHERS => (OTHERS => '0'));
      xor_array7 <= (OTHERS => (OTHERS => '0'));
      xor_array6 <= (OTHERS => (OTHERS => '0'));
      xor_array5 <= (OTHERS => (OTHERS => '0'));
      xor_array4 <= (OTHERS => (OTHERS => '0'));
      xor_array3 <= (OTHERS => (OTHERS => '0'));
      xor_array2 <= (OTHERS => (OTHERS => '0'));
      xor_array1 <= (OTHERS => (OTHERS => '0'));


    ELSIF rising_edge(clk) THEN
      -- Clock stage 0:
      -- Create one contribution per received bit.
      xor_array8(0)(M * T - 1 DOWNTO 0) <= (OTHERS => '0'); -- This is the overall parrity bit-package. It should NOT contribute to the syndromes, and it is therefore explicitly set to 0 in the initial xor_array.
      -- Store valid bit in the delay pipeline
      raw_data_array(1)(2 ** M) <= data_valid;

      IF data_valid = '1' THEN

        -- If the input data is valid, we store it in the pipeline.
		  -- Remember that this is the original message and the valid bit with it.
        raw_data_array(1)(2 ** M - 1 DOWNTO 0) <= data_in;

        -- Overall parity contribution from all 256 bits.
		  -- This will set the 16th bit of every syndrome-parity-package to contain the information bit of the codeword.
		  -- Later when every packet is XORed together, the 16th bit in the final vector will directly correspond to the overall parity.
        FOR i IN 0 TO (2 ** 8) - 1 LOOP
          xor_array8(i)(M * T) <= data_in(i);
        END LOOP;

        -- Syndrome contributions from BCH bits only (data_in(1)-data_in(255))
        -- data_in(1)   corresponds to alpha^0
        -- data_in(2)   corresponds to alpha^1
        -- data_in(255) corresponds to alpha^254
		  -- Because data_in(0) should not contribute, the loop will start from 1.
        FOR i IN 1 TO (2 ** 8) - 1 LOOP
			 -- We simply check if the bit is 1, and if it is, it should contribute to both syndromes
			 -- Since M*T-1=15 the bottom 16 bits wil get 8 bit representation of alpha^i-1 and the 8 bit representation of alpha^3(i-1)
          IF data_in(i) = '1' THEN
            xor_array8(i)(M * T - 1 DOWNTO 0) <= LOG_A_TO_A_LUT(i - 1) & LOG_A_TO_A_POW3_LUT(i - 1);
          ELSE
            xor_array8(i)(M * T - 1 DOWNTO 0) <= (OTHERS => '0');
          END IF;

        END LOOP;

      ELSE

        -- Because this module is pipelined, we cannot "stop" if the input is invalid
		  -- Therefore we should just fill in this "level" of the initial xor_array with all 0's
		  -- And of course also the delay pipeline with the initial codeword should also be cleared.
		  -- By doing this, the pipeline will not contain any invalid data from earlier "levels".
		  -- Remember that the raw_data_array will also contain the valid bit
		  -- So if this is 0, the rest of the decoder can simply ignore this "level".
        xor_array8(0)(M * T) <= '0';

        FOR i IN 1 TO (2 ** 8) - 1 LOOP
          xor_array8(i) <= (OTHERS => '0');
        END LOOP;

        raw_data_array(1)(2 ** M - 1 DOWNTO 0) <= (OTHERS => '0');

      END IF;


      -- Clock stages 1 to 7:
      -- Pipelined XOR tree to make each clock faster.
		-- It is assumed that having 8 fast clocks is better than 1 slow clock
		-- Since the critical path of the entire decoder is very important.

		-- The tree will simply XOR each pair in the array that is one factor larger than itself
		-- and then fill itself with the result.
		-- This works because each "packet" has exactly the same structure with [overall|S1|S3]
		-- so XOR will only "hit" its respective bits.
      FOR i IN 0 TO (2 ** 7) - 1 LOOP
        xor_array7(i) <= xor_array8(i * 2) XOR xor_array8(i * 2 + 1);
      END LOOP;

      FOR i IN 0 TO (2 ** 6) - 1 LOOP
        xor_array6(i) <= xor_array7(i * 2) XOR xor_array7(i * 2 + 1);
      END LOOP;

      FOR i IN 0 TO (2 ** 5) - 1 LOOP
        xor_array5(i) <= xor_array6(i * 2) XOR xor_array6(i * 2 + 1);
      END LOOP;

      FOR i IN 0 TO (2 ** 4) - 1 LOOP
        xor_array4(i) <= xor_array5(i * 2) XOR xor_array5(i * 2 + 1);
      END LOOP;

      FOR i IN 0 TO (2 ** 3) - 1 LOOP
        xor_array3(i) <= xor_array4(i * 2) XOR xor_array4(i * 2 + 1);
      END LOOP;

      FOR i IN 0 TO (2 ** 2) - 1 LOOP
        xor_array2(i) <= xor_array3(i * 2) XOR xor_array3(i * 2 + 1);
      END LOOP;

      FOR i IN 0 TO 1 LOOP
        xor_array1(i) <= xor_array2(i * 2) XOR xor_array2(i * 2 + 1);
      END LOOP;


      -- Clock stage 8:
      -- Now we only have 2 packets that represents 128 input bits.
		-- First we calculate the overall parity, which is the XOR of all bits in the final 2 packets.
      data_parity <= xor_array1(0)(M * T) XOR xor_array1(1)(M * T);

		-- Then S1 is the first 8 bits after the overall parity (bit 15 to 8) XORed with eachother
      S1 <= xor_array1(0)(M * T - 1 DOWNTO M)
            XOR xor_array1(1)(M * T - 1 DOWNTO M);

	   -- And S3 is the final 8 bits (bit 7 to 0)
      S3 <= xor_array1(0)(M - 1 DOWNTO 0)
            XOR xor_array1(1)(M - 1 DOWNTO 0);

	   -- Finally, after all stages are complete, we must remember that this module is pipelined
		-- This means that we have to make sure, that the output matches the codeword that was sent with it, because the XOR tree takes 8 clock cycles to complete.
		-- By doing this, the central decoding module can just rely solely on what it receives from this module
		-- Therefore we manually set data_out and data_out_valid to be the "final" stage of the raw_data_array register.
		
      data_out <= raw_data_array(clk_cycles)(2 ** M - 1 DOWNTO 0); -- remember that this reads the "old" version. Since this is a process, and data_out is a signal, it will first update on the next clk edge.
      data_out_valid <= raw_data_array(clk_cycles)(2 ** M);
		
		-- After we've set these, we push the pipeline 1 step forward.
      FOR i IN 1 TO clk_cycles - 1 LOOP
        raw_data_array(i + 1) <= raw_data_array(i);
      END LOOP;

    END IF;

  END PROCESS P1;

END ARCHITECTURE RTL;