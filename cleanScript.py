input_file = 'strain_gauges_nomux.lua'

#duplicate file
output_file = input_file.replace('.lua', '_cleaned.lua')

#open both
with open(input_file, 'r') as infile, open(output_file, 'w') as outfile:
    #loop through lines
    for line in infile:
        #take out comments and ANY whitespace
        cleaned_line = line.split('--')[0]

        #add line if it isnt blank, and if it isnt a print statement
        if cleaned_line != "" and "print(" not in cleaned_line:
            outfile.write(cleaned_line + "\n")
