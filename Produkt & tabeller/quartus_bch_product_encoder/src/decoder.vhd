--- bch_decoder

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY decoder IS
  GENERIC (
    M : INTEGER := 8; -- 2**m = codeword length
    T : INTEGER := 2  -- error correction cap.
  );
  PORT (
    clk, rst : IN STD_LOGIC;

    data_in    : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- received codeword
    data_valid : IN STD_LOGIC; -- is 1 when data_in contains a new codeword to be handled. This is set by other modules

    code_out   : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- corrected codeword
    code_valid : OUT STD_LOGIC; -- is set to 1 by this module when the corrected codeword is ready.

    errors_found : OUT STD_LOGIC_VECTOR(1 DOWNTO 0) -- amount of errors we think the rec codeword contains.
  );
END ENTITY;

ARCHITECTURE RTL OF decoder IS

 ----------------------------------------------------
				-- Components
 ----------------------------------------------------

  -- Alpha^i => i table
  COMPONENT a_to_log_a_tabel IS
    PORT (
      address  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      contents : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      clk, rst : IN  STD_LOGIC
    );
  END COMPONENT a_to_log_a_tabel;

  -- a => a^3 table
  COMPONENT a_to_a_pow3_tabel IS
    PORT (
      address  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      contents : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      clk, rst : IN  STD_LOGIC
    );
  END COMPONENT a_to_a_pow3_tabel;

  -- log(A) => [log(z1),log(z2)] (8 bit each).
  COMPONENT log_A_to_log_rootsOfA_tabel IS
    PORT (
      address  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
      contents : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
      clk, rst : IN  STD_LOGIC
    );
  END COMPONENT log_A_to_log_rootsOfA_tabel;

  -- Creates the bit-mask used to flip the erroroneous bits at the end.
  COMPONENT one_hot_encoder IS
    PORT (
      clk : IN STD_LOGIC;
      rst : IN STD_LOGIC;

      binary_in   : IN  STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
      one_hot_out : OUT STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0')
    );
  END COMPONENT one_hot_encoder;

  -- The syndrome calculator calculates
  -- 		S1 = r(alpha)
  -- 		S3 = r(alpha^3)
  --  	Overall parity (XOR of all bits).
  COMPONENT syndrome_calculator IS
    PORT (
      clk : IN STD_LOGIC;
      rst : IN STD_LOGIC;

      data_in    : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
      data_valid : IN STD_LOGIC;

      data_out       : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
      data_out_valid : OUT STD_LOGIC;

      data_parity : OUT STD_LOGIC;

      S1, S3 : OUT STD_LOGIC_VECTOR(M - 1 DOWNTO 0)
    );
  END COMPONENT syndrome_calculator;


 ----------------------------------------------------
					-- Signals
 ----------------------------------------------------  

 -- Because the entire decoder is designed to be pipelined, all data is kept in arrays.
 -- That way, the syndromes, parity, codeword, log-values, ... are all aligned through the entire decoding process
 -- The result is, in the same way as the encoder, that we have a warmup period and then we are capable of outputting 1 fixed codeword pr. clock.
 
 -- Outputs from the syndrome_calculator module and their "delay" arrays.
  TYPE S1_array_t IS ARRAY (1 TO 2) OF STD_LOGIC_VECTOR(M - 1 DOWNTO 0); -- Delay array
  TYPE S3_array_t IS ARRAY (1 TO 2) OF STD_LOGIC_VECTOR(M - 1 DOWNTO 0); -- Delay array (could've just used 1 type)

  -- Because we need the initial syndromes for other calculations, and the decoder is pipelined, we have to "keep" them
  -- For example S1 is used to calculate S1^3, and this operation is clocked.
  -- Furthermore, we need the same syndromes 1 clock later again, so that we can classify how many errors happened.
  -- Since we are streaming 1 codeword pr. clock, we have to keep the syndromes from earlier clocks, until we have done the LUT lookups.
  -- Since we need the same syndrome for 2 more clocks, that is the reasoning behind the size of S1/3_array_t
  SIGNAL S1_array : S1_array_t := (OTHERS => (OTHERS => '0'));
  SIGNAL S3_array : S3_array_t := (OTHERS => (OTHERS => '0'));

  SIGNAL S1_array0, S3_array0 : STD_LOGIC_VECTOR(M - 1 DOWNTO 0); -- These are the signals that get the direct, initial output from the syndrome module.

  -- The same logic applies for the log value.
  -- Here we calculate log(S1).
  -- Log_S1_array2 is the direct "link" between the module a_to_log_a_tabel and this decoder module.
  -- After this value is fed initially, we push it forward in the pipeline, which is what the main array is for.
  -- Notice that the index values are pipeline step numbers, and NOT mathematical indices that should be interpreted in any other way than 0 to 8 or whatever the indexes might be if shifted to start from 0.
  TYPE log_S1_array_t IS ARRAY (3 TO 11) OF STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
  SIGNAL log_S1_array : log_S1_array_t := (OTHERS => (OTHERS => '0'));
  SIGNAL log_S1_array2 : STD_LOGIC_VECTOR(M - 1 DOWNTO 0);

  -- Enumeration type for the "type" of error(s) the codeword contains.
  TYPE error_count_type IS (
    NO_ERRORS,
    ONE_ERROR,
    TWO_ERRORS,
    INVALID
  );
  -- Again we want to "pair" the error count to the codeword in through the entire pipeline.
  -- Again, 3 to 14 is only used as a naming convention (step 3 to output, which is step 15).
  TYPE error_count_array_t IS ARRAY (3 TO 14) OF error_count_type;
  SIGNAL error_count_array : error_count_array_t := (OTHERS => INVALID);

  -- Same logic as for the syndromes. This is the codeword we've received from the syndrome_calculator module.
  -- messages0 is the direct link and the array is the pipeline.
  TYPE messages_t IS ARRAY (1 TO 14) OF STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
  SIGNAL messages : messages_t := (OTHERS => (OTHERS => '0'));
  SIGNAL messages0 : STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);

  -- Same logic for the singular valid/parity bits from the syndrome calculator.
  SIGNAL data_out_valid : STD_LOGIC_VECTOR(1 TO 14) := (OTHERS => '0');
  SIGNAL message_parity : STD_LOGIC_VECTOR(1 TO 14) := (OTHERS => '0');
  SIGNAL data_out_valid0, message_parity0 : STD_LOGIC;

  -- This register is not a part of the pipeline like the others
  -- This one is used for 4 different mathematical procedures we're doing
  -- The intermediate values are kept in this array.
  TYPE step_array_t IS ARRAY (1 TO 4) OF STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
  SIGNAL step_array : step_array_t := (OTHERS => (OTHERS => '0'));

  -- will contain log(A) that we're using to solve the error locator polynomial
  SIGNAL log_A : STD_LOGIC_VECTOR(M - 1 DOWNTO 0) := (OTHERS => '0');
  -- Log(z1)log(z2) are kept in this (the roots to the error locator polynomial)
  SIGNAL log_roots : STD_LOGIC_VECTOR(M * T - 1 DOWNTO 0);
  -- log(S1^2). is used in the 2-error case since:
  -- 		log(S1^2)=2log(S1) mod 255.
  SIGNAL log_pow2_S1 : STD_LOGIC_VECTOR(M - 1 DOWNTO 0);

  -- more helper-signals for the log-domain arithmetic.
  -- They have length 9, because the result of some of the arithmetic can overflow/underflow
  -- minus_log_pow2_S1 = -log(S1^2), minus_log_S1 = -log(S1)
  -- step4 and step6 contain temp results the correction (mod 255).
  SIGNAL step4, step6, minus_log_pow2_S1, minus_log_S1 :
    STD_LOGIC_VECTOR(M DOWNTO 0) := (OTHERS => '0');

  -- candidate error positions BEFORE modulo reduction
  -- These are in the log domain still.
  -- Size 9 again because they can overflow
  SIGNAL error_l1, error_l2 :
    STD_LOGIC_VECTOR(M DOWNTO 0) := (OTHERS => '0');
  
  -- final error locations (now 8 bits each).
  -- this value is still technically a log value (log(alpha^i))
  -- but it is used as index-value in the codeword, since they are equal.
  -- We need 2 signals (could've been an array) for the second error, because the one-hot-encoder is clocked
  -- which means that the second error will have to wait an additional clock, before the one-hot-encoder is "ready" again.
  SIGNAL error_location1, error_location2_0, error_location2_1 :
    STD_LOGIC_VECTOR(M - 1 DOWNTO 0) := (OTHERS => '0');

  -- these will contain the one-hot masks used to correct.
  TYPE error_vectors_t IS ARRAY (0 TO 1) OF STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0);
  SIGNAL error_vectors : error_vectors_t;

  -- These are the inputs to the one-hot-encoder to create the bit mask.
  -- 2 possible positions, so 2 addresses are given to the module.
  TYPE find_error_vectors_of_this_t IS ARRAY (0 TO 1) OF STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
  SIGNAL find_error_vectors_of_this : find_error_vectors_of_this_t := (OTHERS => (OTHERS => '1'));


