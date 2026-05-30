-- bch_decoder
-- Feeds data in, appends remainder as parity bits
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY decoder IS
	GENERIC (
		M : INTEGER := 8; -- 2**m = length
		T : INTEGER := 2); -- error correction capability

	PORT (
		clk, rst : IN STD_LOGIC;
		data_in : IN STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
		data_valid : IN STD_LOGIC;
		code_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0);
		code_valid : OUT STD_LOGIC
	);
END ENTITY;

ARCHITECTURE RTL OF decoder IS
	--========================================================
	----------------------| COMPONENTS |----------------------
	--========================================================

	Component a_to_log_a_tabel is
		port(address  : in  std_logic_vector(7 DOWNTO 0); -- memory address
				 out  : out std_logic_vector(7 DOWNTO 0); -- value
			clk, rst  : in  std_logic 
			);
	end Component a_to_log_a_tabel;

	Component a_to_a_pow3_tabel is
		port(address  : in  std_logic_vector(7 DOWNTO 0); -- memory address
				 out  : out std_logic_vector(7 DOWNTO 0); -- value
			clk, rst  : in  std_logic 
			);
	end Component a_to_a_pow3_tabel;

	Component log_A_to_log_rootsOfA_tabel is
		port(address  : in  std_logic_vector(7 DOWNTO 0); -- memory address
				out   : out std_logic_vector(15 DOWNTO 0); -- value
			clk, rst  : in  std_logic
			);
	end Component log_A_to_log_rootsOfA_tabel;

	Component one_hot_encoder IS 
		PORT (
		clk, rst : IN STD_LOGIC;
		binary_in : IN STD_LOGIC_VECTOR(M - 1 DOWNTO 0);
		one_hot_out : OUT STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0');
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

	--all these arrays just pass values to the next step, after they are initialised
    SIGNAL S1_array IS ARRAY (0 TO 10) of STD_LOGIC_VECTOR(M - 1 DOWNTO 0)     := (OTHERS => (OTHERS => '0'));
    SIGNAL S3_array IS ARRAY (0 TO 10) of STD_LOGIC_VECTOR(M - 1 DOWNTO 0)     := (OTHERS => (OTHERS => '0'));
	SIGNAL log_S1_array IS ARRAY (2 TO 11) of STD_LOGIC_VECTOR(M - 1 DOWNTO 0) := (OTHERS => (OTHERS => '0'));
	SIGNAL is_either_0_or_1_errors IS ARRAY (3 to 13) of STD_LOGIC_VECTOR(1 DOWNTO 0) := (OTHERS => (OTHERS => '1'));
	SIGNAL messages IS ARRAY (0 to 16) of STD_LOGIC_VECTOR(M**2 -1 DOWNTO 0)  := (OTHERS => (OTHERS => '0'));
	SIGNAL data_out_valid : STD_LOGIC_VECTOR(0 to 16) := (OTHERS => '0');

	--a collection of 8 bit vectors where step_array(i+1) is the result of a calculation using step_array(i)
    SIGNAL step_array IS ARRAY (1 TO 4) of STD_LOGIC_VECTOR(M - 1 DOWNTO 0)    := (OTHERS => (OTHERS => '0')); -- step 4 is 5

	SIGNAL log_A : STD_LOGIC_VECTOR(M - 1 DOWNTO 0) := (OTHERS => '0'); --step7

	-- both roots so length is twice as long (T=2)
	-- result of using log_A to get roots from LUT
	SIGNAL log_roots : STD_LOGIC_VECTOR(M*T - 1 DOWNTO 0);

	--signed log values (result of subtraction)
		--get back to unsigned length 8 by adding 255 (if negative)
	SIGNAL step4, step6, minus_log_pow2_S1, minus_log_S1 : STD_LOGIC_VECTOR(M DOWNTO 0) := (OTHERS => '0');

	--log values with room for overflow (result of addition)
		--get back to length 8 by adding -255 (if >= 255)
	SIGNAL error_l1, error_l2 : STD_LOGIC_VECTOR(M DOWNTO 0) := (OTHERS => '0');

	SIGNAL error_location1, error_location2_0, error_location2_1 : STD_LOGIC_VECTOR(M-1 DOWNTO 0) := (OTHERS => '0');

	SIGNAL error_vectors IS ARRAY (0 to 1) of STD_LOGIC_VECTOR(M **2 - 2 DOWNTO 0);
	SIGNAL find_error_vectors_of_this IS ARRAY (0 to 1) of STD_LOGIC_VECTOR(M-1 DOWNTO 0);

BEGIN
	--=======================================================
	----------------------| PORT MAPS |----------------------
	--=======================================================

	--LUT's

	pow3_tabel_for_step1 : entity a_to_a_pow3_tabel
		PORT MAP(
			address => S1_array(0),  
			out => step_array(1), 
			clk => clk, rst => rst 
		);
	
	log_tabel_for_step2 : entity a_to_log_a_tabel
		PORT MAP(
			address => S1_array(1),  
			out => log_S1_array(2), 
			clk => clk, rst => rst 
		);

	log_tabel_for_step3 : entity a_to_log_a_tabel
		PORT MAP(
			address => step_array(2),  
			out => step_array(3), 
			clk => clk, rst => rst 
		);
	
	log_A_tabel_for_step8 : entity log_A_to_log_rootsOfA_tabel
		PORT MAP(
			address => log_A,  
			out => log_roots, 
			clk => clk, rst => rst 
		);

	--others

	syn_cal : entity syndrome_calculator 
		PORT MAP(
			clk => clk,
			rst => rst,
			data_in => data_in,
			data_valid => data_valid,

			S1 => S1_array(0),
			S3 => S3_array(0),
			data_out => messages(0),
			data_out_valid => data_out_valid(0),
			data_parity =>
		);

	one_hot_error_finders : FOR i IN 0 TO 1 GENERATE
		one_hot_error_finders : ENTITY one_hot_encoder
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
			
			messages <= (OTHERS => (OTHERS => '0'));
			data_out_valid <= (OTHERS => '0');

			S1_array <= (OTHERS => (OTHERS => '0'));
    		S3_array <= (OTHERS => (OTHERS => '0'));
			log_S1_array <= (OTHERS => (OTHERS => '0'));
			is_either_0_or_1_errors <= (OTHERS => (OTHERS => '1'));

			--TODO most other signals

		ELSIF (rising_edge(clk)) THEN 
			
			for i in 0 TO 9 LOOP
				S1_array(i + 1) <= S1_array(i);
			END LOOP;

            for i in 0 TO 9 LOOP
				S3_array(i + 1) <= S3_array(i);
			END LOOP;

			for i in 2 TO 10 LOOP
				log_S1_array(i+1) <= log_S1_array(i);
			END LOOP;

			for i in 3 TO 12 LOOP
				is_either_0_or_1_errors(i+1) <= is_either_0_or_1_errors(i);
			END LOOP;

			for i in 0 TO 10 LOOP
				messages(i+1) <= messages(i);
			END LOOP;

			data_out_valid(1 to 16) <= data_out_valid(0 to 15);
			
			--step 1 ==============================
			--find S1**3 

            --step_array(1) <= a_to_a_pow3_tabel(S1_array(0));
			
			--step 2 ==============================
			-- S1**3 xor S3

            step_array(2) <= (step_array(1) xor S3_array(1));
			--log_S1_array(2) <= a_to_log_a_tabel(S1_array(1))

			--step 3 ==============================
			-- test if 0 or 1 errors to override result later
				--since log(0) is undefined the next steps are undefined if there is 0 or 1 errors. 
				--therefore we wait for the computation to finish before overriding what errors to flip later. 

			is_either_0_or_1_errors(3)(0) <= ( S1_array(2) = x"00"  and S3_array(2) = x"00"); --S1 = 0
			is_either_0_or_1_errors(3)(1) <= ((S1_array(2) = x"00" nand S1_array(2) = x"00") and step_array(2) = x"00"); --S1**3 = S3 and  not S1=S3=0 
			
			minus_log_S1 <= (not ('0' & log_S1_array(2))) + 1;
			--step_array(3) <= a_to_log_a_tabel(step_array(2));

			--step 4 ==============================
			-- divide by S1 (-log_S1) 

            step4 <= ('0' & step_array(3)) + minus_log_S1; --step4 has length 9
			
		
			
			-- multiply by 2 (shift left), and ensure under 255, if over add -255
			log_pow2_S1 <= (log_S1_array(3)(M-2 downto 0) & log_S1_array(3)(M-1)); --works assuming log_S1_array(3) <

				--IF log_S1_array(3)(M-1) = '1' then -- multiply by 2 (shift left), and ensure under 255, if over add -255
				--	log_pow2_S1 <= (log_S1_array(3)(M-2 downto 0) & "1");
				--else then
				--	log_pow2_S1 <= (log_S1_array(3)(M-2 downto 0) & "0");
				--end IF;

			--step 5 ==============================
			--ensure over 0

			IF step4(M) = '1' or step4(M-1 downto 0) = x"FF" then -- if < 0, add 255 (x"FF")
				step_array(4) <= step4(M-1 downto 0)+x"FF"; --x"FF"
			else then
				step_array(4) <= step4(M-1 downto 0);
			end IF;
			
			minus_log_pow2_S1 <= (not ('0' & log_pow2_S1)) + 1;

            --step 6 ==============================
			-- divide by S1**2 (-log S1**2) to get log_A

			step6 <= ('0' & step_array(4)) + minus_log_pow2_S1; 
			
			--step 7 ===============================
			--find log_A by ensuring result from previous step is >= 0

			IF step6(M) = '1' or step6(M-1 downto 0) = x"FF" then -- if < 0, add 255
				log_A <= step6(M-1 downto 0) + x"FF"; 
			else then
				log_A <= step6(M-1 downto 0);
			end IF;

			--step 8 ==============================
			--find roots from tabel

			--log_roots = log_A_to_log_roots(log_A)					TODO
				--root1 = roots(15 downto 8);
				--root2 = roots( 7 downto 0);

			--step 9 ==============================
			--mult potential tabel entries with S1 (add log_S1)

			if (log_roots(15 downto 8) != x"FF") then --if there is an error * S1
				error_l1 <= ('0'&log_roots(15 downto 8)) + ('0'&log_S1_array(8));
			else then
				error_l1 <= x"FFF"(M downto 0); --the invalid error position
			end if;

			if (log_roots( 7 downto 0) != x"FF") then --if there is an error * S1
				error_l2 <= ('0'&log_roots( 7 downto 0)) + ('0'&log_S1_array(8));
			else then
				error_l2 <= x"FFF"(M downto 0); --the invalid error position
			end if;

			--step 10 ==============================
			--ensure under 255

			--((error_l1(M) = '1' or error_l1(M-1 downto 0) = x"FF") and (error_l1 != X"FFF"(M downto 0))) 
			-- is the same as
			--(error_l1(M) = '1' xor error_l1(M-1 downto 0) = x"FF")
			
			IF (error_l1(M) = '1' xor error_l1(M-1 downto 0) = x"FF") then -- ensure under 255, if over or equal, subtract 255
				error_location1 <= error_l1(M-1 downto 0)+x"01"; --x"01" = (not 255)+1 = -255 
			else then
				error_location1 <= error_l1(M-1 downto 0);
			end IF;

			IF (error_l1(M) = '1' xor error_l1(M-1 downto 0) = x"FF") then -- ensure under 255, if over or equal, subtract 255
				error_location2_0 <= error_l2(M-1 downto 0)+x"01"; --x"01" = (not 255)+1 = -255 
			else then
				error_location2_0 <= error_l2(M-1 downto 0); 
			end IF;


				--NOTE: error_locations are either 0-254 or 255
				-- 255 (x"FF") means no correctable error! (there are 3 or more errors)
				-- 0-254 is signal to correct the error at this position (excluding parity)

			--step 11 ==============================
			--one hot of error1

			error_location2_1 <= error_location2_0;
			--one hot encoding of 
			if (is_either_0_or_1_errors(10) = '00') then --if 2 or more errors
				-- error_location1
				find_error_vectors_of_this(0) <= error_location1;
			else then --there is only 1 or 0 errors
				find_error_vectors_of_this(0) <= x"FF";
					-- x"FF"
			end if;

			--step 12 ==============================
			--one hot of error2 and flip error1

			messages(12) <= (messages(11)(2**M-1 downto 1) xor (error_vectors(0))) & messages(11)(0);

			--one hot encoding of error_location 2 or S1 if step2
			if (is_either_0_or_1_errors(11) = '00') then 
				-- error_location2 
				find_error_vectors_of_this(1) <= error_location2_1;
			elsif (is_either_0_or_1_errors(11) = '01') then --one error
				-- log_S1_array(11)
				find_error_vectors_of_this(1) <= log_S1_array(11);
			else then -- 0 errors 
				find_error_vectors_of_this(1) <= x"FF";
				-- x"FF"
			end if;
			
			--step 13 ==============================
			--flip error2
			messages(13) <= (messages(12)(2**M-1 downto 1) xor (error_vectors(1))) & messages(12)(0);
			
				
			--step 14 ==============================
			messages(14) <= messages(13);
				


			--step 15 ==============================
			messages(15) <= messages(14);

			--step 16 ==============================
			messages(16) <= messages(15);
			--step 17 ==============================
			code_out <= messages(16);
			code_out_valid <= data_out_valid(16);
				
		END IF;
	END PROCESS;

END ARCHITECTURE;

	-- TODO: 
	-- TB's 
	-- dont ignore parity (lol)
	-- clean up arrays / other code
	-- remove extra / empty steps