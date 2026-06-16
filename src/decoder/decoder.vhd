-- bch_decoder
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY decoder IS
	GENERIC (
		M : INTEGER := 8; -- 2**m = length
		T : INTEGER := 2); -- error correction capability

	PORT (
		clk, rst : IN STD_LOGIC;
		data_in : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
		data_valid : IN STD_LOGIC;
		code_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
		code_valid : OUT STD_LOGIC;
		errors_found : OUT STD_LOGIC_VECTOR(1 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE RTL OF decoder IS
	--========================================================
	----------------------| COMPONENTS |----------------------
	--========================================================

	Component a_to_log_a_tabel is
		port(address  : in  std_logic_vector(7 DOWNTO 0); -- memory address
			contents  : out std_logic_vector(7 DOWNTO 0); -- value
			clk, rst  : in  std_logic 
			);
	end Component a_to_log_a_tabel;

	Component a_to_a_pow3_tabel is
		port(address  : in  std_logic_vector(7 DOWNTO 0); -- memory address
			contents  : out std_logic_vector(7 DOWNTO 0); -- value
			clk, rst  : in  std_logic 
			);
	end Component a_to_a_pow3_tabel;

	Component log_A_to_log_rootsOfA_tabel is
		port(address  : in  std_logic_vector(7 DOWNTO 0); -- memory address
		contents   : out std_logic_vector(15 DOWNTO 0); -- value
			clk, rst  : in  std_logic
			);
	end Component log_A_to_log_rootsOfA_tabel;

	Component one_hot_encoder IS 
		PORT (
		clk, rst : IN STD_LOGIC;
		binary_in : IN STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
		one_hot_out : OUT STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0')
		);
	END Component one_hot_encoder;

	Component syndrome_calculator IS
		PORT (
		clk, rst : IN STD_LOGIC;
		data_in : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- 
		data_valid : IN STD_LOGIC;

		data_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- 256 bits for M=8
		data_out_valid : OUT STD_LOGIC;
		data_parity : OUT STD_LOGIC; -- 0 is data has even parity, 1 is uneven
		S1,S3 : OUT STD_LOGIC_VECTOR(M-1 DOWNTO 0)
		);
	END Component syndrome_calculator;

	--=====================================================
	----------------------| SIGNALS |----------------------
	--=====================================================
	Constant FINAL_ARRAY_INDEX : INTEGER  := 11;

	--all these arrays just pass values to the next step, after they are initialised
	TYPE S1_array_t IS ARRAY (1 TO 2) of STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
	TYPE S3_array_t IS ARRAY (1 TO 2) of STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
    SIGNAL S1_array : S1_array_t     := (OTHERS => (OTHERS => '0'));
    SIGNAL S3_array : S3_array_t     := (OTHERS => (OTHERS => '0'));
	SIGNAL S1_array0, S3_array0 : STD_LOGIC_VECTOR(M - 1 DOWNTO 0);

	TYPE log_S1_array_t IS ARRAY (3 TO 11) of STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
	SIGNAL log_S1_array : log_S1_array_t := (OTHERS => (OTHERS => '0'));
	SIGNAL log_S1_array2 : STD_LOGIC_VECTOR(M - 1 DOWNTO 0);

	TYPE error_count_type is (
		NO_ERRORS,
		ONE_ERROR,
		TWO_ERRORS,
		INVALID
	);
	TYPE error_count_array_t IS ARRAY (3 to FINAL_ARRAY_INDEX) of error_count_type;
	SIGNAL error_count_array : error_count_array_t := (OTHERS => INVALID);

	TYPE messages_t IS ARRAY (1 to FINAL_ARRAY_INDEX) of STD_LOGIC_VECTOR(2**M -1 DOWNTO 0);
	SIGNAL messages : messages_t  := (OTHERS => (OTHERS => '0'));
	SIGNAL messages0 : STD_LOGIC_VECTOR(2**M -1 DOWNTO 0);
	SIGNAL data_out_valid : STD_LOGIC_VECTOR(1 to FINAL_ARRAY_INDEX) := (OTHERS => '0');
	SIGNAL message_parity : STD_LOGIC_VECTOR(1 to FINAL_ARRAY_INDEX) := (OTHERS => '0');
	SIGNAL data_out_valid0, message_parity0 : STD_LOGIC; 

	--a collection of 8 bit vectors where step_array(i+1) is the result of a calculation using step_array(i)
	TYPE step_array_t IS ARRAY (1 TO 4) of STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
    SIGNAL step_array : step_array_t := (OTHERS => (OTHERS => '0')); -- step 4 is 5

	SIGNAL log_A : STD_LOGIC_VECTOR(M - 1 DOWNTO 0) := (OTHERS => '0'); --step7

	-- both roots so length is twice as long (T=2)
	-- result of using log_A to get roots from LUT
	SIGNAL log_roots : STD_LOGIC_VECTOR(M*T - 1 DOWNTO 0);

	SIGNAL log_pow2_S1 : STD_LOGIC_VECTOR(M - 1 DOWNTO 0);

	--signed log values (result of subtraction)
		--get back to unsigned length 8 by adding 255 (if negative)
	SIGNAL step4, step6, minus_log_pow2_S1, minus_log_S1 : STD_LOGIC_VECTOR(M DOWNTO 0) := (OTHERS => '0');

	--log values with room for overflow (result of addition)
		--get back to length 8 by adding -255 (if >= 255)
	SIGNAL error_l1, error_l2 : STD_LOGIC_VECTOR(M DOWNTO 0) := (OTHERS => '0');

	SIGNAL error_location1, error_location2 : STD_LOGIC_VECTOR(M-1 DOWNTO 0) := (OTHERS => '0');
	
	TYPE error_vectors_t IS ARRAY (0 to 1) of STD_LOGIC_VECTOR(2**M - 2 DOWNTO 0);
	SIGNAL error_vectors : error_vectors_t;
	TYPE find_error_vectors_of_this_t IS ARRAY (0 to 1) of STD_LOGIC_VECTOR(M-1 DOWNTO 0);
	SIGNAL find_error_vectors_of_this : find_error_vectors_of_this_t := (OTHERS => (OTHERS => '1'));

BEGIN
	--=======================================================
	----------------------| PORT MAPS |----------------------
	--=======================================================

	--LUT's

	pow3_tabel_for_step1 : entity work.a_to_a_pow3_tabel
		PORT MAP(
			address => S1_array0,  
			contents => step_array(1), 
			clk => clk, rst => rst 
		);
	
	log_tabel_for_step2 : entity work.a_to_log_a_tabel
		PORT MAP(
			address => S1_array(1),  
			contents => log_S1_array2, 
			clk => clk, rst => rst 
		);

	log_tabel_for_step3 : entity work.a_to_log_a_tabel
		PORT MAP(
			address => step_array(2),  
			contents => step_array(3), 
			clk => clk, rst => rst 
		);
	
	log_A_tabel_for_step8 : entity work.log_A_to_log_rootsOfA_tabel
		PORT MAP(
			address => log_A,  
			contents => log_roots, 
			clk => clk, rst => rst 
		);

	--others

	syn_cal : entity work.syndrome_calculator 
		PORT MAP(
			clk => clk,
			rst => rst,
			data_in => data_in,
			data_valid => data_valid,

			S1 => S1_array0,
			S3 => S3_array0,
			data_out => messages0,
			data_out_valid => data_out_valid0,
			data_parity => message_parity0
		);

	one_hot_error_finders : FOR i IN 0 TO 1 GENERATE
		one_hot_error_finders : ENTITY work.one_hot_encoder
			PORT MAP(
				clk => clk,
				rst => rst,

				binary_in => find_error_vectors_of_this(i),
				one_hot_out => error_vectors(i)
			);
	END GENERATE;


	--==========================================================
	----------------------| MAIN PROCESS |----------------------
	--==========================================================
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

			--TODO most other signals

		ELSIF (rising_edge(clk)) THEN 
			
			for i in 1 TO 1 LOOP
				S1_array(i + 1) <= S1_array(i);
			END LOOP;
			S1_array(1) <= S1_array0;

            for i in 1 TO 1 LOOP
				S3_array(i + 1) <= S3_array(i);
			END LOOP;
			S3_array(1) <= S3_array0;

			for i in 3 TO 10 LOOP
				log_S1_array(i+1) <= log_S1_array(i);
			END LOOP;
			log_S1_array(3) <= log_S1_array2;

			for i in 3 TO FINAL_ARRAY_INDEX-1 LOOP
				error_count_array(i+1) <= error_count_array(i);
			END LOOP;
			messages(1) <= messages0;
			for i in 1 TO 9 LOOP
				messages(i+1) <= messages(i);
			END LOOP;
			data_out_valid(1) <= data_out_valid0;
			message_parity(1) <= message_parity0;
			data_out_valid(2 to FINAL_ARRAY_INDEX) <= data_out_valid(1 to FINAL_ARRAY_INDEX-1);
			message_parity(2 to FINAL_ARRAY_INDEX) <= message_parity(1 to FINAL_ARRAY_INDEX-1);
 			
			--step 1 ==============================
			--find S1**3 

            --step_array(1) <= a_to_a_pow3_tabel(S1_array(0));
			
			--step 2 ==============================
			-- S1**3 xor S3

            step_array(2) <= (step_array(1) xor S3_array(1));
			--log_S1_array2 <= a_to_log_a_tabel(S1_array(1))

			--step 3 ==============================
			-- test if 0 or 1 errors to override result later (excluding parity)
				--since log(0) is undefined the next steps are undefined if there is 0 or 1 errors. 
				--therefore we wait for the computation to finish before overriding what errors to flip later.
			IF data_out_valid(2) = '0' THEN
				error_count_array(3) <= INVALID;
			elsif ( S1_array(2) = x"00"  and S3_array(2) = x"00") THEN
				error_count_array(3) <= NO_ERRORS; --S1 = 0
			elsif (step_array(2) = x"00") THEN 
				error_count_array(3) <= ONE_ERROR;
			else
				error_count_array(3) <= TWO_ERRORS;
			END IF;

			  
			
			minus_log_S1 <= std_logic_vector(unsigned(not ('0' & log_S1_array2)) + 1);
			--step_array(3) <= a_to_log_a_tabel(step_array(2));

			--step 4 ==============================
			-- divide by S1 (-log_S1) 

            step4 <= std_logic_vector(unsigned('0' & step_array(3)) + unsigned(minus_log_S1)); --step4 has length 9
			
		
			
			-- multiply by 2 (shift left), and ensure under 255, if over add -255
			log_pow2_S1 <= (log_S1_array(3)(M-2 downto 0) & log_S1_array(3)(M-1)); --works assuming log_S1_array(3) <

				--IF log_S1_array(3)(M-1) = '1' then -- multiply by 2 (shift left), and ensure under 255, if over add -255
				--	log_pow2_S1 <= (log_S1_array(3)(M-2 downto 0) & "1");
				--else
				--	log_pow2_S1 <= (log_S1_array(3)(M-2 downto 0) & "0");
				--end IF;

			--step 5 ==============================
			--ensure over 0

			IF step4(M) = '1' or step4(M-1 downto 0) = x"FF" then -- if < 0, add 255 (x"FF")
				step_array(4) <= std_logic_vector(unsigned(step4(M-1 downto 0)) + 255); --x"FF"
			else
				step_array(4) <= step4(M-1 downto 0);
			end IF;
			
			minus_log_pow2_S1 <= std_logic_vector(unsigned(not ('0' & log_pow2_S1)) + 1);

            --step 6 ==============================
			-- divide by S1**2 (-log S1**2) to get log_A

			step6 <= std_logic_vector(unsigned('0' & step_array(4)) + unsigned(minus_log_pow2_S1)); 
			
			--step 7 ===============================
			--find log_A by ensuring result from previous step is >= 0

			IF step6(M) = '1' or step6(M-1 downto 0) = x"FF" then -- if < 0, add 255
				log_A <= std_logic_vector(unsigned(step6(M-1 downto 0)) + 255);--+ x"FF"; 
			else
				log_A <= step6(M-1 downto 0);
			end IF;

			--step 8 ==============================
			--find roots from tabel

			--log_roots = log_A_to_log_roots(log_A)
				--root1 = log_roots(15 downto 8);
				--root2 = log_roots( 7 downto 0);

			--step 9 ==============================
			--mult potential tabel entries with S1 (add log_S1)

			if (log_roots(15 downto 8) /= x"FF") then --if there is an error * S1
				error_l1 <= std_logic_vector(unsigned('0'&log_roots(15 downto 8)) + unsigned('0'&log_S1_array(8)));
			else
				error_l1 <= ('1' & x"FF"); --the invalid error position
			end if;

			if (log_roots( 7 downto 0) /= x"FF") then --if there is an error * S1
				error_l2 <= std_logic_vector(unsigned('0'&log_roots( 7 downto 0)) + unsigned('0'&log_S1_array(8)));
			else
				error_l2 <= ('1' & x"FF"); --the invalid error position
			end if;

			
			--ensure under 255

			--((error_l1(M) = '1' or error_l1(M-1 downto 0) = x"FF") and (error_l1 /= X"FFF"(M downto 0))) 
			-- is the same as
			--(error_l1(M) = '1' xor error_l1(M-1 downto 0) = x"FF")
			
			--IF ((error_l1(M) = '1') xor error_l1(M-1 downto 0) = x"FF") then -- ensure under 255, if over or equal, subtract 255
			--	error_location1 <= std_logic_vector(unsigned(error_l1(M-1 downto 0))+1); --x"01" = (not 255)+1 = -255 
				--error_location1 <= std_logic_vector(unsigned(error_l1(M-1 downto 0)));
			--else
			--	error_location1 <= error_l1(M-1 downto 0);
			--end IF;

			--IF ((error_l2(M) = '1') xor (error_l2(M-1 downto 0) = x"FF")) then -- ensure under 255, if over or equal, subtract 255
				--error_location2_0 <= std_lo error_l2(M-1 downto 0)+x"01"; --x"01" = (not 255)+1 = -255 
			--	error_location2 <= std_logic_vector(unsigned(error_l2(M-1 downto 0))+1);
				--error_location2_0 <= std_logic_vector(unsigned(error_l2(M-1 downto 0)));
			--else
			--	error_location2 <= error_l2(M-1 downto 0); 
			--end IF;
	

			
			--one hot encoding of 
			--if (error_count_array(10) = TWO_ERRORS) and (message_parity(10) = '0') then --if 2+ errors and there is an even error count
				
			--	find_error_vectors_of_this(0) <= error_location1;
			
			--else --there is an uneven error count or 0 
			--	find_error_vectors_of_this(0) <= x"FF"; --dont flip a bit in message
					-- x"FF"
			--end if;
			--one hot encoding of error_location 2 or S1 if step2
			--if (error_count_array(10) = TWO_ERRORS) and (message_parity(10) = '0') then --2 (or more) errors and even error count
			--	find_error_vectors_of_this(1) <= error_location2;

			--elsif (error_count_array(10) = ONE_ERROR) then --the parity is ignored here since 
			--	find_error_vectors_of_this(1) <= log_S1_array(11);

			--else -- 0 errors 
			--	find_error_vectors_of_this(1) <= x"FF"; --dont flip a bit in message
				
			--end if;
			
			



			--step 10 ==============================

			--NOTE: error_locations are either 0-254 or 255
			-- 255 (x"FF") means no correctable error! (there are 3 or more errors)
			-- 0-254 is signal to correct the error at this position (excluding parity)

			--if the 


			--one hot of error1
			--one hot encoding of error_l1
			if (error_count_array(9) = TWO_ERRORS) and (message_parity(9) = '0') then --if 2+ errors and there is an even error count
				IF ((error_l1(M) = '1') xor error_l1(M-1 downto 0) = x"FF") then -- ensure under 255, if over or equal, subtract 255
					find_error_vectors_of_this(0) <= std_logic_vector(unsigned(error_l1(M-1 downto 0))+1); --x"01" = (not 255)+1 = -255 
				--error_location1 <= std_logic_vector(unsigned(error_l1(M-1 downto 0)));
				else
					find_error_vectors_of_this(0) <= error_l1(M-1 downto 0);
				end IF;
				
			
			else --there is an uneven error count or 0 
				find_error_vectors_of_this(0) <= x"FF"; --dont flip a bit in message
					-- x"FF"
			end if;


			--one hot of error2
			--one hot encoding of error_l2 or S1 if step2
			if (error_count_array(9) = TWO_ERRORS) and (message_parity(9) = '0') then --2 (or more) errors and even error count
				IF ((error_l2(M) = '1') xor (error_l2(M-1 downto 0) = x"FF")) then -- ensure under 255, if over or equal, subtract 255
					--error_location2_0 <= std_lo error_l2(M-1 downto 0)+x"01"; --x"01" = (not 255)+1 = -255 
					find_error_vectors_of_this(1) <= std_logic_vector(unsigned(error_l2(M-1 downto 0))+1);
					--error_location2_0 <= std_logic_vector(unsigned(error_l2(M-1 downto 0)));
				else
					find_error_vectors_of_this(1) <= error_l2(M-1 downto 0); 
				end IF;

			elsif (error_count_array(9) = ONE_ERROR) then --the parity is ignored here since 
				find_error_vectors_of_this(1) <= log_S1_array(9);

			else -- 0 errors 
				find_error_vectors_of_this(1) <= x"FF"; --dont flip a bit in message
				
			end if;
			--step 11 ==============================
			--one hot of error1 and error2, flip parity if relevant
			

			--if there is exactly 1 error and the parity of the message is even
				--assume the parity bit is an error

			--if there is no errors but the parity is wrong, 
				--flip the parity bit
			IF (((error_count_array(10) = ONE_ERROR) and (message_parity(10) = '0')) or ((error_count_array(10) = NO_ERRORS) and (message_parity(10) = '1'))) THEN
				messages(11)(0) <= not messages(10)(0); --flip parity bit
			ELSE
				messages(11)(0) <= messages(10)(0); --pass parity bit
			END IF;
			--pass the rest of the message along
			messages(11)(2**M-1 downto 1) <= messages(10)(2**M-1 downto 1);

			
			--step 12 ==============================
			--flip error1 and error2			
			--output the corrected message and the errors found
			code_out <= (messages(FINAL_ARRAY_INDEX)(2**M-1 downto 1) xor ((error_vectors(0)) or (error_vectors(1)))) & messages(FINAL_ARRAY_INDEX)(0);

			code_valid <= data_out_valid(FINAL_ARRAY_INDEX);

			if (error_count_array(FINAL_ARRAY_INDEX) = NO_ERRORS and message_parity(FINAL_ARRAY_INDEX) = '0') then
				errors_found <= "00"; --0
			elsif ((error_count_array(FINAL_ARRAY_INDEX) = NO_ERRORS and message_parity(FINAL_ARRAY_INDEX) = '1') or 
				   (error_count_array(FINAL_ARRAY_INDEX) = ONE_ERROR and message_parity(FINAL_ARRAY_INDEX) = '1')) then

				errors_found <= "01"; --1
			elsif ((error_count_array(FINAL_ARRAY_INDEX) = ONE_ERROR and message_parity(FINAL_ARRAY_INDEX) = '0') or 
				   (error_count_array(FINAL_ARRAY_INDEX) = TWO_ERRORS and message_parity(FINAL_ARRAY_INDEX) = '0')) then
				errors_found <= "10"; --2
			else 
				errors_found <= "11"; --3 or more
			end if;
				

				
		END IF;
	END PROCESS;

END ARCHITECTURE;