BEGIN

 ----------------------------------------------------
					-- Port maps.
 ---------------------------------------------------- 

 
  -- address (S1) is sent so we can retrieve S1^3.
  -- this is the "actual" step1, since the work is done by the LUT.
  pow3_tabel_for_step1 : ENTITY work.a_to_a_pow3_tabel
    PORT MAP (
      address  => S1_array0,
      contents => step_array(1), -- step_array(1) will then contain S1^3 1 clock later.
      clk      => clk,
      rst      => rst
    );

  -- In the pipeline flow, we're now 1 clock later
  -- that means that S1_array0 will have a new syndrome from another codeword
  -- so we must use the appropriate index-value in the pipeline so we get the same S1 from step1
  -- This gives us log(S1).
  log_tabel_for_step2 : ENTITY work.a_to_log_a_tabel
    PORT MAP (
      address  => S1_array(1), -- Same S1, but 1-clock later
      contents => log_S1_array2, -- log_S1_array2 (the relative 0 index) will then contain log(S1) 1 clock later.
      clk      => clk,
      rst      => rst
    );

  -- We need to use the same table again, but for something else.
  -- Now we want to get log(S1^3+S3) (introduced further down)
  log_tabel_for_step3 : ENTITY work.a_to_log_a_tabel
    PORT MAP (
      address  => step_array(2), -- this will contain S1^3+S3
      contents => step_array(3), -- next "part" of the intermediate array will be log(S1^3+S3) 1 clock later.
      clk      => clk,
      rst      => rst
    );

  -- This is the root table for the 2 normalized roots in the 2-error case.
  -- For a value log(A), we get [log(z1),log(z2)].
  log_A_tabel_for_step8 : ENTITY work.log_A_to_log_rootsOfA_tabel
    PORT MAP (
      address  => log_A,
      contents => log_roots, -- still 1 clock later this is updated.
      clk      => clk,
      rst      => rst
    );

  -- The syndrome_calculator is self-explanatory based on the signals
  syn_cal : ENTITY work.syndrome_calculator
    PORT MAP (
      clk            => clk,
      rst            => rst,
      data_in        => data_in,
      data_valid     => data_valid,
      S1             => S1_array0,
      S3             => S3_array0,
      data_out       => messages0,
      data_out_valid => data_out_valid0,
      data_parity    => message_parity0
    );

  -- we create 1 instance of the one_hot_encoder for each of the 2 possible error positions
  -- the port map is self-explanatory.
  one_hot_error_finders : FOR i IN 0 TO 1 GENERATE
    one_hot_error_finders : ENTITY work.one_hot_encoder
      PORT MAP (
        clk         => clk,
        rst         => rst,
        binary_in   => find_error_vectors_of_this(i),
        one_hot_out => error_vectors(i)
      );
  END GENERATE;


 ----------------------------------------------------
					-- Main process.
 ---------------------------------------------------- 

  PROCESS (clk, rst)
  BEGIN

    IF rst = '1' THEN

      code_out <= (OTHERS => '0');
      code_valid <= '0';

      message_parity <= (OTHERS => '0');
      data_out_valid <= (OTHERS => '0');

      log_A <= (OTHERS => '0');

      S1_array <= (OTHERS => (OTHERS => '0'));
      S3_array <= (OTHERS => (OTHERS => '0'));

      log_S1_array <= (OTHERS => (OTHERS => '0'));

      error_count_array <= (OTHERS => INVALID);

      messages <= (OTHERS => (OTHERS => '0'));

      errors_found <= "00";


		ELSIF rising_edge(clk) THEN
		-- Update all shift-registers on each clock.
		-- Remember that some parts of the registers are independent signals, which is why they're handled outside of the loops.
      FOR i IN 1 TO 1 LOOP
        S1_array(i + 1) <= S1_array(i);
      END LOOP;
      S1_array(1) <= S1_array0;

      FOR i IN 1 TO 1 LOOP
        S3_array(i + 1) <= S3_array(i);
      END LOOP;
      S3_array(1) <= S3_array0;

      FOR i IN 3 TO 10 LOOP
        log_S1_array(i + 1) <= log_S1_array(i);
      END LOOP;
      log_S1_array(3) <= log_S1_array2;

      FOR i IN 3 TO 13 LOOP
        error_count_array(i + 1) <= error_count_array(i);
      END LOOP;

      messages(1) <= messages0;

      FOR i IN 1 TO 10 LOOP
        messages(i + 1) <= messages(i);
      END LOOP;

		-- These values will never change, and are single-bit values.
		-- Therefore we can just use manual slice assignment.
      data_out_valid(1) <= data_out_valid0;
      message_parity(1) <= message_parity0;

      data_out_valid(2 TO 14) <= data_out_valid(1 TO 13);
      message_parity(2 TO 14) <= message_parity(1 TO 13);


	----------------------------------------------------
						-- Actual decoding.
	---------------------------------------------------- 

			-- Goal:
			-- Use the BCH syndromes S1 and S3 to classify the BCH error pattern and prepare the values needed to find the error location(s).
			--
			-- For one BCH error:
			--   S1 = alpha^i
			--   S3 = alpha^(3i)
			--   therefore S1^3 = S3, so S1^3 xor S3 = 0.
			--
			-- For two BCH errors:
			--   S1^3 xor S3 is non-zero and is used later to compute the normalized A value for the equation z^2 + z + A = 0.
			
			-- Since the decoder is pipelined, each step works on delayed values from the same received codeword.
			
			
		-- Step 1 (N)
		-- This is done in the port map (getting S1^3)
		-- But since the LUT is clocked, the result is first ready on the NEXT clock.
		-- So clock N with codeword A gives S1_array0 = S1_A as the input to the LUT
		-- Clock N+1 will then have step_array(1) = S1_A^3
		
		-- Step 2 (N+1)
		-- clock N+1 we compute S1_A^3 + S3_A
		-- the result is then ready on clock N+2.
      step_array(2) <= step_array(1) XOR S3_array(1);

		-- Step 3 (N+2)
		-- This step is twofold.
		-- We are at clock N+2, so we have:
		-- 	S1_array(2) = S1_A
		-- 	S3_array(2) = S3_A
		-- 	step_array(2) = (S1_A)^3 + S3_A
		-- So now we can classify the codeword to see how many errors the codeword contains.
		-- This is done using the following rule for ONE error:
		-- 	S1 = alpha^i
		-- 	S3 = alpha^(3i)
		-- with one error, this means:
		-- 	S3 = S1^3 => S3+S1^3=0.
		-- So for no errors, both syndromes are 0
		-- 1 error the above holds
		-- otherwise, we will initially treat the codeword to contain 2 errors.
      IF data_out_valid(2) = '0' THEN
        error_count_array(3) <= INVALID;

      ELSIF (S1_array(2) = x"00" AND S3_array(2) = x"00") THEN
        error_count_array(3) <= NO_ERRORS;

      ELSIF step_array(2) = x"00" THEN
        error_count_array(3) <= ONE_ERROR;

      ELSE
        error_count_array(3) <= TWO_ERRORS;
      END IF;
		
		-- Furthermore, clock N+2 will also use the a_to_log_a LUT with step_array(2) as input to obtain log((S1_A)^3+S3_A)
		-- Finally at clock N+2, we compute -log(S1_A) from log_S1_array2 so we can subtract it directly later in the normalized equation.
		-- To make it "negative", we use two's complement (invert all bits and add 1)
      minus_log_S1 <= STD_LOGIC_VECTOR(UNSIGNED(NOT ('0' & log_S1_array2)) + 1); -- remember that minus_log_S1 is 9 bits, so we append 1 zero.


      -- Step 4 (N+3)
      -- now we have:
		-- 	step_array(3) = log((S1_A)^3+S3_A)
		-- 	minus_log_S1 = -log(S1_A)
		-- in the 2-error case, we have the system:
		-- 	X = alpha^i
		-- 	Y = alpha^j
		-- 	S1 = X+Y
		-- 	S3 = X^3+Y^3 
		-- and we want to obtain the normalized equation:
		-- 	z^2+z+A=0
		-- 	A = (X*Y)/S1^2
		-- Where we can solve for the roots and get the error locations.
		-- We can isolate and achieve:
		-- 	XY = (S1^3+S3)/S1
		-- So we compute log(((S1_A)^3+S3)/S1) = log((S1_A)^3+S3)-log(S1), which is exactly log(XY) in the 9-bit version.
      step4 <= STD_LOGIC_VECTOR(UNSIGNED('0' & step_array(3)) + UNSIGNED(minus_log_S1));

		-- Now we just need S1^2. We can calculate this using the following identity:
		-- 	S1 = alpha^k
		-- 	S1^2 = alpha^2k
		-- 	log(S1^2) = 2k = 2 log(S1) mod 255.
		-- Since k is an 8-bit value, we can obtain this by doing a left-rotation:
		-- 	if k < 128, left shift gives us exactly 2k
		-- 	if k >=128, then a left shift will result in the MSB wrapping and adding 1, which gives 2k-255 (2k modulo 255)
      log_pow2_S1 <= log_S1_array(3)(M - 2 DOWNTO 0) & log_S1_array(3)(M - 1); -- The part after the & is the old MSB, appended as the new LSB (rotation).


      -- Step 5 (N+4)
      -- here we have:
		-- 	step4 = 9-bit rep of log(((S1_A)^3+S3_A) / S1_A) = log(XY)
		-- 	log_pow2_S1 = log((S1_A)^2)
		-- Because step4 is calculated from a value made with two's complement, we must check if the result was negative
		-- In two's complement, the vector is seen as negative, if the MSB is 1 (also known as the sign bit).
		-- If it is, we manually do "positive" modulo to bring back the value into the valid log range (0 to 254)
		-- If the result was positive, we just cut-off the sign bit.
		-- Both cases results in step_array(4) containing the corrected value
		-- 	step_array(4) = log(X*Y)
      IF step4(M) = '1' OR step4(M - 1 DOWNTO 0) = x"FF" THEN
        step_array(4) <= STD_LOGIC_VECTOR(UNSIGNED(step4(M - 1 DOWNTO 0)) + 255);
      ELSE
        step_array(4) <= step4(M - 1 DOWNTO 0);
      END IF;
		-- Finally, using the same logic as step 3, we calculate -log((S1_A)^2) using two's complement.
		-- Remember it is again 9 bits.
      minus_log_pow2_S1 <= STD_LOGIC_VECTOR(UNSIGNED(NOT ('0' & log_pow2_S1)) + 1);


      -- Step 6 (N+5)
      -- at this point we have:
		-- 	step_array(4) = log((S1_A)^3+S3_A)/S1_A) = log(XY) (corrected 8-bit rep).
		-- 	minus_log_pow2_S1 = -log((S1_A)^2)
		-- We want to calculate A. In the log domain, the division is subtraction, so doing the same as step 4
		-- we achieve the 9-bit, two's complement version of log(A).
      step6 <= STD_LOGIC_VECTOR(UNSIGNED('0' & step_array(4)) + UNSIGNED(minus_log_pow2_S1));


      -- Step 7 (N+6)
		-- Completely analog to step 5, we again correct log(A) from two's complement into the valid log range.
      IF step6(M) = '1' OR step6(M - 1 DOWNTO 0) = x"FF" THEN
        log_A <= STD_LOGIC_VECTOR(UNSIGNED(step6(M - 1 DOWNTO 0)) + 255);
      ELSE
        log_A <= step6(M - 1 DOWNTO 0);
      END IF;


      -- Step 8 (N+7)
      -- Now we have the correct 8-bit rep of log(A)
		-- This is the input to the root LUT
		-- So step 8 is handled by the port map.
		-- The return value is: 
		-- 	log_roots(15 downto 8) = log(z1)
		-- 	log_roots(7 downto 0) = log(z2)


      -- Step 9 (N+8)
      -- Now we have the log values for both roots in the normalized equation:
		-- 	z^2+z+A=0
		-- So we must get actual log values using:
		-- 	X = S1*z1
		-- 	Y = S1*z2
		-- in log domain, this is:
		-- 	log(X) = log(S1) + log(z1)
		-- 	log(Y) = log(S1) + log(z2)
		-- So we just check if each of the two roots are valid, and if they are, we scale them correctly.
		-- Again we get a 9 bit value, because the log arithemtic can overflow.
      IF log_roots(15 DOWNTO 8) /= x"FF" THEN
        error_l1 <= STD_LOGIC_VECTOR(
          UNSIGNED('0' & log_roots(15 DOWNTO 8)) +
          UNSIGNED('0' & log_S1_array(8))
        );
      ELSE
        error_l1 <= ('1' & x"FF"); -- if the root is invalid (we use "FF" as invalid), then we change the output of this step to be invalid too.
      END IF;

      IF log_roots(7 DOWNTO 0) /= x"FF" THEN
        error_l2 <= STD_LOGIC_VECTOR(
          UNSIGNED('0' & log_roots(7 DOWNTO 0)) +
          UNSIGNED('0' & log_S1_array(8))
        );
      ELSE
        error_l2 <= ('1' & x"FF");
      END IF;


      -- Step 10 (N+9)
		-- Now we have:
		-- 	error_l1 = raw 9-bit log(X)
		-- 	error_l2 = raw 9-bit log(Y)
		-- Since these values are received from an addition, we check if the sum overflowed
		-- If the value is over 255, then bit 9 will be 1, meaning we must reduce them both mod 255
		-- we add 1, because the "lower" 8 bits will be 1 smaller than what it should be.
		-- 	example: 300 dec = 100101100 binary. modulo 255 => 00101100 = 44, but it should be 45.
		-- We also check if we get the value 255 (x"FF"), because here, the 9th bit is not 1, but the lower 8 bits will be 0 mod 255.
		-- Here we use XOR instead of OR, because the value might be the "invalid" vector with all 1's (9th bit is 1 and lower 8 are all 1's too)
		-- if it were OR, we would be trying to correct it, when we in reality should just push it further in the pipeline, because the values are invalid.
		-- XOR handles this, because TRUE XOR TRUE = False, which would send is to the ELSE branch of the statement.

      IF ((error_l1(M) = '1') XOR (error_l1(M - 1 DOWNTO 0) = x"FF")) THEN
        error_location1 <= STD_LOGIC_VECTOR(UNSIGNED(error_l1(M - 1 DOWNTO 0)) + 1);
      ELSE
        error_location1 <= error_l1(M - 1 DOWNTO 0); -- if the 9th bit is not 1, we can just use the lower 8 bits, since we don't have an overflow.
      END IF;

      IF ((error_l2(M) = '1') XOR (error_l2(M - 1 DOWNTO 0) = x"FF")) THEN
        error_location2_0 <= STD_LOGIC_VECTOR(UNSIGNED(error_l2(M - 1 DOWNTO 0)) + 1);
      ELSE
        error_location2_0 <= error_l2(M - 1 DOWNTO 0);
      END IF;


      -- Step 11 (N+10)
      -- here we have:
		-- 	error_location 1/2 = corrected BCH error position for both errors (actual indexes in correct format)
		-- 	error_count_array(10) = delayed error classification
		-- 	message_parity(10) = delayed overall parity result.
		-- First we delay location 2, because we handle it on the next clock
		-- then we check if there are 2 errors. If there are, then we need both one_hot_encoders.
		-- The check is done by a two-fold check. In this way, a wrong classification can be "caught" by the overall parity. An error in the message_parity is handled later.
		-- Remember that for an overall XOR parity bit, it will be 0 if there are an EVEN number of errors.
		-- so the first one is "actually" the "second" one, because this will only ever create a bit-mask if there are 2 errors.

      error_location2_1 <= error_location2_0;

      IF (error_count_array(10) = TWO_ERRORS) AND (message_parity(10) = '0') THEN
        find_error_vectors_of_this(0) <= error_location1;
      ELSE
        find_error_vectors_of_this(0) <= x"FF";
      END IF;


      -- Step 12 (N+11)
		-- Here we have:
		-- 	messages(11) = delayed received codeword
		-- 	error_count_array(11) = classification (same as for N+10)
		-- 	message_parity(11) = parity result
		-- 	error_location2_1 = delayed second BCH error position
		-- 	log_S1_array(11) = log(S1)
		-- 
		-- First we handle the overall parity bit, because it is not covered by the BCH code.
		-- The check is rather simple: If the overall parity result does not match the amount of errors, we assume it is wrong and flip the bit.
		-- The 2 possible cases are for 1 error (should be 1 overall parity) and NO errors (should be 0 overall parity).
      IF (
        ((error_count_array(11) = ONE_ERROR) AND (message_parity(11) = '0')) OR
        ((error_count_array(11) = NO_ERRORS) AND (message_parity(11) = '1'))
      ) THEN
        messages(12)(0) <= NOT messages(11)(0); -- flip it
      ELSE
        messages(12)(0) <= messages(11)(0); -- keep it.
      END IF;

		-- In both cases, the BCH part is untouched, so we just move it along unchanged.
		-- We have to do this, because the parity bit has not updated yet on this clock
		-- meaning that if we just used messages(12)<=messages(11), then we would just keep the errorneous parity bit.
		
      messages(12)(2 ** M - 1 DOWNTO 1) <= messages(11)(2 ** M - 1 DOWNTO 1);

		
		-- The second part of step 12 is to find out if we need both one_hot_encoders.
		-- The check is the same as step 11.
      IF (error_count_array(11) = TWO_ERRORS) AND (message_parity(11) = '0') THEN
        find_error_vectors_of_this(1) <= error_location2_1; -- 2 errors means that step 11 has already handled one of them.

		-- If there is only 1 error, then step 11 creates an invalid input to the one_hot_encoder, and only step 12 will send a valid input.
      ELSIF (error_count_array(11) = ONE_ERROR) THEN
        find_error_vectors_of_this(1) <= log_S1_array(11); -- 1 error means S1 = alpha^i => i = log(S1).

      ELSE
        find_error_vectors_of_this(1) <= x"FF";
      END IF;


      -- Step 13 (N+12)
		-- here we have:
		-- 	messages(12) = codeword after parity bit is corrected.
		-- 	error_vectors(0) = one-hot mask for error location 1
		-- So we simply just flip the bit at the index where the bit-mask is 1.
		-- Finally we append the corrected parity bit by itself.
		-- We have to handle it seperately, because error_vectors is 255 bits long, but messages(12) is 256 bits long
		-- meaning that the XOR operation would flip the wrong bit if we XORed both vectors directly.
      messages(13) <= (messages(12)(2 ** M - 1 DOWNTO 1) XOR error_vectors(0)) & messages(12)(0);


      -- Step 14 (N+13)
		-- Exactly the same logic as step 13.
      messages(14) <= (messages(13)(2 ** M - 1 DOWNTO 1) XOR error_vectors(1)) & messages(13)(0);


      -- Step 15 (N+14)
		-- This is the final step. Here we have:
		-- 	messages(14) = corrected codeword
		-- 	data_out_valid(14) = valid bit aligned with the codeword
		-- 	error_count_array(14) = BCH error classification
		-- 	message_parity(14) = overall parity result.
		-- First we do mapping to the output of the module
      code_out <= messages(14);
      code_valid <= data_out_valid(14);

		-- Then we classify the amount of errors found. We are capable of correcting 2 errors, but we are capable of detecting 3
		-- If there are >= 3 errors, we cannot handle them, and '11' is an "invalid" code.
      IF (error_count_array(14) = NO_ERRORS AND message_parity(14) = '0') THEN
        errors_found <= "00";

      ELSIF (
        (error_count_array(14) = NO_ERRORS AND message_parity(14) = '1') OR
        (error_count_array(14) = ONE_ERROR AND message_parity(14) = '1')
      ) THEN
        errors_found <= "01";

      ELSIF (
        (error_count_array(14) = ONE_ERROR AND message_parity(14) = '0') OR
        (error_count_array(14) = TWO_ERRORS AND message_parity(14) = '0')
      ) THEN
        errors_found <= "10";

      ELSE
        errors_found <= "11";
      END IF;

    END IF;

  END PROCESS;

END ARCHITECTURE;