# Extract business formations from SOTS DB

### Prerequisites

1. Executed the local deployment commands outlined in the [ctdata-sots-search](https://github.com/CT-Data-Collaborative/ctdata-sots-search) and [ctdata-sots-cli](https://github.com/CT-Data-Collaborative/ctdata-sots-cli) repos. 

2. From this you should have a `monthly_rebuilds` folder, make sure you have a `/monthly_rebuilds/formations/9_2017` (where 9_2017 indicates the month folder that corresponds to your latest data download) folder set up before you launch these commands

3. Clone two repos to your local machine:

```git clone git@github.com:CT-Data-Collaborative/ctdata-sots-formations-data-processing.git```

```git clone git@github.com:CT-Data-Collaborative/ctdata-sots-formations.git```

### Instructions

1. cd to `monthly_rebuilds` folder, run following extract_formations commands:

```sots extract_formations --dbhost 0.0.0.0 --dbport 5432 --dbuser sots --dbpass [password] -q Address -o formations/9_2017/addresses.csv```


```sots extract_formations --dbhost 0.0.0.0 --dbport 5432 --dbuser sots --dbpass [password] -q Formations -o formations/9_2017/formations.csv```

--dbpass [password] replace with your configured database password

2. After running the extract_formations commands, do the following:

- Create three sub-folders in your local `ctdata-sots-formations-data-processing` folder structure (`./extracts`, `./final`, and `./json`)

- In the `./extracts` folder, create a sub-folder with today's date (i.e. `./09_28_2017`)

- In the `./final` folder, create a sub-folder with today's date (i.e. `./09_28_2017`) and within the date folder, create another folder called `./types`

- Copy the extracted data (addresses.csv and formations.csv) into the `./09_28_2017` sub-folder in the `./extracts` directory.

- Run the `processs-sql-extracts.R` command, setting the paths accordingly

- Run the `convert_to_json.py` file, setting paths accordingly


3. The `convert_to_json.py` command can be executed as a command line script as follows:

`python2 convert_to_json.py -i [INPUT DIR WHERE R OUTPUT DATA TO] -o [OUTPUT DIR WHERE YOU WANT IT TO GO] -c`

Replace paths accordingly. If you omit the `-c` flag at the end, the processing will be a "dry run" and no data will be written out. The input directory should point to the location of the `./types` subdirectory of the `./final` folder, as output by the R script.

For example: `python2 convert_to_json.py -i final/09_28_2017/types -o json/09_28_2017/ -c`

All of the directories need to already exist.

4. Go to the [ctadat-sots-formations README](https://github.com/CT-Data-Collaborative/ctdata-sots-formations/blob/master/README.md) for the remaining steps 

