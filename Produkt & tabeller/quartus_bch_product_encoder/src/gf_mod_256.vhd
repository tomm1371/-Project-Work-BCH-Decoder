LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

ENTITY gf_mod_256 IS
  GENERIC (
    R : INTEGER := 16
  );
  PORT (
    clk              : IN  STD_LOGIC;
    reset            : IN  STD_LOGIC;
    prev_result      : IN  STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
    new_data_bit     : IN  STD_LOGIC;
    message_pass_in  : IN  STD_LOGIC_VECTOR(254 DOWNTO 0);
    gen              : IN  STD_LOGIC_VECTOR(R DOWNTO 0);
    result           : OUT STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
    message_pass_out : OUT STD_LOGIC_VECTOR(254 DOWNTO 0)
  );
END ENTITY gf_mod_256;

ARCHITECTURE rtl OF gf_mod_256 IS
BEGIN
  PROCESS (clk, reset)
    VARIABLE shifted_result : STD_LOGIC_VECTOR(R - 1 DOWNTO 0);
  BEGIN
    IF reset = '1' THEN
      result <= (OTHERS => '0');
      message_pass_out <= (OTHERS => '0');
    ELSIF rising_edge(clk) THEN
      shifted_result := prev_result(R - 2 DOWNTO 0) & new_data_bit;

      -- Polynomial long division over GF(2):
      -- if the leading term is present, subtract the monic generator.
      -- In GF(2), subtraction is XOR. gen(R) cancels the leading term,
      -- so only gen(R-1 downto 0) has to be stored in the remainder.
      IF prev_result(R - 1) = '1' THEN
        result <= shifted_result XOR gen(R - 1 DOWNTO 0);
      ELSE
        result <= shifted_result;
      END IF;

      message_pass_out <= message_pass_in;
    END IF;
  END PROCESS;
END ARCHITECTURE rtl;
