LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY tb_product_encoder IS
END ENTITY tb_product_encoder;

ARCHITECTURE sim OF tb_product_encoder IS

  CONSTANT M : INTEGER := 8;
  CONSTANT T : INTEGER := 2;

  CONSTANT BCH_DATA_BITS    : INTEGER := 2 ** M - M * T - 1; -- 239
  CONSTANT BCH_CODE_BITS    : INTEGER := 2 ** M;             -- 256
  CONSTANT BCH_PARITY_BITS  : INTEGER := M * T;              -- 16
  CONSTANT PRODUCT_IN_BITS  : INTEGER := BCH_DATA_BITS * BCH_DATA_BITS;
  CONSTANT PRODUCT_OUT_BITS : INTEGER := BCH_CODE_BITS * BCH_CODE_BITS;
  CONSTANT CLK_PERIOD       : TIME := 10 ns; -- Might want to change this to test possible speed.

  CONSTANT GEN_POLY : STD_LOGIC_VECTOR(BCH_PARITY_BITS DOWNTO 0) :=
    "10110111101100011";
  CONSTANT ZERO_PADDING : STD_LOGIC_VECTOR(BCH_PARITY_BITS - 1 DOWNTO 0) :=
    (OTHERS => '0');

  SUBTYPE bch_data_t    IS STD_LOGIC_VECTOR(BCH_DATA_BITS - 1 DOWNTO 0);
  SUBTYPE bch_code_t    IS STD_LOGIC_VECTOR(BCH_CODE_BITS - 1 DOWNTO 0);
  SUBTYPE product_in_t  IS STD_LOGIC_VECTOR(PRODUCT_IN_BITS - 1 DOWNTO 0);
  SUBTYPE product_out_t IS STD_LOGIC_VECTOR(PRODUCT_OUT_BITS - 1 DOWNTO 0);

  TYPE input_matrix_t IS ARRAY (0 TO BCH_DATA_BITS - 1) OF bch_data_t;
  TYPE row_code_matrix_t IS ARRAY (0 TO BCH_DATA_BITS - 1) OF bch_code_t;
  TYPE output_matrix_t IS ARRAY (0 TO BCH_CODE_BITS - 1) OF bch_code_t;

  SIGNAL clk           : STD_LOGIC := '0';
  SIGNAL reset         : STD_LOGIC := '0';
  SIGNAL data_valid    : STD_LOGIC := '0';
  SIGNAL data_in       : product_in_t := (OTHERS => '0');
  SIGNAL product_valid : STD_LOGIC;
  SIGNAL product_out   : product_out_t;

  FUNCTION xor_reduce(vec : STD_LOGIC_VECTOR) RETURN STD_LOGIC IS
    VARIABLE result_v : STD_LOGIC := '0';
  BEGIN
    FOR i IN vec'RANGE LOOP
      result_v := result_v XOR vec(i);
    END LOOP;
    RETURN result_v;
  END FUNCTION;

  -- Independent reference model for one extended BCH(256,239) encoding.
  -- This is the same logic as is used in the pipelined version
  -- but this reference model does not use states, is not pipelined, is not clocked and does not use "valid" signals.
  -- It is just to calculate the expected result, and then we can compare it to the hardware-friendly version.
  -- The main difference in VHDL is that we only use variables and not signals.
  -- This is just pure "math" and no hardware friendly logic.
  FUNCTION reference_bch_encode(data_v : bch_data_t) RETURN bch_code_t IS
    VARIABLE dividend_v  : STD_LOGIC_VECTOR(BCH_DATA_BITS + BCH_PARITY_BITS - 1 DOWNTO 0);
    VARIABLE remainder_v : STD_LOGIC_VECTOR(BCH_PARITY_BITS - 1 DOWNTO 0) := (OTHERS => '0');
    VARIABLE shifted_v   : STD_LOGIC_VECTOR(BCH_PARITY_BITS - 1 DOWNTO 0);
    VARIABLE codeword_v  : bch_code_t := (OTHERS => '0');
  BEGIN
    dividend_v := data_v & ZERO_PADDING; -- zero padding to allow for systematic encoding

    -- Same division as is done in the main file. This is just not clocked.
    FOR bit_index IN dividend_v'HIGH DOWNTO dividend_v'LOW LOOP
      shifted_v := remainder_v(BCH_PARITY_BITS - 2 DOWNTO 0) & dividend_v(bit_index);

      IF remainder_v(BCH_PARITY_BITS - 1) = '1' THEN
        remainder_v := shifted_v XOR GEN_POLY(BCH_PARITY_BITS - 1 DOWNTO 0);
      ELSE
        remainder_v := shifted_v;
      END IF;
    END LOOP;

    -- Make the output systematic:
    codeword_v(BCH_CODE_BITS - 1 DOWNTO BCH_PARITY_BITS + 1) := data_v;
    codeword_v(BCH_PARITY_BITS DOWNTO 1) := remainder_v;
    codeword_v(0) := xor_reduce(data_v) XOR xor_reduce(remainder_v);

    RETURN codeword_v;
  END FUNCTION;

  -- This reference model is for the product version. Now we check if it works for the full 239*239 bits and the structure is correct.
  FUNCTION reference_product_encode(flat_input_v : product_in_t) RETURN product_out_t IS
    VARIABLE input_matrix_v : input_matrix_t;
    VARIABLE row_codes_v    : row_code_matrix_t;
    VARIABLE output_matrix_v : output_matrix_t := (OTHERS => (OTHERS => '0'));
    VARIABLE column_data_v  : bch_data_t;
    VARIABLE column_code_v  : bch_code_t;
    VARIABLE expected_v     : product_out_t := (OTHERS => '0');
    VARIABLE row_high_v     : INTEGER;
    VARIABLE row_low_v      : INTEGER;
    VARIABLE col_v          : INTEGER;
  BEGIN
    -- Unpack the flat input into 239 rows, exactly as the clocked version does it.
    FOR row IN 0 TO BCH_DATA_BITS - 1 LOOP
      row_high_v := PRODUCT_IN_BITS - 1 - row * BCH_DATA_BITS;
      row_low_v  := row_high_v - BCH_DATA_BITS + 1;
      input_matrix_v(row) := flat_input_v(row_high_v DOWNTO row_low_v);
    END LOOP;

    -- Encode all 239 rows with the same logic that gf_mod_256 does.
    FOR row IN 0 TO BCH_DATA_BITS - 1 LOOP
      row_codes_v(row) := reference_bch_encode(input_matrix_v(row));
    END LOOP;

    -- Then we create the column vectors and encode them.
    FOR column IN 0 TO BCH_CODE_BITS - 1 LOOP
      col_v := BCH_CODE_BITS - 1 - column;

      FOR row IN 0 TO BCH_DATA_BITS - 1 LOOP
        column_data_v(BCH_DATA_BITS - 1 - row) := row_codes_v(row)(col_v);
      END LOOP;

      column_code_v := reference_bch_encode(column_data_v);

      FOR row IN 0 TO BCH_CODE_BITS - 1 LOOP
        output_matrix_v(row)(col_v) := column_code_v(BCH_CODE_BITS - 1 - row);
      END LOOP;
    END LOOP;

    -- Then we reflatten the output so we can directly compare EVERY bit.
    FOR row IN 0 TO BCH_CODE_BITS - 1 LOOP
      row_high_v := PRODUCT_OUT_BITS - 1 - row * BCH_CODE_BITS;
      row_low_v  := row_high_v - BCH_CODE_BITS + 1;
      expected_v(row_high_v DOWNTO row_low_v) := output_matrix_v(row);
    END LOOP;

    RETURN expected_v;
  END FUNCTION;

