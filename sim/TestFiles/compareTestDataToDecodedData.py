import pathlib


testData = open(pathlib.Path("sim","TestFiles","testData.txt"), "r")
decoderOut = open(pathlib.Path("sim","TestFiles","decoderOutput.txt"), "r")
testData.readline() # skip first line
#line = fileR.readline()
print("Testing begins")
lineTest = testData.readline().strip()
lineDeco = decoderOut.readline().strip()
i = 1
while lineTest != "" and lineDeco != "":
    if lineTest != lineDeco:
        print("Error on codeword: "+str(i))
    
    lineTest = testData.readline().strip()
    lineDeco = decoderOut.readline().strip()
    i += 1
print("Testing done")

testData.close()
decoderOut.close()