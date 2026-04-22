M=4
t=2 #number of errors to correct
g = int("10011", 2)
genPoly = int('111010001', 2) #the generator polynomial

def generateFile(LUTname:str, index:list[int], value:list[int], bitLengthOfIndex = M, bitLengthOfValues = M, entriesPerLine:int = 4):
    if len(index) != len(value):
        print("index and value must have equal length")
        
    header = "library IEEE;\nuse IEEE.std_logic_1164.all;\nuse IEEE.numeric_std.all;\n\n"
    topPart = f"""
entity {LUTname} is
port(address  : in  std_logic_vector({bitLengthOfIndex-1} DOWNTO 0); -- memory address
         out  : out std_logic_vector({bitLengthOfValues -1} DOWNTO 0); -- value
        );
end entity {LUTname};

architecture {LUTname}_arch of {LUTname} is

type LUT_type is array (0 to {len(index)-1}) of std_logic_vector({bitLengthOfValues -1} DOWNTO 0);
signal rom_out : std_logic_vector({M-1} DOWNTO 0);

constant LUT : ROM_type := (\n"""
    LUTstr = ""
    for i in range(len(index)):
        
        
        binStr = bin(value[i])[2:]
        binStr = (bitLengthOfValues -len(binStr))*"0" + binStr
        
        # ex 000 => "1010101011",
        LUTstr += f'{index[i]:03d} => "{binStr}", '
        
        if (i % entriesPerLine == entriesPerLine -1):
            LUTstr += "\n"
            
    LUTstr = LUTstr.strip()[:-1] + "\n"    
    
    end = f"""                            
                            others => "0"
                            );
begin
    out <= LUT(to_integer(unsigned(address)));
    
end architecture {LUTname}_arch;
    """
    totalString = header + topPart + LUTstr + end
    file = open(LUTname+".vhd", 'w')
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
    return a*b
    aShift = a
    sum = 0
    for i in range (a.bit_length()):
        #print(i, bin(sum), bin (aShift))
        if aShift % 2 == 1:
            sum = sum ^ (b<<i)
        aShift = aShift >> 1
    return sum    
     
def expGF2(a,b,mod):
    if b == 0 : return 1
    sum = a
    for i in range (b-1):
        sum = modGF2(mult(sum,a), mod)
    return sum
    
def logTabel(lengthMultiplier =  1):
    tabel = [0]
    a=2
    for i in range(((2**M)-1)*lengthMultiplier):
        tabel.append(expGF2(a,i,g)) 
    return tabel 


#generateFile("log_tabel", range(((2**M))), logTabel())
#generateFile("inv_log_tabel", logTabel(), range(((2**M))))