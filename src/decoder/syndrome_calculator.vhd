-- syndrome_calculator
-- Takes a message, returns the message and its syndromes (S1 and S3)
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY syndrome_calculator IS
	GENERIC (
		M : INTEGER := 8; -- log_2(message length)
		T : INTEGER := 2); -- error correction capability/ syndrome count

	PORT (
		clk, rst : IN STD_LOGIC;
		data_in : IN STD_LOGIC_VECTOR(2**M - 1 DOWNTO 0); -- 
		data_valid : IN STD_LOGIC;

		data_out : OUT STD_LOGIC_VECTOR(2**M-1 DOWNTO 0); -- 256 bits for M=8
		data_out_valid : OUT STD_LOGIC;
		data_parity : OUT STD_LOGIC; -- 0 is data has even parity, 1 is uneven
		S1,S3 : OUT STD_LOGIC_VECTOR(M-1 DOWNTO 0)
	);
END ENTITY;

ARCHITECTURE RTL OF syndrome_calculator IS
	--=========================================================================================
	-------------------------------------| LUT GENERATION |------------------------------------
	--=========================================================================================
	
	-- LUT type for GF(256) elements.
	TYPE LUT_type IS ARRAY (0 TO 255) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
	-- Multiply by alpha in GF(2^8).
	-- Primitive polynomial:
	--   p(x) = x^8 + x^4 + x^3 + x^2 + 1
	-- Hex: 0x11D.
	-- After shifting left, if an x^8 term appears, reduce back to 8 bits
	-- by XORing with 0x1D.
	FUNCTION multiply_by_alpha(
		a : in UNSIGNED(7 DOWNTO 0)) 
		RETURN UNSIGNED IS
		VARIABLE shifted_v : UNSIGNED(7 DOWNTO 0) ;
	BEGIN
		shifted_v := a(6 DOWNTO 0) & '0';

		IF a(7) = '1' THEN
		shifted_v := shifted_v XOR TO_UNSIGNED(16#1D#,8);
		END IF;

		RETURN shifted_v;
	END FUNCTION;

	-- Multiply by alpha^3.
	-- This is used for the S3 syndrome.
	FUNCTION multiply_by_alpha3(
		a : in UNSIGNED(7 DOWNTO 0)) 
		RETURN UNSIGNED IS
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
		VARIABLE a_v   : UNSIGNED(7 DOWNTO 0) := TO_UNSIGNED(1,8);
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
		VARIABLE a_v   : UNSIGNED(7 DOWNTO 0) := TO_UNSIGNED(1,8);
	BEGIN
		FOR log_i IN 0 TO 254 LOOP
		lut_v(log_i) := STD_LOGIC_VECTOR(a_v);
		a_v := multiply_by_alpha3(a_v);
		END LOOP;

		RETURN lut_v;
	END FUNCTION;

	CONSTANT LOG_A_TO_A_LUT      : LUT_type := build_alpha_lut;
	CONSTANT LOG_A_TO_A_POW3_LUT : LUT_type := build_alpha_pow3_lut;


	--=========================================================================================
	----------------------------------| XOR TREE DEFINITION |----------------------------------
	--=========================================================================================

	constant clk_cycles : INTEGER := 3; --clk used to finish the xor tree
	TYPE data_array IS ARRAY (1 TO clk_cycles) OF STD_LOGIC_VECTOR(2**M DOWNTO 0); --msb is data_valid, the rest is the original message
	SIGNAL raw_data_array : data_array := (OTHERS => (OTHERS => '0'));
	--each "node" in the xor tree is a 17 bit vector that contains data to calculate the following:
	-- msb              lsb
	-- parity & [S1] & [S3] 
	
	--som of the layers in the tree are wired together to do multiple xor operations per clock
	--the layers are wired in a 2 - 3 - 3 pattern so the layers are done like this: 8-7, 6-5-4, 3-2-1
	TYPE t8 IS ARRAY (2**8-1 DOWNTO 0) of STD_LOGIC_VECTOR(M*T DOWNTO 0);
	TYPE t7 IS ARRAY (2**7-1 DOWNTO 0) of STD_LOGIC_VECTOR(M*T DOWNTO 0);
	TYPE t6 IS ARRAY (2**6-1 DOWNTO 0) of STD_LOGIC_VECTOR(M*T DOWNTO 0);
	TYPE t5 IS ARRAY (2**5-1 DOWNTO 0) of STD_LOGIC_VECTOR(M*T DOWNTO 0);
	TYPE t4 IS ARRAY (2**4-1 DOWNTO 0) of STD_LOGIC_VECTOR(M*T DOWNTO 0);
	TYPE t3 IS ARRAY (2**3-1 DOWNTO 0) of STD_LOGIC_VECTOR(M*T DOWNTO 0);
	TYPE t2 IS ARRAY (2**2-1 DOWNTO 0) of STD_LOGIC_VECTOR(M*T DOWNTO 0);
	TYPE t1 IS ARRAY (2-1    DOWNTO 0) of STD_LOGIC_VECTOR(M*T DOWNTO 0);
	SIGNAL xor_array8 : t8 := (OTHERS => (OTHERS => '0'));
	SIGNAL xor_array7 : t7 ;
	SIGNAL xor_array6 : t6 := (OTHERS => (OTHERS => '0'));
	SIGNAL xor_array5 : t5 ;
	SIGNAL xor_array4 : t4 ;
	SIGNAL xor_array3 : t3 := (OTHERS => (OTHERS => '0'));
	SIGNAL xor_array2 : t2 ;
	SIGNAL xor_array1 : t1 ;
	
begin
	--clk 1
	xor1 :FOR i IN 0 TO (2**7)-1 GENERATE		
		xor_array7(i) <= xor_array8(i*2) xor xor_array8(i*2+1);
	END GENERATE;
	
	--clk 2
	xor2_1 :FOR i IN 0 TO (2**5)-1 GENERATE		
		xor_array5(i) <= xor_array6(i*2) xor xor_array6(i*2+1);
	END GENERATE;

	xor2_2 :FOR i IN 0 TO (2**4)-1 GENERATE			
		xor_array4(i) <= xor_array5(i*2) xor xor_array5(i*2+1);
	END GENERATE;

	--clk 3
	xor3_1 :FOR i IN 0 TO (2**2)-1 GENERATE		
		xor_array2(i) <= xor_array3(i*2) xor xor_array3(i*2+1);
	END GENERATE;

	xor3_2 :FOR i IN 0 TO (2)-1 GENERATE			
		xor_array1(i) <= xor_array2(i*2) xor xor_array2(i*2+1);
	END GENERATE;


	--==========================================================
	----------------------| MAIN PROCESS |----------------------
	--==========================================================

	P1 : process(clk, rst)
	begin
		IF rst = '1' THEN

			data_parity <= '0';
			data_out <= (OTHERS => '0');
			data_out_valid <= '0';
			raw_data_array <= (OTHERS => (OTHERS => '0'));
			S1 <= (OTHERS => '0');
			S3 <= (OTHERS => '0');
			
			xor_array8 <=  (OTHERS => (OTHERS => '0'));
			xor_array6 <=  (OTHERS => (OTHERS => '0'));
			xor_array3 <=  (OTHERS => (OTHERS => '0'));
			

		ELSIF (rising_edge(clk)) THEN
			-- pass data along every clk
			for i in 1 to (clk_cycles -1) LOOP
				raw_data_array(i+1) <= raw_data_array(i);
			END LOOP;

			-- ================== clk 0 ===================
			--parity has no effect on the syndrome calculation
			xor_array8(0)(M*T -1 downto 0) <= (OTHERS => '0');

			raw_data_array(1)(2**M) <= data_valid;

			IF data_valid = '1' THEN
				raw_data_array(1)(2**M-1 downto 0) <= data_in; -- store the input message bits into the first element of the message array

				for i in 0 TO (2**8)-1 LOOP 
					xor_array8(i)(M*T) <= data_in(i); --parity
				END LOOP;

				--note: (xor_array8(0)) is 0's 
				for i in 1 TO (2**8)-1 LOOP 
					IF data_in(i) = '1' THEN --notice how for each value of i, the value is a constant or 0's
									   		 --and that the tabel dosen't exist for every value.
						xor_array8(i)(M*T -1 downto 0) <= LOG_A_TO_A_LUT(i-1) & LOG_A_TO_A_POW3_LUT(i-1); -- [S1] & [S3]
					else
						xor_array8(i)(M*T -1 downto 0) <= (OTHERS => '0');
					end if;
				END LOOP;

			ELSE --data_valid != '1'
				xor_array8(0)(M*T) <= '0'; --the rest of (xor_array(0)) is always 0's 
				for i in 1 TO (2**8)-1 LOOP 
					xor_array8(i) <=  (OTHERS => '0');
				end LOOP;
				raw_data_array(1)(2**M-1 downto 0) <= (OTHERS => '0');
			END IF;

			-- ================== clk 1 ===================
			for i in 0 TO (2**6)-1 LOOP
				xor_array6(i) <= xor_array7(i*2) xor xor_array7(i*2+1);
			END LOOP;

			-- ================== clk 2 ===================
			for i in 0 TO (2**3)-1 LOOP			
				xor_array3(i) <= xor_array4(i*2) xor xor_array4(i*2+1);
			END LOOP;

			
			-- =============== last clk (3) ================
			data_parity <= xor_array1(0)(M*T) xor xor_array1(1)(M*T);
			S1 <= xor_array1(0)(M*T-1 DOWNTO M) xor xor_array1(1)(M*T-1 DOWNTO M); 
			S3 <= xor_array1(0)(M-1 DOWNTO 0) xor xor_array1(1)(M-1 DOWNTO 0);
			
			data_out <= raw_data_array(clk_cycles)(2**M-1 downto 0);
			data_out_valid <= raw_data_array(clk_cycles)(2**M);

		end if;
		
	end process;
END architecture RTL;