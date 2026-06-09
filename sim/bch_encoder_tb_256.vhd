LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;

ENTITY bch_encoder_tb_256 IS
END ENTITY bch_encoder_tb_256;

ARCHITECTURE Behavioral OF bch_encoder_tb_256 IS

    -- Component declaration for the Unit Under Test (UUT)
    COMPONENT bch_encoder_256
        PORT (
            clk : IN STD_LOGIC;
            rst : IN STD_LOGIC;
            data_in : IN STD_LOGIC_VECTOR(238 DOWNTO 0); -- 239 bits for M=8, T=2
            data_valid : IN STD_LOGIC;
            code_out : OUT STD_LOGIC_VECTOR(255 DOWNTO 0); -- 256 bits for M=8
            code_valid : OUT STD_LOGIC
        );
    END COMPONENT;

    -- Signals to connect to the UUT
    SIGNAL clk : STD_LOGIC := '0';
    SIGNAL rst : STD_LOGIC := '0';
    SIGNAL data_in : STD_LOGIC_VECTOR(238 DOWNTO 0) := (OTHERS => '0'); -- 239 bits for M=8, T=2
    SIGNAL data_valid : STD_LOGIC := '0';
    SIGNAL code_out : STD_LOGIC_VECTOR(255 DOWNTO 0);
    SIGNAL code_valid : STD_LOGIC;

    file input_file : TEXT open READ_MODE is "TestFiles/testData.txt";
    file output_file : TEXT open WRITE_MODE is "TestFiles/encoderOutput.txt";

    constant CLK_PERIOD : TIME := 20 ns;

BEGIN
    -- Instantiate the Unit Under Test (UUT)
    uut : bch_encoder_256
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
            WAIT FOR CLK_PERIOD / 2;
            clk <= '1';
            WAIT FOR CLK_PERIOD / 2;
        END LOOP;
    END PROCESS;

    -- Stimulus process to apply test vectors
    stimulus_process : PROCESS
        variable line_in : line;
        variable vec : std_logic_vector(238 DOWNTO 0);
        variable rom_init_complete : boolean := false;
    BEGIN
        -- Reset the UUT
        if (not rom_init_complete) then
            rst <= '1';
            WAIT FOR CLK_PERIOD * 2;
            rst <= '0';
            WAIT FOR CLK_PERIOD * 2;

            rom_init_complete := true;
            readline(input_file, line_in); -- ignore the first line (header)
            while not endfile(input_file) loop
                readline(input_file, line_in);            
                read(line_in, vec);
                data_valid <= '1';
                data_in <= vec;
                WAIT FOR CLK_PERIOD;
            end loop;
            data_valid <= '0';
        end if;
    WAIT;
    END PROCESS;

    capture_output : PROCESS
        variable output_line : line;
    BEGIN
        WAIT UNTIL RISING_EDGE(clk);
        if code_valid = '1' then
            write(output_line, code_out);
            writeline(output_file, output_line);
        end if;
    END PROCESS;

        -- Apply test vector 1
        /* data_in <= (0 => '1', OTHERS => '0'); -- Example input data (239 bits)
        data_valid <= '1';
        WAIT FOR 20 ns;
        data_valid <= '0';
        WAIT FOR 100 ns;

        -- Apply test vector 2
        data_in <= (238 => '1', OTHERS => '0'); -- Another example input data (239 bits)
        data_valid <= '1';
        WAIT FOR 20 ns;
        data_valid <= '0';
        WAIT FOR 100 ns; */

        -- End of simulation
        --WAIT;
    --END PROCESS;
END ARCHITECTURE Behavioral;