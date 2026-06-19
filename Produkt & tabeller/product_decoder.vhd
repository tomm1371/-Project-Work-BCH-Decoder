LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY product_decoder IS
  GENERIC (
    M          : INTEGER := 8; -- This is usually fixed
    T          : INTEGER := 2; -- also fixed
    ITERATIONS : INTEGER := 3 -- This is what is varied in the simulations. By default we do 3 iterations.
  );
  PORT (
    clk   : IN STD_LOGIC;
    reset : IN STD_LOGIC;

	 -- We use the same convention logic here, as we did for rows in the encoder
	 -- Because we receive 256 bits pr. clock, and we treat all of them as columns to be inserted into the initial matrix
	 -- we call them column, but they might as well be called "data".
    column_valid : IN STD_LOGIC; -- is set by upstream module (TB in practice). indicates that column_in contains a valid codeword.
    column_in    : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- actual input column data vector.
    column_ready : OUT STD_LOGIC; -- This is SENT upstream to indicate that the decoder is ready for another column.

	 -- Output ports after decoding is finished
	 -- We keep the pipeline structure and in steady-state output 1 codeword pr. clock
	 -- Remember that the output is NOT sliced, so it still contains the parity bits.
    codeword_valid : OUT STD_LOGIC; -- codeword_out has valid codeword
    codeword_out   : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- decoded codeword.


    block_done : OUT STD_LOGIC -- this is set to 1 when all 256 columns from 1 product-code block are outputted after all iterations.
  );
END ENTITY product_decoder;

