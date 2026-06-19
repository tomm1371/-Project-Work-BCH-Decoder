LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY DaBomb_encoder_product IS
  GENERIC (
    constant rows : NATURAL := 239;
    constant columns : NATURAL := 256
  );
  PORT (
        clk : IN STD_LOGIC;
        reset : IN STD_LOGIC;

        -- In this version, the module can accept one 239-bit row per clock whenever row_valid & row_ready = 1.
        -- Therefore, all input will be treated as rows, hence the naming convention.
        row_in : IN STD_LOGIC_VECTOR(rows-1 DOWNTO 0); -- actual 239 bits.
        row_valid : IN STD_LOGIC; -- is 1 when row_in contains one valid 239-bit data row.

        row_ready : OUT STD_LOGIC; -- This is set to 1 when the module is ready to receive data.

        codeword_out : OUT STD_LOGIC_VECTOR(columns-1 DOWNTO 0); -- actual 256 bits output codeword.
        codeword_valid : OUT STD_LOGIC -- is 1 when codeword_out contains a valid encoded column codeword.
    );
END ENTITY DaBomb_encoder_product;

architecture encoder_arch OF DaBomb_encoder_product IS
    --constant rows : NATURAL := 239;
    --constant columns : NATURAL := 256;

    constant FUNC_CLK_DELAY: NATURAL := 1;

    component encoder IS
	PORT (
		clk, rst : IN STD_LOGIC;
		data_in : IN STD_LOGIC_VECTOR(238 DOWNTO 0); -- 239 bits for M=8, T=2
		data_valid : IN STD_LOGIC;
		codeword_out : OUT STD_LOGIC_VECTOR(255 DOWNTO 0); -- 256 bits for M=8
		codeword_valid : OUT STD_LOGIC
	);
    END component;

        type main_array_t is array (rows-1 DOWNTO 0) OF STD_LOGIC_VECTOR(columns-1 DOWNTO 0);
    SIGNAL main_array : main_array_t := (OTHERS => (OTHERS => '0'));

    SIGNAL DATA_IN_FUNC : STD_LOGIC_VECTOR(rows-1 DOWNTO 0);
    SIGNAL DATA_VALID_FUNC : STD_LOGIC;
    
    SIGNAL CODE_OUT_FUNC : STD_LOGIC_VECTOR(columns-1 DOWNTO 0);
    SIGNAL CODE_VALID_FUNC : STD_LOGIC;

    SIGNAL ROWS_RECEIVED : UNSIGNED(8-1 downto 0) := TO_UNSIGNED(0,8);
    SIGNAL CURRENT_ROW_TO_WRITE : INTEGER range 0 to rows     := 0;
    SIGNAL CURRENT_COL_TO_READ : INTEGER  range 0 to columns  := 0;

    TYPE state IS (
		WAITING_FOR_FIRST_ROW,
        GIVE_DATA_PLZ,
        NO_MORE_ROWS,
        DOING_COLUMNS,
        CLEARING_COLUMN_BUFFER
	);

    SIGNAL current_state : state := WAITING_FOR_FIRST_ROW;

    BEGIN

    FUNC: entity work.encoder
		PORT MAP(
            clk => clk, rst => reset,
            data_in => DATA_IN_FUNC,
            data_valid => DATA_VALID_FUNC,
            code_out =>CODE_OUT_FUNC,
            code_valid => CODE_VALID_FUNC
		);


    PROCESS (clk, reset)
    BEGIN
        IF (reset = '1') then
            main_array <= (OTHERS => (OTHERS => '0'));
            current_state <= WAITING_FOR_FIRST_ROW;
            row_ready <= '0';

        ELSIF (rising_edge(clk)) THEN
            IF (current_state = WAITING_FOR_FIRST_ROW) THEN
                CURRENT_ROW_TO_WRITE <= 0;
                CURRENT_COL_TO_READ <= 0;
                row_ready <= '1';
                DATA_VALID_FUNC <= row_valid;
                DATA_IN_FUNC <= row_in;

                if (row_valid = '1') then
                    ROWS_RECEIVED <=  TO_UNSIGNED(1, 8);
                    current_state <= GIVE_DATA_PLZ;

                else --data_valid = '0' then
                    ROWS_RECEIVED <= TO_UNSIGNED(0, 8);
                    current_state <= WAITING_FOR_FIRST_ROW;
                end if;
            
            ELSIF (current_state = GIVE_DATA_PLZ)  THEN 
                row_ready <= '1';
                DATA_VALID_FUNC <= '1';
                ROWS_RECEIVED <= ROWS_RECEIVED + TO_UNSIGNED(1,8);
                        
                if (row_valid = '1') then
                    DATA_IN_FUNC <= row_in;
                else --data_valid = '0' then
                    DATA_IN_FUNC <= (OTHERS => '0');
                end if;
                
                if (ROWS_RECEIVED = (rows-1)) then
                    current_state <= NO_MORE_ROWS;
                else 
                    current_state <= GIVE_DATA_PLZ;
                end if;

            ELSIF (current_state = NO_MORE_ROWS)  THEN
                row_ready <= '0'; 
                DATA_VALID_FUNC <= '0';
                DATA_IN_FUNC <= (OTHERS => '0');

                if (CODE_VALID_FUNC = '0') then
                    current_state <= DOING_COLUMNS;
                else 
                    current_state <= NO_MORE_ROWS;
                end if;

            ELSIF (current_state = DOING_COLUMNS)  THEN 
                row_ready <= '0';
                DATA_VALID_FUNC <= '1';
                CURRENT_COL_TO_READ <= CURRENT_COL_TO_READ + 1;
                FOR row in 0 TO rows-1 LOOP
                    DATA_IN_FUNC(row) <= main_array(row)(CURRENT_COL_TO_READ);
                end LOOP;

                if (CURRENT_COL_TO_READ = columns-1) then
                    current_state <= CLEARING_COLUMN_BUFFER;
                else
                    current_state <= DOING_COLUMNS;
                end if;


            ELSE --(current_state = CLEARING_COLUMN_BUFFER)  THEN 
                row_ready <= '0';
                DATA_VALID_FUNC <= '0';
                DATA_IN_FUNC <= (OTHERS => '0');

                if (CODE_VALID_FUNC = '0') then 
                    current_state <= WAITING_FOR_FIRST_ROW;
                else
                    current_state <= CLEARING_COLUMN_BUFFER;
                end if;

            END IF;
            
            --output of function
            IF (CODE_VALID_FUNC = '1') then 
                IF (current_state = GIVE_DATA_PLZ OR current_state = NO_MORE_ROWS) then
                    codeword_valid <= '0';
                    codeword_out <= (OTHERS => '0'); 
                    CURRENT_ROW_TO_WRITE <= CURRENT_ROW_TO_WRITE + 1;
                    main_array(CURRENT_ROW_TO_WRITE) <= CODE_OUT_FUNC;
                

                elsif (current_state = DOING_COLUMNS OR current_state = CLEARING_COLUMN_BUFFER) then
                    codeword_valid <= '1';
                    codeword_out <= CODE_OUT_FUNC;
                    
                end if;
            else
                codeword_valid <= '0';  
                codeword_out <= (OTHERS => '0'); 
            end if;

        end if;--main
    end PROCESS;

end architecture encoder_arch;