-- bch_encoder
-- Feeds data in, appends remainder as parity bits
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY bch_encoder IS
	GENERIC (
		M : INTEGER := 4; -- message length
		T : INTEGER := 2); -- error correction capability
		
		PORT (
			clk, rst : IN STD_LOGIC;
			data_in : IN STD_LOGIC_VECTOR(2 ** M - M * T - 1 - 1 DOWNTO 0); -- 7 bits for M=4, T=2
			data_valid : IN STD_LOGIC;
			code_out : OUT STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0); -- 15 bits for M=4
			code_valid : OUT STD_LOGIC
		);
END ENTITY;
			
ARCHITECTURE RTL OF bch_encoder IS
	CONSTANT N : INTEGER := 2 ** M - 1;
	CONSTANT R : INTEGER := M * T;
	
	CONSTANT message_length : INTEGER := 2 ** M - M * T - 1
	CONSTANT K : INTEGER := message_length;


	TYPE message_array 			IS ARRAY (1 TO K) OF STD_LOGIC_VECTOR(N - 1 DOWNTO 0);
	-- TYPE prev_result_array 		IS ARRAY (1 TO K) OF STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
	TYPE new_data_bit_array 	IS ARRAY (1 TO K) OF STD_LOGIC;
	TYPE parity_array 	IS ARRAY (0 TO K) OF STD_LOGIC;
	TYPE result_array 			IS ARRAY (0 TO K) OF STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
	-- TYPE next_parity_array 		IS ARRAY (1 TO K) OF STD_LOGIC;

	-- internal signals
	SIGNAL parity_bit : STD_LOGIC = '0';
	-- SIGNAL result_of_modulo : STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0) := (OTHERS => '0');
	-- SIGNAL message_reg : STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0');
	
	-- constants
	CONSTANT gen : STD_LOGIC_VECTOR(2 ** M DOWNTO 0) := '111010001'; -- generator polynomial for M=4, T=2
	-- CONSTANT zeroes : STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0) := (OTHERS => '0');

	BEGIN

	process(clk, rst)
	BEGIN
		IF rst = '1' THEN
			code_out <= (OTHERS => '0');
			code_valid <= '0';
		ELSIF (rising_edge(clk) and data_valid) THEN
			message_array(0) <= data_in & (OTHERS => '0');
			result_array(0) <= data_in(message_length - 1 DOWNTO message_length - 1 - R);
			new_data_bit_array(1) <= data_in(message_length - 1 - R - 1);
			parity_array(0) <= xor data_in(message_length - 1 DOWNTO message_length - 1 - R);


			code_out <= message_array(K) & result_array(K) & xor (result_array(K) & parity_array(K))  
		END IF;
	END PROCESS;


	mod_rounds : FOR i IN 1 TO K GENERATE
		modulo_divider : ENTITY work.gf_mod
			PORT MAP(
				clk => clk,
				rst => rst,
				message_pass_in => message_array(i-1),
				message_pass_out => message_array(i),
				new_data_bit => new_data_bit_array(i),
				
				prev_result => result_array(i-1),
				result => result_array(i),

				current_parity => parity_array(i-1),
				next_parity => parity_array(i),
			);
	END GENERATE;


	-- TODO: after all rounds, we need to combine the final message and parity bits into the output codeword
	-- TODO: valid signal should be asserted after the last round is complete, which is after K clock cycles of processing the input data

	-- message_reg <= data_in + result_of_modulo;
	-- parity_bit <= XOR message_reg;
	--code_out <= message_reg + parity_bit;

END ARCHITECTURE;