ARCHITECTURE rtl OF product_decoder IS

  CONSTANT BCH_CODE_BITS : INTEGER := 2 ** M; -- 256 (one codeword)
  CONSTANT NUM_PASSES    : INTEGER := 2 * ITERATIONS; -- Total number of BCH decoder passes. One iteration is one column pass and one row pass.

  SUBTYPE bch_code_t IS STD_LOGIC_VECTOR(BCH_CODE_BITS - 1 DOWNTO 0); -- Rename the vector for easier, more readable code.

  TYPE product_matrix_t IS ARRAY (0 TO BCH_CODE_BITS - 1) OF bch_code_t; -- 256x256 productcode matrix.
  -- At each pipeline stage, we need 2 matrices.
  -- This is because when matrix A is done, matrix B will have to read it
  -- but at the same time, new data is arriving, and we cannot overwrite matrix A before matrix B is done reading from it.
  -- Therefore we have 2 buffers at each stage of the pipeline.
  TYPE matrix_pair_t IS ARRAY (0 TO 1) OF product_matrix_t;
  -- finally we keep all pairs in one final array.
  -- Here, the generic ITERATIONS directly decides how many matrices we have to create.
  TYPE matrix_pipeline_t IS ARRAY (0 TO NUM_PASSES - 1) OF matrix_pair_t;

  -- Flags to indicate full/free of each pair at every stage.
  TYPE buffer_flag_pair_t IS ARRAY (0 TO 1) OF STD_LOGIC; -- 0 = free, 1 = full.
  TYPE buffer_flag_pipeline_t IS ARRAY (0 TO NUM_PASSES - 1) OF buffer_flag_pair_t; -- keeps all flags along the pipeline.

  
  -- Every "stage" / pass is 1 decoder instance. Each of these instances need some specific signals.
  -- but because the amount of passes is variable, and because it is ugly,
  -- we create type of size NUM_PASSES that will contain 1 of each relevant signal for every stage.
  -- Each index is therefore NOT a clock value, but stage numbers.
  TYPE code_array_t IS ARRAY (0 TO NUM_PASSES - 1) OF bch_code_t; -- type for the codeword array. Each index is the codeword that 1 stage is handling (input/output)
  TYPE valid_array_t IS ARRAY (0 TO NUM_PASSES - 1) OF STD_LOGIC; -- 1-bit flags for every stage.
  -- This one is a bit different.
  -- Because the component decoder has an OUT PORT for "errors_found", we must handle it
  -- but it is not used in the logic for the product decoder.
  TYPE errors_array_t IS ARRAY (0 TO NUM_PASSES - 1) OF STD_LOGIC_VECTOR(1 DOWNTO 0);
  TYPE count_array_t IS ARRAY (0 TO NUM_PASSES - 1) OF INTEGER RANGE 0 TO BCH_CODE_BITS; -- counters for each stage
  TYPE slot_array_t IS ARRAY (0 TO NUM_PASSES - 1) OF INTEGER RANGE 0 TO 1; -- which of 2 slots in 1 pair is used for read/write for each stage.

  
  ---------------------------------------------
					-- Signals
  ---------------------------------------------
  
  -- Actual buffers. 1 particular bit is accessed like this:
  -- matrix_buffers_s(stage)(slot)(row)(bit)
  SIGNAL matrix_buffers_s : matrix_pipeline_t := (OTHERS => (OTHERS => (OTHERS => (OTHERS => '0'))));
  -- Signifies if one of the matrix slots is full
  -- buffer_full_s(stage)(slot) = 1 when full and 0 when free.
  SIGNAL buffer_full_s    : buffer_flag_pipeline_t := (OTHERS => (OTHERS => '0'));

  -- Input signals for the decoder instances.
  SIGNAL decoder_data_in_s    : code_array_t := (OTHERS => (OTHERS => '0'));
  SIGNAL decoder_data_valid_s : valid_array_t := (OTHERS => '0');
  
  -- Output signals for the decoder instances.
  SIGNAL decoder_code_out_s   : code_array_t := (OTHERS => (OTHERS => '0'));
  SIGNAL decoder_code_valid_s : valid_array_t := (OTHERS => '0');
  SIGNAL decoder_errors_s     : errors_array_t := (OTHERS => (OTHERS => '0'));

  -- Stage control signals --
  SIGNAL stage_busy_s       : valid_array_t := (OTHERS => '0'); -- High when a stage is processing one block
  
  -- Counters for feeding decoder input and collectin decoder output for each stage.
  SIGNAL feed_count_s       : count_array_t := (OTHERS => 0);
  SIGNAL collect_count_s    : count_array_t := (OTHERS => 0);
  
  -- Slot tracking.
  SIGNAL stage_read_slot_s  : slot_array_t := (OTHERS => 0); -- Stores which full input slot a stage is reading from. For i>0 this is a slot from stage i-1
  SIGNAL stage_write_slot_s : slot_array_t := (OTHERS => 0); -- Stores which free output matrix slot a stage is writing its decoded rows/columns into. For stage i this is a slot in the i'th pair.

  -- Output control signals --
  SIGNAL output_busy_s : STD_LOGIC := '0'; -- is high when 1 block is being streamed out.
  SIGNAL output_slot_s : INTEGER RANGE 0 TO 1 := 0; -- Which slot is the output logic reading from.
  SIGNAL output_count_s : INTEGER RANGE 0 TO BCH_CODE_BITS := 0; -- Counter for output codewords.

  -- stage 0 is unique, because the initial stage cannot check if stage i-1 has a ready matrix to read from
  -- instead we use some helping signals. 
  SIGNAL stage0_has_free_s : STD_LOGIC := '0'; -- is high when one of stage0's matrix-pair is free.
  SIGNAL column_ready_s    : STD_LOGIC := '0'; -- Internal version of column_ready port, used for both internal logic and later mapped directly to the OUT port.

  
  ---------------------------------------------
					-- Helping functions
  ---------------------------------------------
  
  -- First 2 functions just check if any slot is free/full for a given stage
  FUNCTION has_free_slot(flags : buffer_flag_pair_t) RETURN BOOLEAN IS
  BEGIN
    RETURN flags(0) = '0' OR flags(1) = '0'; -- Returns TRUE if any of them are free.
  END FUNCTION;

  FUNCTION has_full_slot(flags : buffer_flag_pair_t) RETURN BOOLEAN IS
  BEGIN
    RETURN flags(0) = '1' OR flags(1) = '1'; -- Returns TRUE if any of them are full.
  END FUNCTION;

  -- This function returns which slot is actually free.
  -- it assumes that one of the slots is indeed free (it is nested after the function above).
  FUNCTION choose_free_slot(flags : buffer_flag_pair_t) RETURN INTEGER IS
  BEGIN
    IF flags(0) = '0' THEN
      RETURN 0;
    ELSE
      RETURN 1;
    END IF;
  END FUNCTION;

  -- Same logic here. Now we just assume that one of the slots is full.
  FUNCTION choose_full_slot(flags : buffer_flag_pair_t) RETURN INTEGER IS
  BEGIN
    IF flags(0) = '1' THEN
      RETURN 0;
    ELSE
      RETURN 1;
    END IF;
  END FUNCTION;

  
  -- Even though we feed columns, the matrix is stored as:
  -- 	matrix(row)(bit)
  -- Meaning that we still must extract 1 bit from each row to create a column vector.
  -- It works in the same way as the one in the product encoder.
  -- It is only used for even stage numbers for stage>0 (column passes) and at the final stage.
  FUNCTION get_column(
    mat           : product_matrix_t;
    column_number : INTEGER
  ) RETURN bch_code_t IS
    VARIABLE column_v     : bch_code_t := (OTHERS => '0');
    VARIABLE col_index_v  : INTEGER;
    VARIABLE bit_index_v  : INTEGER;
  BEGIN
    col_index_v := BCH_CODE_BITS - 1 - column_number;

    FOR r IN 0 TO BCH_CODE_BITS - 1 LOOP
      bit_index_v := BCH_CODE_BITS - 1 - r;
      column_v(bit_index_v) := mat(r)(col_index_v);
    END LOOP;

    RETURN column_v;
  END FUNCTION;

