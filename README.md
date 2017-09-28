# Extract business formations from SOTS DB

After running the extract_formations commands with the cli do the following:

1. Copy the extracted data into a subfolder in an `./extracts` directory.
2. Run the `processs-sql-extracts.R` command, setting the paths accordingly
3. Run the `convert_to_json.py` file, setting paths accordingly.


The `convert_to_json.py` command can be executed as a command line script as follows:

`python convert_to_json.py -i [INPUT DIR WHERE R OUTPUT DATA TO] -o [OUTPUT DIR WHERE YOU WANT IT TO GO] -c`

Replace paths accordingly. If you omit the `-c` flag at the end, the processing will be a "dry run" and no data will be written out. The input directory should point to the location of the
'types' subdirectory, as output by the R script.

All of the directories need to already exist.

Finally, copy the final data into the '/dist/data/' directory in the 'sots-formations-app' folder and push '/dist' to s3.
