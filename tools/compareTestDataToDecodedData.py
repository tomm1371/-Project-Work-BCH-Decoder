import pathlib


testData = open(pathlib.Path("sim","TestFiles","testData.txt"), "r")
decoderOut = open(pathlib.Path("sim","TestFiles","trimmedDecodedOutput.txt"), "r")
errorFile = open(pathlib.Path("sim","TestFiles","error_pos.txt"), "r")
#testData.readline() # skip first line
lineE = errorFile.readline()
print("Testing begins")
lineTest = testData.readline().strip()
lineDeco = decoderOut.readline().strip()
errorPos = errorFile.readline().strip().split(" ")
i = 1
incorrect = 0
while lineTest != "" and lineDeco != "":
    if lineTest != lineDeco:
        diff = int(lineTest, 2) ^ int(lineDeco, 2)
        print("Error on codeword: "+(str(i).zfill(3))+"  difference: " + str((hex(diff)[2:])).zfill(64) +  " ("+ str(bin(diff)[2:].count("1")) +" bits)")
        #print("                Errors in codeword: "+ (hex(2**int(errorPos[0],16) ^ 2**int(errorPos[1], 16))[2:]).zfill(64) + " "+str(errorPos)+"\n")
        incorrect += 1
    
    lineTest = testData.readline().strip()
    lineDeco = decoderOut.readline().strip()
    errorPos = errorFile.readline().strip().split(" ")
    i += 1
print("\nTesting done on "+ str(i-1) +" lines" )
print(str(incorrect) + " errors, which is roughly "+ str(round((incorrect/(i-1))*100))+"%"  )

testData.close()
decoderOut.close()
errorFile.close()