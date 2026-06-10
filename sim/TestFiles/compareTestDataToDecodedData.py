import pathlib


testData = open(pathlib.Path("sim","TestFiles","testData.txt"), "r")
decoderOut = open(pathlib.Path("sim","TestFiles","decoderOutput.txt"), "r")
testData.readline() # skip first line
#line = fileR.readline()
print("Testing begins")
lineTest = testData.readline().strip()
lineDeco = decoderOut.readline().strip()
i = 1
incorrect = 0
while lineTest != "" and lineDeco != "":
    if lineTest != lineDeco:
        print("Error on codeword: "+str(i))
        incorrect += 1
    
    lineTest = testData.readline().strip()
    lineDeco = decoderOut.readline().strip()
    i += 1
print("\nTesting done on "+ str(i-1) +" lines" )
print(str(incorrect) + " errors, which is roughly "+ str(round((incorrect/(i-1))*100))+"%"  )

testData.close()
decoderOut.close()