BEGIN

  clk <= NOT clk AFTER CLK_PERIOD / 2;

  dut : ENTITY work.product_encoder
    GENERIC MAP (
      M => M,
      T => T
    )
    PORT MAP (
      clk           => clk,
      reset         => reset,
      data_valid    => data_valid,
      data_in       => data_in,
      product_valid => product_valid,
      product_out   => product_out
    );

  -- Main process
  stimulus_process : PROCESS
    VARIABLE test_input_v      : product_in_t := (OTHERS => '0'); -- Empty vector that will contain the test data (for both experiments)
    VARIABLE expected_output_v : product_out_t; -- The output that the reference model calculates (so we can compare)
    VARIABLE input_index_v     : INTEGER; -- is used for the assymmetric test. Explanation when relevant.

	 -- We use a procedure since we want to do different tests (both an all-zero and an asymmetric case)
	 -- The only difference is the input data, so to save space in the code.
	 -- If you don't know VHDL that well, just think of a procedure as a classic function/method in software.
    PROCEDURE run_test(
      CONSTANT test_name_v : IN STRING; -- Name the test we're running
      CONSTANT test_data_v : IN product_in_t -- Give the input vector that we want to test.
    ) 
	 IS
      VARIABLE timeout_v : INTEGER := 0; -- Timeout if product_valid never arrives from DUT.
    BEGIN
      expected_output_v := reference_product_encode(test_data_v); -- Load the reference models answer

		-- Then we send the testdata to DUT
      data_in <= test_data_v;
      data_valid <= '1';
      WAIT UNTIL rising_edge(clk);
      data_valid <= '0';

		-- Timeout logic. Make sure we dont wait forever if an error has happened.
		-- It should never take 3000 clocks :)
      WHILE product_valid /= '1' LOOP
        WAIT UNTIL rising_edge(clk);
        timeout_v := timeout_v + 1;

        ASSERT timeout_v < 3000
          REPORT "ERROR: " & test_name_v & " timed out waiting for product_valid."
          SEVERITY FAILURE;
      END LOOP;

		-- Check if the answer from DUT is exactly the same as the reference models answer.
      ASSERT product_out = expected_output_v
        REPORT "ERROR: " & test_name_v & " did not match the reference product encoder."
        SEVERITY FAILURE;

      REPORT "PASS: " & test_name_v SEVERITY NOTE;

      -- To not end with race-conditions, we allow the DUT 1 extra clock to return to the initial state in its FSM.
      WAIT UNTIL rising_edge(clk);
    END PROCEDURE;

  BEGIN
    -- Reset all state first (and let the DUT settle so we give a few extra clocks).
    reset <= '1';
    data_valid <= '0';
    data_in <= (OTHERS => '0');

    WAIT FOR 5 * CLK_PERIOD;
    WAIT UNTIL rising_edge(clk);
    reset <= '0';
    WAIT UNTIL rising_edge(clk);

    -- Test 1: We use only 0's and expect only 0's.
    test_input_v := (OTHERS => '0');
    run_test("all-zero input", test_input_v); -- Even though we expect all zeros, we can also check the reference model in this one.

    -- Test 2: Actual data. In this test, a more "random" and asymmetric input vector is created.
	 -- Using some pseudo-random formula, the loop will add 1's at many different spots in the input vector.
    test_input_v := (OTHERS => '0');
    FOR row IN 0 TO BCH_DATA_BITS - 1 LOOP
      FOR column IN 0 TO BCH_DATA_BITS - 1 LOOP
        IF ((7 * row + 3 * column + row / 5) MOD 13) < 6 THEN
          input_index_v := PRODUCT_IN_BITS - 1 - (row * BCH_DATA_BITS + column);
          test_input_v(input_index_v) := '1';
        END IF;
      END LOOP;
    END LOOP;

    run_test("asymmetric non-zero input", test_input_v);

   REPORT "PASS: all product encoder tests completed." SEVERITY NOTE;

	ASSERT FALSE
	REPORT "Simulation finished."
	SEVERITY FAILURE;

	WAIT;
  END PROCESS;

END ARCHITECTURE sim;
