LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;

ENTITY bch_encoder_tb IS
END ENTITY bch_encoder_tb;

ARCHITECTURE Behavioral OF bch_encoder_tb IS

    -- Component declaration for the Unit Under Test (UUT)
    COMPONENT bch_encoder
        GENERIC (
            M : INTEGER := 4; -- message length
            T : INTEGER := 2 -- error correction capability
        );
        PORT (
            clk : IN STD_LOGIC;
            rst : IN STD_LOGIC;
            data_in : IN STD_LOGIC_VECTOR(2 ** M - M * T - 1 - 1 DOWNTO 0); -- 7 bits for M=4, T=2
            data_valid : IN STD_LOGIC;
            code_out : OUT STD_LOGIC_VECTOR(2 ** M - 1 DOWNTO 0); -- 15 bits for M=4
            code_valid : OUT STD_LOGIC
        );
    END COMPONENT;

    -- Signals to connect to the UUT
    SIGNAL clk : STD_LOGIC := '0';
    SIGNAL rst : STD_LOGIC := '0';
    SIGNAL data_in : STD_LOGIC_VECTOR(6 DOWNTO 0) := (OTHERS => '0'); -- 7 bits for M=4, T=2
    SIGNAL data_valid : STD_LOGIC := '0';
    SIGNAL code_out : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL code_valid : STD_LOGIC;
BEGIN
    -- Instantiate the Unit Under Test (UUT)
    uut : bch_encoder
    PORT MAP(
        clk => clk,
        rst => rst,
        data_in => data_in,
        data_valid => data_valid,
        code_out => code_out,
        code_valid => code_valid
    );

    -- Clock generation
    clk_process : PROCESS
    BEGIN
        WHILE true LOOP
            clk <= '0';
            WAIT FOR 10 ns;
            clk <= '1';
            WAIT FOR 10 ns;
        END LOOP;
    END PROCESS;

    -- Stimulus process to apply test vectors
    stimulus_process : PROCESS
    BEGIN
        -- Reset the UUT
        rst <= '1';
        WAIT FOR 20 ns;
        rst <= '0';
        WAIT FOR 20 ns;

        -- Apply test vector 1
        data_in <= "0101010"; -- Example input data (7 bits)
        data_valid <= '1';
        WAIT FOR 20 ns;
        data_valid <= '0';
        WAIT FOR 100 ns;

        -- Apply test vector 2
        data_in <= "0011100"; -- Another example input data (7 bits)
        data_valid <= '1';
        WAIT FOR 20 ns;
        data_valid <= '0';
        WAIT FOR 100 ns;

        -- End of simulation
        WAIT;
    END PROCESS;
END ARCHITECTURE Behavioral;