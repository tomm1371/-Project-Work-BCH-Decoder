LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY bch_encoder_256 IS
  GENERIC (
    M : INTEGER := 8;
    T : INTEGER := 2
  );
  PORT (
    clk        : IN  STD_LOGIC;
    reset      : IN  STD_LOGIC;
    data_valid : IN  STD_LOGIC;
    data_in    : IN  STD_LOGIC_VECTOR(2 ** M - M * T - 2 DOWNTO 0);
    code_valid : OUT STD_LOGIC;
    code_out   : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0)
  );
END ENTITY bch_encoder_256;

ARCHITECTURE rtl OF bch_encoder_256 IS
  CONSTANT N              : INTEGER := 2 ** M - 1;
  CONSTANT R              : INTEGER := M * T;
  CONSTANT MESSAGE_LENGTH : INTEGER := N - R;
  CONSTANT K              : INTEGER := MESSAGE_LENGTH;
  CONSTANT DIVIDEND_LEN   : INTEGER := MESSAGE_LENGTH + R;

  -- Generator polynomial for the binary BCH(255,239) component code.
  -- Degree 16 means 17 coefficients. The extended parity bit is added
  -- separately to obtain BCH(256,239).
  CONSTANT GEN_POLY : STD_LOGIC_VECTOR(R DOWNTO 0) := "10110111101100011";

  TYPE message_array IS ARRAY (0 TO K) OF STD_LOGIC_VECTOR(DIVIDEND_LEN - 1 DOWNTO 0);
  TYPE result_array IS ARRAY (0 TO K) OF STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
  TYPE parity_array IS ARRAY (0 TO K) OF STD_LOGIC;

  SIGNAL message_s     : message_array := (OTHERS => (OTHERS => '0'));
  SIGNAL result_s      : result_array := (OTHERS => (OTHERS => '0'));
  SIGNAL parity_s      : parity_array := (OTHERS => '0');
  SIGNAL valid_pipeline : STD_LOGIC_VECTOR(K + 1 DOWNTO 1) := (OTHERS => '0');

  FUNCTION xor_reduce(vec : STD_LOGIC_VECTOR) RETURN STD_LOGIC IS
    VARIABLE acc : STD_LOGIC := '0';
  BEGIN
    FOR i IN vec'RANGE LOOP
      acc := acc XOR vec(i);
    END LOOP;
    RETURN acc;
  END FUNCTION;
BEGIN
  PROCESS (clk, reset)
  BEGIN
    IF reset = '1' THEN
      message_s(0) <= (OTHERS => '0');
      result_s(0) <= (OTHERS => '0');
      parity_s(0) <= '0';
      valid_pipeline <= (OTHERS => '0');
      code_out <= (OTHERS => '0');
      code_valid <= '0';
    ELSIF rising_edge(clk) THEN
      code_valid <= '0';
      valid_pipeline(1) <= data_valid;

      FOR i IN 1 TO K LOOP
        valid_pipeline(i + 1) <= valid_pipeline(i);
      END LOOP;

      IF data_valid = '1' THEN
        -- Systematic encoding: divide data*x^R by GEN_POLY.
        message_s(0) <= data_in & (R - 1 DOWNTO 0 => '0');

        -- Preload the first R dividend bits. The following K rounds stream
        -- in the remaining MESSAGE_LENGTH-R data bits and the R appended zeros.
        result_s(0) <= data_in(MESSAGE_LENGTH - 1 DOWNTO MESSAGE_LENGTH - R);
        parity_s(0) <= xor_reduce(data_in(MESSAGE_LENGTH - 1 DOWNTO MESSAGE_LENGTH - R));
      ELSE
        message_s(0) <= (OTHERS => '0');
        result_s(0) <= (OTHERS => '0');
        parity_s(0) <= '0';
      END IF;

      IF valid_pipeline(K + 1) = '1' THEN
        code_out(2 ** M - 1 DOWNTO 2 ** M - MESSAGE_LENGTH) <= message_s(K)(DIVIDEND_LEN - 1 DOWNTO R);
        code_out(R DOWNTO 1) <= result_s(K);
        code_out(0) <= parity_s(K) XOR xor_reduce(result_s(K));
        code_valid <= '1';
      END IF;
    END IF;
  END PROCESS;

  mod_rounds : FOR i IN 1 TO K GENERATE
    modulo_divider : ENTITY work.gf_mod_256
      GENERIC MAP (
        R => R
      )
      PORT MAP (
        clk              => clk,
        reset            => reset,
        prev_result      => result_s(i - 1),
        new_data_bit     => message_s(i - 1)(K - i),
        message_pass_in  => message_s(i - 1),
        gen              => GEN_POLY,
        result           => result_s(i),
        message_pass_out => message_s(i)
      );

    PROCESS (clk, reset)
    BEGIN
      IF reset = '1' THEN
        parity_s(i) <= '0';
      ELSIF rising_edge(clk) THEN
        parity_s(i) <= parity_s(i - 1) XOR message_s(i - 1)(K - i);
      END IF;
    END PROCESS;
  END GENERATE;
END ARCHITECTURE rtl;
