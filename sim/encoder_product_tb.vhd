LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;

ENTITY bch_encoder_tb_256 IS
END ENTITY bch_encoder_tb_256;

ARCHITECTURE Behavioral OF bch_encoder_tb_256 IS

    -- Component declaration for the Unit Under Test (UUT)
    COMPONENT encoder_product
        PORT (
            clk : IN STD_LOGIC;
            reset : IN STD_LOGIC;
            -- input
            row_valid : IN STD_LOGIC;
            row_in : IN STD_LOGIC_VECTOR(238 DOWNTO 0); -- 239 bits for M=8, T=2

            row_ready : OUT STD_LOGIC;
            -- output
            codeword_valid : OUT STD_LOGIC;
            codeword_out : OUT STD_LOGIC_VECTOR(255 DOWNTO 0); -- 256 bits for M=8
            block_done : OUT STD_LOGIC
        );
    END COMPONENT;

    -- Signals to connect to the UUT
    SIGNAL clk : STD_LOGIC := '0';
    SIGNAL rst : STD_LOGIC := '0';
    SIGNAL data_in : STD_LOGIC_VECTOR(238 DOWNTO 0) := (OTHERS => '0'); -- 239 bits for M=8, T=2
    SIGNAL data_valid : STD_LOGIC := '0';
    
    
    SIGNAL code_out : STD_LOGIC_VECTOR(255 DOWNTO 0) := (OTHERS => '0');
    SIGNAL code_valid : STD_LOGIC := '0';
    SIGNAL row_ready : STD_LOGIC := '0';
    SIGNAL block_done : STD_LOGIC := '0';

    file input_file : TEXT open READ_MODE is "TestFiles/testData.txt";
    file output_file : TEXT open WRITE_MODE is "TestFiles/encoderProductOutput.txt";

    constant CLK_PERIOD : TIME := 20 ns;

BEGIN
    -- Instantiate the Unit Under Test (UUT)
    uut : encoder_product
    PORT MAP(
        clk => clk,
        reset => rst,
        -- input
        row_valid => data_valid,
        row_in => data_in,

        row_ready => row_ready,
        -- output
        codeword_valid => code_valid,
        codeword_out => code_out,
        block_done => block_done
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
            WAIT FOR CLK_PERIOD * 2.5;

            rom_init_complete := true;
            readline(input_file, line_in); -- ignore the first line (header)
            --row_ready <= '1'; -- indicate ready to receive data
            while not endfile(input_file) loop
                if row_ready = '1' then -- only apply new input when not busy
                    readline(input_file, line_in);            
                    read(line_in, vec);
                    data_valid <= '1';
                    data_in <= vec;
                end if;
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

END ARCHITECTURE Behavioral;