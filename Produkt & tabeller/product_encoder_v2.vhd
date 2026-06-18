LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY product_encoder_v2 IS
  GENERIC (
    M : INTEGER := 8;
    T : INTEGER := 2
  );
  PORT (
    clk   : IN STD_LOGIC;
    reset : IN STD_LOGIC;

	 -- In this version, the module can accept one 239-bit row per clock whenever row_valid & row_ready = 1.
	 -- Therefore, all input will be treated as rows, hence the naming convention.
    row_valid : IN STD_LOGIC; -- is 1 when row_in contains one valid 239-bit data row.
    row_in    : IN STD_LOGIC_VECTOR(2 ** M - M * T - 2 DOWNTO 0); -- actual 239 bits.
    row_ready : OUT STD_LOGIC; -- This is set to 1 when the module is ready to receive data.

    codeword_valid : OUT STD_LOGIC; -- is 1 when codeword_out contains a valid encoded column codeword.
    codeword_out   : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- actual 256 bits output codeword.

    block_done : OUT STD_LOGIC -- is 1 when the final encoded column is sent.
  );
END ENTITY product_encoder_v2;

ARCHITECTURE rtl OF product_encoder_v2 IS

  CONSTANT BCH_DATA_BITS : INTEGER := 2 ** M - M * T - 1; -- 239
  CONSTANT BCH_CODE_BITS : INTEGER := 2 ** M; -- 256

  SUBTYPE bch_data_t IS STD_LOGIC_VECTOR(BCH_DATA_BITS - 1 DOWNTO 0); -- shorter name for a 239 bit vector
  SUBTYPE bch_code_t IS STD_LOGIC_VECTOR(BCH_CODE_BITS - 1 DOWNTO 0); -- shorter name for a 256 bit vector

  TYPE row_encoded_matrix_t IS ARRAY (0 TO BCH_DATA_BITS - 1) OF bch_code_t; -- 239x256 matrix. It is not 256x256, because we stream out while encoding the columns.

  -- The 2 matrices. One is taking inputs while the other is reading and sending the columns to the output part.
  SIGNAL matrix_A_s : row_encoded_matrix_t := (OTHERS => (OTHERS => '0'));
  SIGNAL matrix_B_s : row_encoded_matrix_t := (OTHERS => (OTHERS => '0'));

  -- Role signals. 0=A, 1=B.
  SIGNAL fill_matrix_s   : INTEGER RANGE 0 TO 1 := 0; -- Which matrix is receiving input rows.
  SIGNAL output_matrix_s : INTEGER RANGE 0 TO 1 := 0; -- which matrix is reading/sending columns.

  -- matrix_ready_s(0) = A, (1) = B. Is 1 in their respective indexes, when the row encoding is done.
  -- When the column-reading is started, it is set back to 0.
  SIGNAL matrix_ready_s : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";

  -- State signals.
  SIGNAL fill_busy_s   : STD_LOGIC := '0'; -- is 1 when the input matrix is receiving rows.
  SIGNAL output_busy_s : STD_LOGIC := '0'; -- is 1 when columns are being read and sent out.

  -- Counters.
  SIGNAL rows_fed_s       : INTEGER RANGE 0 TO BCH_DATA_BITS := 0; -- how many rows has the input-matrix sent to the encoder
  SIGNAL rows_collected_s : INTEGER RANGE 0 TO BCH_DATA_BITS := 0; -- how many rows has it received back from the encoder.
  SIGNAL cols_fed_s       : INTEGER RANGE 0 TO BCH_CODE_BITS := 0; -- How many cols has the output-matrix sent to its encoder
  SIGNAL cols_collected_s : INTEGER RANGE 0 TO BCH_CODE_BITS := 0; -- how many cols has it received back. In practice this also counts how many codewords we've sent out.

  -- Valid- and data signals for the 2 encoder instances. 
  -- input
  SIGNAL row_encoder_data_valid_s : STD_LOGIC := '0';
  SIGNAL row_encoder_data_in_s    : bch_data_t := (OTHERS => '0');
  -- output
  SIGNAL row_encoder_code_valid_s : STD_LOGIC;
  SIGNAL row_encoder_code_out_s   : bch_code_t;

  -- same here.
  SIGNAL col_encoder_data_valid_s : STD_LOGIC := '0';
  SIGNAL col_encoder_data_in_s    : bch_data_t := (OTHERS => '0');
  SIGNAL col_encoder_code_valid_s : STD_LOGIC;
  SIGNAL col_encoder_code_out_s   : bch_code_t; -- final output that we send along.

  -- This is the signal that is used in our internal logic to determine the OUT port.
  -- Some versions of VHDL wont allow you to ready OUT ports in internal combinational logic. Therefore, for good practice, we use a signal.
  -- It is 1 when we can accept an input row.
  SIGNAL row_ready_s : STD_LOGIC := '0';

  
  -- Create a column vector.
  -- After the row encoding is done, we have 239x256 matrix.
  -- matrix_A_s(0),matrix_A_s(1),..., matrix_A_s(238) are the rows
  -- so matrix_A_s(0)(col_v),...matrix_A_s(238)(col_v) will be the col_v'th column.
  FUNCTION get_column(
    mat           : row_encoded_matrix_t; -- which matrix
    column_number : INTEGER -- which column are we "creating".
  ) RETURN bch_data_t IS -- remember that bch_data_t is 239 bits
    VARIABLE column_input_v : bch_data_t := (OTHERS => '0');
    VARIABLE col_v          : INTEGER;
    VARIABLE in_bit_v       : INTEGER;
  BEGIN
  -- our codewords are written as (255 downto 0), meaning that index 255 is the "first" bit.
  -- therefore we "flip" the index to make sense in a left-to-right way of the matrix index.
    col_v := BCH_CODE_BITS - 1 - column_number; -- column-number 0 => col_v=255.

	 -- then we just take 1 bit from the respective rows and write them to the vector.
    FOR r IN 0 TO BCH_DATA_BITS - 1 LOOP
      in_bit_v := BCH_DATA_BITS - 1 - r; -- Flip the index-ordering so the first row (0) is the first bit (238) in the column-vector.
      column_input_v(in_bit_v) := mat(r)(col_v);
    END LOOP;

    RETURN column_input_v; -- returns the 239-bit vector we can use in the encoding.
  END FUNCTION;