BEGIN

  -- Secutiy check.
  ASSERT ITERATIONS > 0
    REPORT "ITERATIONS must be larger than 0"
    SEVERITY FAILURE;

  -- Initial check if stage 0 has a free slot to write incoming data to.
  stage0_has_free_s <= '1' WHEN buffer_full_s(0)(0) = '0' OR buffer_full_s(0)(1) = '0' ELSE '0';

  -- Upstream "ready" logic.
  -- We are ready to accept new codewords in 2 cases:
  column_ready_s <= '1' WHEN (
    (stage_busy_s(0) = '1' AND feed_count_s(0) < BCH_CODE_BITS) -- We are already feeding columns but the matrix is not full yet
	 OR
    (stage_busy_s(0) = '0' AND stage0_has_free_s = '1') -- Stage0 is not feeding, and we have a free matrix.
  ) 
  ELSE '0';

  column_ready <= column_ready_s; -- Map the internal signal to the OUT port.

  -- Decode instance generation.
  -- Every pass/stage gets 1 instance.
  decoder_gen : FOR i IN 0 TO NUM_PASSES - 1 GENERATE
    decoder_inst : ENTITY work.decoder
      GENERIC MAP (
        M => M,
        T => T
      )
		-- Because we've created the signal arrays earlier, the i'th stage will get the i'th signal-to-port map.
      PORT MAP (
        clk          => clk,
        rst          => reset,
        data_in      => decoder_data_in_s(i),
        data_valid   => decoder_data_valid_s(i),
        code_out     => decoder_code_out_s(i),
        code_valid   => decoder_code_valid_s(i),
        errors_found => decoder_errors_s(i) -- This is not used, but the PORT is there, so we must map to it.
      );
  END GENERATE;

  PROCESS (clk)
  -- We use variables because they are immediately updated
  -- meaning that we can change them and use the updated value on the SAME clock cycle.
    VARIABLE read_slot_v     : INTEGER RANGE 0 TO 1; -- which FULL matrix should a stage read from
    VARIABLE write_slot_v    : INTEGER RANGE 0 TO 1; -- which FREE matrix should a stage write to.
	 
    -- When we are on a column pass, the output from the component decoder should be interpreted as such.
	 -- Therefore we must manually loop through all the bits and place them in the correct row
	 -- since the row is what is accessible directly through slicing, we don't have to do this in the row passes.
	 VARIABLE col_index_v     : INTEGER RANGE 0 TO BCH_CODE_BITS - 1; -- what column in the matrix are we writing to (static for entire column)
    VARIABLE bit_index_v     : INTEGER RANGE 0 TO BCH_CODE_BITS - 1; -- what bit from the decoder output are we choosing to write. (changes for each row in 1 column).

  BEGIN
    IF rising_edge(clk) THEN

      IF reset = '1' THEN

        matrix_buffers_s <= (OTHERS => (OTHERS => (OTHERS => (OTHERS => '0'))));
        buffer_full_s <= (OTHERS => (OTHERS => '0'));

        decoder_data_in_s <= (OTHERS => (OTHERS => '0'));
        decoder_data_valid_s <= (OTHERS => '0');

        stage_busy_s <= (OTHERS => '0');
        feed_count_s <= (OTHERS => 0);
        collect_count_s <= (OTHERS => 0);
        stage_read_slot_s <= (OTHERS => 0);
        stage_write_slot_s <= (OTHERS => 0);

        output_busy_s <= '0';
        output_slot_s <= 0;
        output_count_s <= 0;

        codeword_valid <= '0';
        codeword_out <= (OTHERS => '0');


        block_done <= '0';

      ELSE

		-- Default 1-clock signals on every block
        decoder_data_valid_s <= (OTHERS => '0');
        decoder_data_in_s <= (OTHERS => (OTHERS => '0'));

        codeword_valid <= '0';
        codeword_out <= (OTHERS => '0');


        block_done <= '0';

		----------------------------------
						-- Stage 0
		----------------------------------
		
		-- This stage is handled differently than all other stages, because here we receive data directly from the IN port.
		-- All other stages read from stage i-1, but for stage 0, this doesn't exist.
		
		-- Stage 0: Accept input columns.
        IF column_valid = '1' AND column_ready_s = '1' THEN -- Handhskae logic.

		  -- If stage 0 is not busy, then this is a new incoming 256x256 block.
          IF stage_busy_s(0) = '0' THEN
            write_slot_v := choose_free_slot(buffer_full_s(0)); -- Pick the free matrix to write to.
            stage_write_slot_s(0) <= write_slot_v; -- Update the slot
            stage_busy_s(0) <= '1';
            feed_count_s(0) <= 1; -- first column added to counter
            collect_count_s(0) <= 0;
          ELSE -- If the initial statement isn't true, then we must already be feeding a matrix.
            IF feed_count_s(0) = BCH_CODE_BITS - 1 THEN -- We're done feeding a block
              feed_count_s(0) <= BCH_CODE_BITS; -- stop value
            ELSE
              feed_count_s(0) <= feed_count_s(0) + 1; -- increment counter if we're not done.
            END IF;
          END IF;
			 -- Push data to the decoder.
          decoder_data_valid_s(0) <= '1';
          decoder_data_in_s(0) <= column_in;

        END IF;

		-- Stage 0: Collect decoded columns.
        IF decoder_code_valid_s(0) = '1' AND stage_busy_s(0) = '1' THEN -- Stage_busy_s is security check to make sure stage 0 is still active.

		  -- because the data in the matrix is written as rows, we must manually place 1 bit in each row of 1 column.
          col_index_v := BCH_CODE_BITS - 1 - collect_count_s(0);
          FOR r IN 0 TO BCH_CODE_BITS - 1 LOOP
            bit_index_v := BCH_CODE_BITS - 1 - r;
            matrix_buffers_s(0)(stage_write_slot_s(0))(r)(col_index_v) <= decoder_code_out_s(0)(bit_index_v);
          END LOOP;

		  -- Counter logic for collected, decoded columns.
          IF collect_count_s(0) = BCH_CODE_BITS - 1 THEN -- we're done:
			 
            buffer_full_s(0)(stage_write_slot_s(0)) <= '1'; -- mark the write slot as full, so stage 1 can read from it.
            stage_busy_s(0) <= '0'; -- free-up decoder
            feed_count_s(0) <= 0;
            collect_count_s(0) <= 0;
          ELSE
            collect_count_s(0) <= collect_count_s(0) + 1; -- otherwise we keep going.
          END IF;

        END IF;
		  
		----------------------------------
					-- Stage i for i>0
		----------------------------------
		
        FOR stage_index IN 1 TO NUM_PASSES - 1 LOOP

          IF stage_busy_s(stage_index) = '0' THEN -- initial check to see, if the stage is not busy on something.

			 -- But the initial check is not enough. For a stage to start on a new matrix, 2 more things have to be true:
			 -- 	1: stage i-1 has a ready matrix that stage i can read from and give to its decoder
			 -- 	2: this stage has a free matrix slot it can write to.
            IF has_full_slot(buffer_full_s(stage_index - 1)) AND has_free_slot(buffer_full_s(stage_index)) THEN

              read_slot_v := choose_full_slot(buffer_full_s(stage_index - 1)); -- Which matrix from stage i-1 is stage i reading from
              write_slot_v := choose_free_slot(buffer_full_s(stage_index)); -- which of its own slots is stage i writing to.

				  -- Update state signals with the variables gotten above (remember variables update immediately).
              stage_read_slot_s(stage_index) <= read_slot_v; 
              stage_write_slot_s(stage_index) <= write_slot_v;
				  
				  -- Set flags and counters. Now stage i is working.
              stage_busy_s(stage_index) <= '1';
              feed_count_s(stage_index) <= 1;
              collect_count_s(stage_index) <= 0;

				  -- Feed column/row to the decoder
              decoder_data_valid_s(stage_index) <= '1'; -- valid in both cases
				  -- The pass we're doing on each iteration changes:
				  -- 		Even numbered passes: Column pass
				  --  	Uneven numbered passes: Row pass
              IF (stage_index MOD 2) = 0 THEN  -- For the column passes, the input to the decoder is a column, so we must construct it from 1 bit from each row
                decoder_data_in_s(stage_index) <= get_column(matrix_buffers_s(stage_index - 1)(read_slot_v), 0);
              ELSE -- For the row passes, we can directly access a row from slicing.
                decoder_data_in_s(stage_index) <= matrix_buffers_s(stage_index - 1)(read_slot_v)(0);
              END IF;

            END IF;

          ELSE -- This means we're already busy and should either keep going or stop feeding.

            IF feed_count_s(stage_index) < BCH_CODE_BITS THEN -- Keep going

              decoder_data_valid_s(stage_index) <= '1';

              IF (stage_index MOD 2) = 0 THEN -- Same logic as earlier with column/row passes.
				  -- This line above is very long, so the indices will be explained a bit:
				  --  matrix_buffers_s(stage_index-1) is the pair from stage i-1
				  --  stage_read_slot_s(stage_index) is chosen initially using the variables, and is the slot this stage is reading from.
				  --  feed_count_s(stage_index) is the column we've reached and are feeding.
                decoder_data_in_s(stage_index) <= get_column(matrix_buffers_s(stage_index - 1)(stage_read_slot_s(stage_index)),feed_count_s(stage_index)
                );
              ELSE -- Otherwise it is a row pass, and we can directly access the rows and feed them to the decoder.
                decoder_data_in_s(stage_index) <= matrix_buffers_s(stage_index - 1)(stage_read_slot_s(stage_index))(feed_count_s(stage_index));
              END IF;

				  -- Done logic
              IF feed_count_s(stage_index) = BCH_CODE_BITS - 1 THEN
                buffer_full_s(stage_index - 1)(stage_read_slot_s(stage_index)) <= '0'; -- We've read the matrix from stage i-1, and can mark it as FREE.
                feed_count_s(stage_index) <= BCH_CODE_BITS; -- done feeding value.
              ELSE
                feed_count_s(stage_index) <= feed_count_s(stage_index) + 1; -- otherwise keep going.
              END IF;

            END IF;

          END IF;

			 
			 
			 -- Collect outputs from the decoder
			 
			 -- Same logic as for stage 0 initially with safety check
          IF decoder_code_valid_s(stage_index) = '1' AND stage_busy_s(stage_index) = '1' THEN

            IF (stage_index MOD 2) = 0 THEN
				-- on column passes, we use the same logic as for stage 0.
				-- Here we again use the slots assigned initially with the variable logic.
				
              col_index_v := BCH_CODE_BITS - 1 - collect_count_s(stage_index);
			
              FOR r IN 0 TO BCH_CODE_BITS - 1 LOOP -- for column passes, we must go bit-for-bit from each row of the corresponding column.
                bit_index_v := BCH_CODE_BITS - 1 - r;
                matrix_buffers_s(stage_index)(stage_write_slot_s(stage_index))(r)(col_index_v) <= decoder_code_out_s(stage_index)(bit_index_v);
              END LOOP;

            ELSE -- Row passes are much easier, as mentioned earlier.
              matrix_buffers_s(stage_index)(stage_write_slot_s(stage_index))(collect_count_s(stage_index)) <= decoder_code_out_s(stage_index);

            END IF;

				-- Done logic.
            IF collect_count_s(stage_index) = BCH_CODE_BITS - 1 THEN
              buffer_full_s(stage_index)(stage_write_slot_s(stage_index)) <= '1'; -- Mark the buffer as full, so stage i+1 can read it
              -- Reset counters and "free up" this stages decoder.
				  stage_busy_s(stage_index) <= '0';
              feed_count_s(stage_index) <= 0;
              collect_count_s(stage_index) <= 0;
            ELSE
              collect_count_s(stage_index) <= collect_count_s(stage_index) + 1;
            END IF;

          END IF;

        END LOOP;

		  
		-- Final output after one block has passed through all stages.
        IF output_busy_s = '0' THEN -- We are not currently outputting anything

          IF has_full_slot(buffer_full_s(NUM_PASSES - 1)) THEN -- Final stage has a full/ready matrix slot

            read_slot_v := choose_full_slot(buffer_full_s(NUM_PASSES - 1)); -- output stage should then read from this slot
            

				-- Start outputting (mark busy, and assign output_slot_s signal to the variable gotten from the logic above).
            output_busy_s <= '1';
            output_slot_s <= read_slot_v;
            output_count_s <= 1; -- start counter

				-- Actual outputting.
            codeword_valid <= '1';
            codeword_out <= get_column(matrix_buffers_s(NUM_PASSES - 1)(read_slot_v), 0); -- We output column-by-column (convention).


          END IF;

        ELSE

          IF output_count_s < BCH_CODE_BITS THEN -- Keep outputting.


            codeword_valid <= '1';
            codeword_out <= get_column(matrix_buffers_s(NUM_PASSES - 1)(output_slot_s), output_count_s);


				-- Done with a block logic.
            IF output_count_s = BCH_CODE_BITS - 1 THEN
              buffer_full_s(NUM_PASSES - 1)(output_slot_s) <= '0'; -- Free up final matrix slot we've just finished outputting.
              output_busy_s <= '0'; -- output logic is freed up
              output_count_s <= 0; -- output stage's counter is reset.
              block_done <= '1'; -- Pulses high for 1 clock.
            ELSE
              output_count_s <= output_count_s + 1;
            END IF;

          END IF;

        END IF;

      END IF;

    END IF;
  END PROCESS;

END ARCHITECTURE rtl;