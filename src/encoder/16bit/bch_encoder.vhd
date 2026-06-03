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
		code_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- 16 bits for M=4
		code_valid : OUT STD_LOGIC
	);
END ENTITY;

ARCHITECTURE RTL OF bch_encoder IS
	CONSTANT N : INTEGER := 2 ** M - 1;
	CONSTANT R : INTEGER := M * T;

	CONSTANT message_length : INTEGER := 2 ** M - M * T - 1;
	CONSTANT K : INTEGER := message_length;
	-- Keep track of the original message bits
	TYPE message_array IS ARRAY (0 TO K) OF STD_LOGIC_VECTOR(R - 2 DOWNTO 0); -- 7 bits for M=4, T=2
	SIGNAL message_s : message_array := (OTHERS => (OTHERS => '0'));
	-- Keep track of the result of each round of modulo division
	TYPE result_array IS ARRAY (0 TO K) OF STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
	SIGNAL result_s : result_array := (OTHERS => (OTHERS => '0'));

	-- TYPE next_parity_array 		IS ARRAY (1 TO K) OF STD_LOGIC;
	-- TYPE prev_result_array 		IS ARRAY (1 TO K) OF STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
	-- internal signals
	SIGNAL valid_output : STD_LOGIC_VECTOR(K + 1 DOWNTO 1) := (OTHERS => '0');
	-- SIGNAL result_of_modulo : STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0) := (OTHERS => '0');
	-- SIGNAL message_reg : STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0');

	-- constants
	CONSTANT gen : STD_LOGIC_VECTOR(2 ** M - R DOWNTO 0) := "111010001"; -- generator polynomial for M=4, T=2

	-- CONSTANT zeroes : STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0) := (OTHERS => '0');

	function xor_reduce(v : std_logic_vector) return std_logic is
		variable x : std_logic := '0';
	begin
		for j in v'range loop
			x := x xor v(j);
		end loop;
		return x;
	end function;

BEGIN

	PROCESS (clk, rst)
	BEGIN
		IF rst = '1' THEN
			code_out <= (OTHERS => '0');
			code_valid <= '0';
			valid_output <= (OTHERS => '0');
			message_s(0) <= (OTHERS => '0');
		ELSIF (rising_edge(clk)) THEN

			IF data_valid = '1' THEN
				message_s(0) <= data_in; -- load the input message bits into the first element of the message array
				result_s(0) <= data_in(message_length - 1 DOWNTO 0) & "0";
				valid_output(1) <= '1';
			ELSE
				valid_output(1) <= '0';
			END IF;

			for i in 1 TO K LOOP
				valid_output(i + 1) <= valid_output(i);
			END LOOP;

			IF valid_output(K + 1) = '1' THEN
				code_out <= message_s(K) & result_s(K) & xor_reduce(message_s(K) & result_s(K));
				code_valid <= '1';
			ELSE
				code_valid <= '0';
			END IF;
			
		END IF;
	END PROCESS;
	
	mod_rounds : FOR i IN 1 TO K GENERATE
		modulo_divider : ENTITY work.gf_mod
			PORT MAP(
				clk => clk,
				rst => rst,
				message_pass_in => message_s(i - 1),
				message_pass_out => message_s(i),
				new_data_bit => message_s(i - 1)(K - i),

				prev_result => result_s(i - 1),
				result => result_s(i),

				current_parity => '0',
				next_parity => OPEN
			);
	END GENERATE;

END ARCHITECTURE;