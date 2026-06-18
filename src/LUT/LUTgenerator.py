import pathlib
M=8
t=2 #number of errors to correct
#g = int("10011", 2)
genPoly = int("10110111101100011", 2)
g = int("100011101",2)



#genPoly = int('111010001', 2) #the generator polynomial

#signal rom_out : std_logic_vector({M-1} DOWNTO 0);

def generateFile(LUTname:str, index:list[int], value:list[int], bitLengthOfIndex = M, bitLengthOfValues = M, entriesPerLine:int = 4):
    if len(index) != len(value):
        print("index and value must have equal length")
        
    header = "library IEEE;\nuse IEEE.std_logic_1164.all;\nuse IEEE.numeric_std.all;\n\n"
    topPart = f"""
entity {LUTname} is
port(address  : in  std_logic_vector({bitLengthOfIndex-1} DOWNTO 0); -- memory address
    contents  : out std_logic_vector({bitLengthOfValues -1} DOWNTO 0); -- value
    clk, rst  : in  std_logic
        );
end entity {LUTname};

architecture {LUTname}_arch of {LUTname} is

type LUT_type is array (0 to {2**bitLengthOfIndex -1}) of std_logic_vector({bitLengthOfValues -1} DOWNTO 0);

constant LUT : LUT_type := (\n"""
    LUTstr = ""
    for i in range(len(index)):
        
        
        binStr = bin(value[i])[2:]
        binStr = (bitLengthOfValues -len(binStr))*"0" + binStr
        
        # ex 000 => "1010101011",
        LUTstr += f'{index[i]:03d} => "{binStr}", '
        
        if (i % entriesPerLine == entriesPerLine -1):
            LUTstr += "\n"
            
    LUTstr = LUTstr.strip() + "\n"   #.[-1:]  
    
    end = f"""                            
                            others => (OTHERS => '0')
                            );
begin
    PROCESS (clk, rst)
    BEGIN
        IF rst = '1' THEN
            contents <= (OTHERS => '0');
        ELSIF (rising_edge(clk)) THEN 
            contents <= LUT(to_integer(unsigned(address)));
        END IF;
    END PROCESS;
    
end architecture {LUTname}_arch;

--	Component {LUTname} is
--		port(address  : in  std_logic_vector({bitLengthOfIndex-1} DOWNTO 0); -- memory address
--			  contents  : out std_logic_vector({bitLengthOfValues -1} DOWNTO 0); -- value
--			clk, rst  : in  std_logic 
--			);
--	end Component {LUTname};

--	???_tabel_for_step? : entity {LUTname}
--		PORT MAP(
--			address => ???,  
--			contents => ???, 
--			clk => clk, rst => rst 
--		);
    """
    totalString = header + topPart + LUTstr + end
    file = open(pathlib.Path("src", "LUT", LUTname+".vhd"), 'w')
    file.write(totalString)
    file.close()
    return 
    
def modGF2(a:int,b:int):
    while a >= b:
        a = a^(b<<(a.bit_length()-b.bit_length()))
    if (a^b).bit_length() < a.bit_length():
        return a^b
    else:
        return a 
    
def divGF2(a:int,b:int):
    result = 0
    while a >= b:
        result = result ^ 1<<(a.bit_length()-b.bit_length())
        a = a^(b<<(a.bit_length()-b.bit_length()))
        
    if a == 0:
        return result
    else:
        return "gik ikke op :("  
     
def mult(a:int, b:int):
    
    aShift = a
    sum = 0
    for i in range (a.bit_length()):
        #print(i, bin(sum), bin (aShift))
        if aShift % 2 == 1:
            sum = sum ^ (b<<i)
        aShift = aShift >> 1
        
    return sum  # \neq a*b
     
def expGF2(a,b,mod):
    if b == 0 : return 1
    sum = a
    for i in range (b-1):
        sum = modGF2(mult(sum,a), mod)
    return sum
    
def logTabelWithZero(exponent = 1, lengthMultiplier =  1, lengthAdder = 0):
    tabel = [0]
    a=2
    for i in range(((2**M)-1)*lengthMultiplier + lengthAdder):
        tabel.append(expGF2(a,i*exponent,g)) 
    return tabel 

def logTabel(exponent = 1, lengthMultiplier =  1):
    tabel = []
    a=2
    for i in range(((2**M)-1)*lengthMultiplier):
        tabel.append(expGF2(a,i*exponent,g)) 
    return tabel

def tabelOverA(GFtabel, poly = g, justRoots = False):
    tabelOverA_ = []

    for A in GFtabel:
        rootList = []
        
        for y in GFtabel:
            sum = expGF2(y,2,poly) ^ y ^ A
            
            if sum == 0: #is root
                yStr = bin(y)[2:]#string of 0's & 1's
                rootList.append(yStr.zfill(M)) #add leading 0's so length is always correct
        
        #print(rootList)
        if justRoots: 
            tabelOverA_.append(rootList)      
        else:
            if len(rootList) == 2: 
                tabelOverA_.append((rootList[0]+rootList[1]).zfill(M*t))
            else:
                tabelOverA_.append("0"*M*t)
            
    if justRoots:
        return tabelOverA_  
    
    intTabel = []
    
    for i in tabelOverA_:
        intTabel.append(int(i,2))
    return intTabel

def justRootsToLogRoots(tabelOverA_):
    returnTabel = []
    lT = logTabel()
    
    for i in tabelOverA_:
        if len(i) == 2:
            returnTabel.append(int(
                (bin(lT.index(int(i[0],2)))[2:]).zfill(8)+
                (bin(lT.index(int(i[1],2)))[2:]).zfill(8)
                ,2))
        else:
            returnTabel.append(int("FFFF",16))
    
    return returnTabel

#for sanity checking
def rootReformatter(rootList):
    retunList = []
    lT = logTabel()
    for pair in rootList:
        if len(pair) != 2 :
            retunList.append(pair)
            continue
        r1, r2 = lT.index(int(pair[0], 2)), lT.index(int(pair[1], 2))
        diff = abs(r1-r2)
        retunList.append((min(r1,r2), diff))
    return retunList

def printLines(iterable):
    for index in iterable:
        print(index)
        

#used for finding log_A and errors
generateFile("a_to_log_a_tabel", logTabel(), range((2**M)-1), entriesPerLine=8) #inv_log_tabel
generateFile("a_to_a_pow3_tabel", logTabelWithZero(exponent=1), logTabelWithZero(exponent=3))
generateFile("log_A_to_log_rootsOfA_tabel", 
             range(0,(2**M-1)), 
             justRootsToLogRoots(tabelOverA(logTabel(), g, justRoots=True)), 
             bitLengthOfValues = M*t)

#partly used for syndrome calculation
generateFile("log_a_to_a_tabel", range((2**M)-1), logTabel(),  entriesPerLine=8)
generateFile("log_a_to_a_pow3_tabel", range((2**M)-1), logTabel(exponent=3), entriesPerLine=8)   

#print(logTabel())
#printLines(tabelOverA(logTabel(), g, justRoots=True))