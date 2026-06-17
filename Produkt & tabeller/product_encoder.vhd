LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY product_encoder IS
  GENERIC (
    M : INTEGER := 8;
    T : INTEGER := 2
  );
  PORT (
    clk           : IN  STD_LOGIC;
    reset         : IN  STD_LOGIC;

    data_valid    : IN  STD_LOGIC; -- Is 1 when input data is valid.
    data_in       : IN  STD_LOGIC_VECTOR((2 ** M - M * T - 1) * (2 ** M - M * T - 1) - 1 DOWNTO 0);

    product_valid : OUT STD_LOGIC; -- Is 1 when output codeword is valid.
    product_out   : OUT STD_LOGIC_VECTOR((2 ** M) * (2 ** M) - 1 DOWNTO 0)
  );
END ENTITY product_encoder;

ARCHITECTURE rtl OF product_encoder IS

  CONSTANT BCH_DATA_BITS    : INTEGER := 2 ** M - M * T - 1; -- 239 data bits as input per row/col
  CONSTANT BCH_CODE_BITS    : INTEGER := 2 ** M;             -- 256 resulting bits pr. codeword in row/col

  CONSTANT PRODUCT_IN_BITS  : INTEGER := BCH_DATA_BITS * BCH_DATA_BITS; -- 57121 input bits (239*239) total
  CONSTANT PRODUCT_OUT_BITS : INTEGER := BCH_CODE_BITS * BCH_CODE_BITS; -- 65536 output bits (256*256) total

  -- The input port is a "flat" vector of length 57121.
  -- To actually use the "product code" structure, the codes uses matrices internally
  -- Therefore, 3 types of matrices are created:
  TYPE input_matrix_t IS ARRAY (0 TO BCH_DATA_BITS - 1) -- main input matrix. This is 239x239
    OF STD_LOGIC_VECTOR(BCH_DATA_BITS - 1 DOWNTO 0);

  TYPE row_encoded_matrix_t IS ARRAY (0 TO BCH_DATA_BITS - 1) -- matrix when the rows are encoded. This is 239x256
    OF STD_LOGIC_VECTOR(BCH_CODE_BITS - 1 DOWNTO 0);

  TYPE output_matrix_t IS ARRAY (0 TO BCH_CODE_BITS - 1) -- finally when both rows and columns are encoded, we arrive at a 256x256 matrix
    OF STD_LOGIC_VECTOR(BCH_CODE_BITS - 1 DOWNTO 0);

  -- State-machine for the encoding. Will be commented further later
  TYPE state_t IS (
    LOAD_INPUT,
    FEED_ROWS,
    WAIT_ROWS,
    FEED_COLS,
    WAIT_COLS,
    DONE
  );

  SIGNAL state_s : state_t := LOAD_INPUT;

  -- Matrix signals that will keep all the bits in the different stages
  SIGNAL input_matrix_s       : input_matrix_t;
  SIGNAL row_encoded_matrix_s : row_encoded_matrix_t;
  SIGNAL output_matrix_s      : output_matrix_t;

  -- data/valid signals. These will be connected to the bch_encoder_256 block later
  SIGNAL encoder_data_valid_s : STD_LOGIC := '0';
  SIGNAL encoder_data_in_s    : STD_LOGIC_VECTOR(BCH_DATA_BITS - 1 DOWNTO 0) := (OTHERS => '0');
  SIGNAL encoder_code_valid_s : STD_LOGIC;
  SIGNAL encoder_code_out_s   : STD_LOGIC_VECTOR(BCH_CODE_BITS - 1 DOWNTO 0);

  -- Indexes. We include 256 as a final possible value. Later we can use this as a "done" index value.
  -- We need both indexes, because the encoder is pipelined, so the input is first done after many clock cycles.
  SIGNAL feed_index_s   : INTEGER RANGE 0 TO BCH_CODE_BITS := 0; -- which row/col are we sending to the encoder
  SIGNAL output_index_s : INTEGER RANGE 0 TO BCH_CODE_BITS := 0; -- which encoded row/col are we receiving from the encoder

