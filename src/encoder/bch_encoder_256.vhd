-- bch_encoder
-- Feeds data in, appends remainder as parity bits
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY bch_encoder_256 IS
	GENERIC (
		M : INTEGER := 8; -- message length
		T : INTEGER := 2); -- error correction capability

	PORT (
		clk, rst : IN STD_LOGIC;
		data_in : IN STD_LOGIC_VECTOR(2 ** M - M * T - 1 - 1 DOWNTO 0); -- 239 bits for M=8, T=2
		data_valid : IN STD_LOGIC;
		code_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- 256 bits for M=8
		code_valid : OUT STD_LOGIC
	);
END ENTITY;

ARCHITECTURE RTL OF bch_encoder_256 IS
	CONSTANT N : INTEGER := 2 ** M - 1;
	CONSTANT R : INTEGER := M * T;

	CONSTANT message_length : INTEGER := 2 ** M - M * T - 1;
	CONSTANT K : INTEGER := message_length;
	CONSTANT dividend_length : INTEGER := message_length + R;
	-- Keep track of the original message bits
	TYPE message_array IS ARRAY (0 TO K) OF STD_LOGIC_VECTOR(dividend_length - 1 DOWNTO 0); -- 255 bits for M=8, T=2
	SIGNAL message_s : message_array := (OTHERS => (OTHERS => '0'));
	-- Keep track of the result of each round of modulo division
	TYPE result_array IS ARRAY (0 TO K) OF STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
	SIGNAL result_s : result_array := (OTHERS => (OTHERS => '0'));

	-- Parity chain through modulo rounds
	TYPE parity_array IS ARRAY (0 TO K) OF STD_LOGIC;
	SIGNAL parity_s : parity_array := (OTHERS => '0');

	-- TYPE next_parity_array 		IS ARRAY (1 TO K) OF STD_LOGIC;
	-- TYPE prev_result_array 		IS ARRAY (1 TO K) OF STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
	-- internal signals
	SIGNAL valid_output : STD_LOGIC_VECTOR(K + 1 DOWNTO 1) := (OTHERS => '0');
	-- SIGNAL result_of_modulo : STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0) := (OTHERS => '0');
	-- SIGNAL message_reg : STD_LOGIC_VECTOR(2 ** M - 2 DOWNTO 0) := (OTHERS => '0');

	-- constants
	CONSTANT gen : STD_LOGIC_VECTOR(R DOWNTO 0) := "10110111101100011"; -- generator polynomial for M=4, T=2

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
			result_s(0) <= (OTHERS => '0');
			parity_s(0) <= '0';
		ELSIF (rising_edge(clk)) THEN

			IF data_valid = '1' THEN
				message_s(0) <= data_in & (R - 1 DOWNTO 0 => '0'); -- append 16 zeros for the systematic division dividend
				result_s(0) <= data_in(message_length - 1 DOWNTO message_length - R); -- seed remainder with the top 16 message bits
				parity_s(0) <= xor_reduce(data_in(message_length -1 DOWNTO message_length - R))
				valid_output(1) <= '1';
			ELSE
				valid_output(1) <= '0';
			END IF;

			for i in 1 TO K LOOP
				valid_output(i + 1) <= valid_output(i);
			END LOOP;

			IF valid_output(K + 1) = '1' THEN
				code_out(255 DOWNTO 256 - message_length) <= message_s(K)(dividend_length - 1 DOWNTO R); -- output the original message bits
				code_out(R  DOWNTO 1) <= result_s(K);
				code_out(0) <= parity_s(K) XOR xor_reduce(result_s(K)); -- final parity = message parity XOR remainder parity
				code_valid <= '1';
			ELSE
				code_valid <= '0';
			END IF;
			
		END IF;
	END PROCESS;
	
	mod_rounds : FOR i IN 1 TO K GENERATE
		modulo_divider : ENTITY work.gf_mod_256
			PORT MAP(
				clk => clk,
				rst => rst,
				message_pass_in => message_s(i - 1),
				message_pass_out => message_s(i),
				new_data_bit => message_s(i - 1)(K - i),

				prev_result => result_s(i - 1),
				result => result_s(i),

				current_parity => parity_s(i - 1),
				next_parity => parity_s(i)
			);
	END GENERATE;

END ARCHITECTURE;