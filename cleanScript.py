input_file = 'strain_gauges.lua'

#duplicate file
output_file = input_file.replace('.lua', '_cleaned.lua')

#open both
with open(input_file, 'r') as infile, open(output_file, 'w') as outfile:
    #loop through lines
    for line in infile:
        #take out comments
        splitLine = line.split('--')
        cleaned_line = splitLine[0]

        #add line if it isnt blank, and if it isnt a print statement
        if cleaned_line != "" and not cleaned_line.isspace() and "print(" not in cleaned_line:# and "print(" not in cleaned_line:
            if len(splitLine) > 1:
                outfile.write(cleaned_line + "\n")
            else:
                outfile.write(cleaned_line)

print("Cleaned")