BEGIN

  -- For this version, where we first encode all rows and then all columns, we only need 1 instance of the bch_encoder_256 block.
  bch_encoder_inst : ENTITY work.bch_encoder_256
    GENERIC MAP (
      M => M,
      T => T
    )
    PORT MAP (
      clk        => clk,
      reset      => reset,
      data_valid => encoder_data_valid_s,
      data_in    => encoder_data_in_s,
      code_valid => encoder_code_valid_s,
      code_out   => encoder_code_out_s
    );
PROCESS(clk)
    -- The first version of the code had some pretty "ugly" slicing
	 -- So i made some variables that make the code more readable.
    VARIABLE column_input_v : STD_LOGIC_VECTOR(BCH_DATA_BITS - 1 DOWNTO 0);
    VARIABLE row_high_v : INTEGER;
    VARIABLE row_low_v  : INTEGER;
    VARIABLE col_v      : INTEGER;
    VARIABLE in_bit_v   : INTEGER;
    VARIABLE out_bit_v  : INTEGER;
  BEGIN
    IF rising_edge(clk) THEN

      IF reset = '1' THEN

        state_s              <= LOAD_INPUT;
        product_valid        <= '0';
        product_out          <= (OTHERS => '0');

        encoder_data_valid_s <= '0';
        encoder_data_in_s    <= (OTHERS => '0');

        feed_index_s         <= 0;
        output_index_s       <= 0;

      ELSE

        -- We return to default on every clock
		  -- This is needed because we must reset the valid flag when we are in the waiting states
		  -- since we do not send more data until the particular "level" is complete.
        product_valid        <= '0';
        encoder_data_valid_s <= '0';
        encoder_data_in_s    <= (OTHERS => '0');

        CASE state_s IS

          WHEN LOAD_INPUT =>
				-- We reset all indexes at the start, since we feed the first row and we expect the first output to be the first row.
            feed_index_s   <= 0;
            output_index_s <= 0;

            IF data_valid = '1' THEN

              -- Convert flat input vector into 239 rows of 239 bits (create the matrix structure)
              -- Row 0 gets the top 239 bits, row 238 gets the bottom 239 bits and so on.
              FOR r IN 0 TO BCH_DATA_BITS - 1 LOOP
                row_high_v := PRODUCT_IN_BITS - 1 - r * BCH_DATA_BITS;
                row_low_v  := row_high_v - BCH_DATA_BITS + 1; -- +1 is needed because both ends of a DOWNTO slice are included.
                input_matrix_s(r) <= data_in(row_high_v DOWNTO row_low_v);
              END LOOP;
              state_s <= FEED_ROWS; -- After the initial matrix structure is created, we start giving the bits to the encoder

            END IF;


			 -- After the matrix is created, we start feeding 1 row pr. clock to the encoder.
          WHEN FEED_ROWS =>

            encoder_data_valid_s <= '1'; -- We have a valid row 
            encoder_data_in_s    <= input_matrix_s(feed_index_s); -- Send that row to the bch-encoder

            IF feed_index_s = BCH_DATA_BITS - 1 THEN 
              feed_index_s <= 0; -- We're done
              state_s      <= WAIT_ROWS;
            ELSE
              feed_index_s <= feed_index_s + 1; -- Loop
            END IF;

            -- Collect row outputs while we're still sending more data to the encoder
				-- Because the encoder is pipelined, this is possible and needed.
            IF encoder_code_valid_s = '1' THEN -- The encoder sets this flag
              row_encoded_matrix_s(output_index_s) <= encoder_code_out_s; -- We start filling the matrix
              output_index_s <= output_index_s + 1;
            END IF;


			 -- We must wait until the entire "first" matrix is complete, before we start filling in the columns.
          WHEN WAIT_ROWS =>

            IF encoder_code_valid_s = '1' THEN
              row_encoded_matrix_s(output_index_s) <= encoder_code_out_s; -- Keep filling the matrix

              IF output_index_s = BCH_DATA_BITS - 1 THEN -- We're done
                output_index_s <= 0;
                feed_index_s   <= 0;
                state_s        <= FEED_COLS;
              ELSE
                output_index_s <= output_index_s + 1;
              END IF;
            END IF;



			 -- Now we make the final matrix. We have a 239x256 row-encoded matrix at this point.
          WHEN FEED_COLS =>
				-- Since the bch encoder takes 239 bits as input, we must create column "vectors" by selecting 1 bit from every row
				-- Because the VHDL vector convention is indexed from "left to right", so the highest index is the first bit in the vector
				-- we let the first column get the "last" bit in index value. It is still the first bit.
				-- That explains why we use BCH_CODE_BITS-1-feed_index_s.

            col_v := BCH_CODE_BITS - 1 - feed_index_s; -- Which column are we creating
            FOR r IN 0 TO BCH_DATA_BITS - 1 LOOP -- r is the row number.
              in_bit_v := BCH_DATA_BITS - 1 - r; -- bit index
              column_input_v(in_bit_v) := row_encoded_matrix_s(r)(col_v);
            END LOOP;

				-- Now the vector is created in the format the bch_encoder is expecting, so we can feed it the same way we do with the rows.
            encoder_data_valid_s <= '1';
            encoder_data_in_s    <= column_input_v;

            IF feed_index_s = BCH_CODE_BITS - 1 THEN
              feed_index_s <= 0;
              state_s      <= WAIT_COLS;
            ELSE
              feed_index_s <= feed_index_s + 1;
            END IF;

            -- Again we collect the outputs while feeding
            IF encoder_code_valid_s = '1' THEN
              col_v := BCH_CODE_BITS - 1 - output_index_s;
              FOR r IN 0 TO BCH_CODE_BITS - 1 LOOP
                out_bit_v := BCH_CODE_BITS - 1 - r;
                output_matrix_s(r)(col_v) <= encoder_code_out_s(out_bit_v);
              END LOOP;
              output_index_s <= output_index_s + 1;
            END IF;


			 -- Now we fill out the remainder of the final matrix, since we're out of input bits and are just waiting for the encoding pipeline to finish.
          WHEN WAIT_COLS =>

            IF encoder_code_valid_s = '1' THEN
              col_v := BCH_CODE_BITS - 1 - output_index_s;
              FOR r IN 0 TO BCH_CODE_BITS - 1 LOOP
                out_bit_v := BCH_CODE_BITS - 1 - r;
                output_matrix_s(r)(col_v) <= encoder_code_out_s(out_bit_v);
              END LOOP;

              IF output_index_s = BCH_CODE_BITS - 1 THEN
                output_index_s <= 0;
                feed_index_s   <= 0;
                state_s        <= DONE;
              ELSE
                output_index_s <= output_index_s + 1;
              END IF;

            END IF;



			 -- When the 256x256 matrix is done, we reflatten it to contain a "flat" output vector of length 256*256.
			 -- THe format will then be that the first row of the matrix is the first 256 bits of the final vector
			 -- The second row is the next 256 bits and so on.
          WHEN DONE =>

            FOR r IN 0 TO BCH_CODE_BITS - 1 LOOP
              row_high_v := PRODUCT_OUT_BITS - 1 - r * BCH_CODE_BITS;
              row_low_v  := row_high_v - BCH_CODE_BITS + 1;
              product_out(row_high_v DOWNTO row_low_v) <= output_matrix_s(r);
            END LOOP;
            product_valid <= '1';
            state_s       <= LOAD_INPUT;


          WHEN OTHERS =>

            state_s <= LOAD_INPUT;

        END CASE;

      END IF;
    END IF;
  END PROCESS;



END ARCHITECTURE rtl;