BEGIN

	----------------------------------------------------------
						-- Encoding instances (2 of them).
	----------------------------------------------------------

	-- Row encoder mapping.
  row_bch_encoder_inst : ENTITY work.bch_encoder_256
    GENERIC MAP (
      M => M,
      T => T
    )
    PORT MAP (
      clk        => clk,
      reset      => reset,
      data_valid => row_encoder_data_valid_s,
      data_in    => row_encoder_data_in_s,
      code_valid => row_encoder_code_valid_s,
      code_out   => row_encoder_code_out_s
    );

	 -- Column encoder mapping.
  col_bch_encoder_inst : ENTITY work.bch_encoder_256
    GENERIC MAP (
      M => M,
      T => T
    )
    PORT MAP (
      clk        => clk,
      reset      => reset,
      data_valid => col_encoder_data_valid_s,
      data_in    => col_encoder_data_in_s,
      code_valid => col_encoder_code_valid_s,
      code_out   => col_encoder_code_out_s
    );

  -- Ready logic.
  -- a row will only be accepted if row_valid & row_ready_s = 1
  -- row_valid comes from upstream, so we only formulate when this module is ready to receive.
  row_ready_s <= '1' WHEN (
   -- Case 1 is if we're feeding rows, but we've not filled out the matrix yet (keep going).
    (fill_busy_s = '1' AND rows_fed_s < BCH_DATA_BITS)
	 OR
	-- Case 2 is if we're not filling a matrix, and this matrix is free.
    (fill_busy_s = '0' AND matrix_ready_s(fill_matrix_s) = '0' 
	 AND 
	 NOT ((output_busy_s = '1') AND (output_matrix_s = fill_matrix_s))) -- this part of Step 2 checks that the matrix we want to feed is not in column/output mode.
  ) 
  ELSE '0'; -- default to 0.

  row_ready <= row_ready_s; -- Finally we map to the OUT port.

	
	----------------------------------------------------------
						-- Main process.
	----------------------------------------------------------
  
  PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN

	 -- clear/default everything on reset.
      IF reset = '1' THEN

        matrix_A_s <= (OTHERS => (OTHERS => '0'));
        matrix_B_s <= (OTHERS => (OTHERS => '0'));

        fill_matrix_s <= 0;
        output_matrix_s <= 0;

        matrix_ready_s <= "00";

        fill_busy_s <= '0';
        output_busy_s <= '0';

        rows_fed_s <= 0;
        rows_collected_s <= 0;

        cols_fed_s <= 0;
        cols_collected_s <= 0;

        row_encoder_data_valid_s <= '0';
        row_encoder_data_in_s <= (OTHERS => '0');

        col_encoder_data_valid_s <= '0';
        col_encoder_data_in_s <= (OTHERS => '0');

        codeword_valid <= '0';
        codeword_out <= (OTHERS => '0');

        block_done <= '0';

      ELSE

		-- default relevant signals on a new clock
		-- Ensures the "pulse" logic.
        row_encoder_data_valid_s <= '0';
        row_encoder_data_in_s <= (OTHERS => '0');

        col_encoder_data_valid_s <= '0';
        col_encoder_data_in_s <= (OTHERS => '0');

        codeword_valid <= '0';
        codeword_out <= (OTHERS => '0');

        block_done <= '0';

		-- Step 1: accept new input_row.
        IF row_valid = '1' AND row_ready_s = '1' THEN -- handshake

		  -- Input data to the encoder module.
          row_encoder_data_valid_s <= '1';
          row_encoder_data_in_s <= row_in;
			 
		  -- Step 1A: we are starting the fill-procedure of rows.
		  -- Therefore we reset counters and set the "busy" flag.
          IF fill_busy_s = '0' THEN
            fill_busy_s <= '1';
            rows_fed_s <= 1;
            rows_collected_s <= 0;
          ELSE
		  -- Step 1B: We are already feeding a matrix, so we just incremenet counter on every new row.
            IF rows_fed_s = BCH_DATA_BITS - 1 THEN -- Explicitly mark that all 239 rows have now been fed. The value 239 is an indicator for later (index 239 is no longer databits).
              rows_fed_s <= BCH_DATA_BITS;
            ELSE
              rows_fed_s <= rows_fed_s + 1;
            END IF;
          END IF;

        END IF;

		-- Step 2: Receive encoded rows from the encoder (fill matrix).
		-- We check if the encoder has a valid codeword.
		-- We also have a security-check to see, if we're actually filling out a matrix.
		-- 	remember that fill_busy_s is 1 both when sending data to the encoder AND receiving the codewords back.
        IF row_encoder_code_valid_s = '1' AND fill_busy_s = '1' THEN

		  -- then we choose which matrix we're filling with codewords
          IF fill_matrix_s = 0 THEN -- remember that 0 is A and 1 is B.
            matrix_A_s(rows_collected_s) <= row_encoder_code_out_s;
          ELSE
            matrix_B_s(rows_collected_s) <= row_encoder_code_out_s;
          END IF;

			 --Check if it was the final encoded row.
			 -- if it was, we mark the matrix to be "ready" for column/output mode.
          IF rows_collected_s = BCH_DATA_BITS - 1 THEN
            matrix_ready_s(fill_matrix_s) <= '1';
				-- we are no longer busy, and reset counters.
            fill_busy_s <= '0';
            rows_fed_s <= 0;
            rows_collected_s <= 0;

          ELSE
            rows_collected_s <= rows_collected_s + 1; -- if we're not done, we just increment the counter and keep filling.
          END IF;
        END IF;

		-- Step 3 (2.5): Select column/output matrix.
		-- This block does not move or encode any data.
		-- It is more of a check-stop
		
		-- Check if the output side is busy.
		-- We only allow for 1 matrix in each mode at any time.
        IF output_busy_s = '0' THEN 

          IF matrix_ready_s(0) = '1' THEN -- is matrix A done with rows?
			 -- if it is, we reset counters and set/reset relevant flags.
            output_busy_s <= '1';
            output_matrix_s <= 0; -- 0 means that matrix A is selected as the output matrix.
            matrix_ready_s(0) <= '0';

            cols_fed_s <= 0;
            cols_collected_s <= 0;

            fill_matrix_s <= 1; -- Set matrix B to be the input matrix.
			
          ELSIF matrix_ready_s(1) = '1' THEN -- Same logic for matrix B
            output_busy_s <= '1';
            output_matrix_s <= 1;
            matrix_ready_s(1) <= '0';

            cols_fed_s <= 0;
            cols_collected_s <= 0;

            fill_matrix_s <= 0;

          END IF;

        END IF;

		  
		-- Step 4: Read columns and send them to encoder.
		
		-- From Step 3 output_busy_s was set to 1, so as long as we're not done, this if statement is true from the clock after step 3.
        IF output_busy_s = '1' AND cols_fed_s < BCH_CODE_BITS THEN

          col_encoder_data_valid_s <= '1'; -- No matter which matrix the columns should be taken from, we let the encoder know that we have a valid column for it.

			 -- Check which matrix we're reading columns from and send them to the encoder.
          IF output_matrix_s = 0 THEN
            col_encoder_data_in_s <= get_column(matrix_A_s, cols_fed_s); -- cols_fed_s is exactly the column_number.
          ELSE
            col_encoder_data_in_s <= get_column(matrix_B_s, cols_fed_s);
          END IF;

			 -- If we're done, we set the 256 value (same as 239 for Step 1)
          IF cols_fed_s = BCH_CODE_BITS - 1 THEN
            cols_fed_s <= BCH_CODE_BITS;
          ELSE -- increment the counter if we're not done.
            cols_fed_s <= cols_fed_s + 1;
          END IF;

        END IF;

		-- Step 5: Collect encoded columns and stream them out.
		-- We check if the encoder has a valid codeword ready
		-- we also have the same security check as step 2 to make sure we're not outputting codewords if no matrices in this mode.
        IF col_encoder_code_valid_s = '1' AND output_busy_s = '1' THEN 

		  -- Set OUT ports.
          codeword_out <= col_encoder_code_out_s;
          codeword_valid <= '1';

			 -- If we're done collecting (and therefore sending) columns, we reset counters/flags and mark that we're done.
          IF cols_collected_s = BCH_CODE_BITS - 1 THEN

            cols_collected_s <= 0;
            cols_fed_s <= 0;
            output_busy_s <= '0';
            block_done <= '1';

          ELSE

            cols_collected_s <= cols_collected_s + 1; -- otherwise we just increment the counter and keep going.

          END IF;

        END IF;

      END IF;

    END IF;
  END PROCESS;

END ARCHITECTURE rtl;