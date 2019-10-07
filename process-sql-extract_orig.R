library(data.table)
library(dplyr)
library(tidyr)

month <- '09_2019'
formations_filename <- 'formations.csv'
address_filename <- 'addresses.csv'
starts_filename <- 'starts.csv'
stops_filename <- 'stops.csv'
raw_path <- paste('extracts/', month, '/', sep='') 

formations_path <- paste(raw_path, formations_filename, sep='')
address_path <- paste(raw_path, address_filename, sep='')
starts_path <- paste(raw_path, starts_filename, sep='')
stops_path <- paste(raw_path, stops_filename, sep='')

# Read formations
formations <- fread(formations_path) # remove drop to keep id_bus_flng
formations <- formations[between(year, 1980, 2019)]

# read address changes
add.changes <- fread(address_path)
add.changes <- data.table(id_bus = unique(add.changes$id_bus), AC = 1)

# For every business ID present in formations, if there is an address change, column `AC` is now 1
# can be summed later
setkey(formations, id_bus)
setkey(add.changes, id_bus)
data <- add.changes[formations]

# For rows with no address change, value of `AC` should be zero, not NA
data[is.na(AC), AC := 0]

# Aggregate by month - sanity check
data_month <- formations[,list(Formations = .N), by=list(year,month)]

# CT Aggregation
data_ct <- data[, list(Formations = .N, AC = sum(AC)), by = list(year, month, type, stock, domestic)]
data_ct[,town := 'Connecticut']
setcolorder(data_ct, c("year", "month", "town", "type", "stock", "domestic", "Formations", "AC"))

# Preliminary aggregation
data <- data[, list(Formations = .N, AC = sum(AC)), by = list(year, month, town, type, stock, domestic)]

# test join
data <- rbindlist(list(data_ct, data))

# bind in town FIPS
towns <- fread("helper_files/town_fips.csv")
setnames(towns, "Town", "town")
setkey(towns, town)

setkey(data, town)
data <- towns[data]

# Bind in county names using substrings of town FIPS
counties <- fread("helper_files/county_fips.csv")
setnames(counties, "FIPS", "County FIPS")
counties$`County FIPS` <- as.character(counties$`County FIPS`)
setkey(counties, `County FIPS`)

data[, `County FIPS` := substr(FIPS, 1, 4)]
setkey(data, `County FIPS`)

data <- counties[data]

# Relabel Types
data[
  ,
  Type := switch(
    type,
    CORP = "Corporation",
    LLC = "LLC",
    LP = "LP",
    LLP = "LLP",
    STAT = "Statutory Trust",
    GP = "General Partnership",
    BEN = "Benefit Corp.",
    "Other"
  ),
  by = type
  ]

# if type == "Other", Stock/Non and For/Dom don't matter
data[Type == "Other", `:=`(stock = "", domestic = "")]

# classify as "CT" or "non-CT" instead of D/F
data[
  ,
  Type := switch(
    domestic,
    D = paste(Type, "(CT)"),
    F = paste(Type, "(Non-CT)"),
    Type
  ),
  by = domestic
  ]

# classify as "Stock" or "Nonstock" instead of S/N
data[
  ,
  Type := switch(
    stock,
    S = paste("Stock", Type),
    N = paste("Nonstock", Type),
    Type
  ),
  by = stock
  ]

# rename a bunch of columns, drop others
data[,`:=`(
  Value = Formations,
  Town = town,
  Year = year,
  Month = month,
  `Companies with Address Change` = AC,
  AC = NULL,
  type = NULL,
  stock = NULL,
  domestic = NULL,
  Formations = NULL,
  town = NULL,
  year = NULL,
  month = NULL
)]

# Get a total irrespective of Type, bind to data
typeTotal <- data[, list(Type = "All Business Entities", Value = sum(Value), `Companies with Address Change` = sum(`Companies with Address Change`)), by = list(County, `County FIPS`, Town, FIPS, Year, Month)]

data <- rbind(data, typeTotal)

# save this for later
geoData <- data[, list(Town, FIPS, County, `County FIPS`)]
setkeyv(geoData, names(geoData))
geoData <- unique(geoData)

# backfill
backfill <- expand.grid(
  Town = unique(data$Town),
  Year = unique(data$Year),
  Month = unique(data$Month),
  Type = unique(data$Type),
  stringsAsFactors = F
)

setkey(data, Town, Year, Month, Type)
data <- merge(data, backfill, all.y = T)


data[
  Year >= 1994
  & Type %in% c(
    "LLC (CT)",
    "LLC (Non-CT)",
    "LP (Non-CT)"
  ) & is.na(Value),
  Value := 0
  ][
    Year >= 1988
    & Type == "LP (CT)"
    & is.na(Value),
    Value := 0
    ][
      Year >= 1996
      & Type == "Other"
      & is.na(Value),
      Value := 0
      ][
        Year >= 1998
        & Type == "General Partnership"
        & is.na(Value),
        Value := 0
        ][
          Year >= 1997
          & Type %in% c("Statutory Trust (CT)", "Statutory Trust (Non-CT)")
          & is.na(Value),
          Value := 0
          ][
            Year >= 2014
            & Type == "Benefit Corp."
            & is.na(Value),
            Value := 0
            ][
              Type %in% c(
                "All Business Entities",
                "Nonstock Corporation (CT)",
                "Nonstock Corporation (Non-CT)",
                "Stock Corporation (CT)",
                "Stock Corporation (Non-CT)"
              ) & is.na(Value),
              Value := 0
              ]

data[,`:=`(
  FIPS = NULL,
  County = NULL,
  `County FIPS` = NULL
)]


setkey(data, Town)
setkey(geoData, Town)
data <- data[geoData]

# Add cogs as column
cogs <- fread("helper_files/towns-and-cogs.csv")
setnames(cogs, "Planning Region", "Council Of Government")
setkey(data, Town)
setkey(cogs, Town)

data <- cogs[data]

# reorder columns
setcolorder(data, c(1, 8, 9, 10, 2, 3, 4, 5, 6, 7))

# Write to File
data_path <- paste('final', month, 'data.csv', sep='/')
write.table(
  data,
  data_path,
  sep = ",",
  row.names = F,
  na = "null"
)

# Write data to separate files by type
for(type in unique(data$Type)) {
  outputFile <- paste(type, "csv", sep=".")
  outputFilePath <- paste("final", month, "types", outputFile, sep='/')
  write.table(
    data[Type == type],
    file.path(outputFilePath),
    sep=",",
    row.names=F,
    na = "null"
  )
}


# Write data to separate nested file structure by type (dir) and by year (csv)
for(type in unique(data$Type)) {
  type_path <- paste("final", month, "types", type, sep='/')
  if (!dir.exists(file.path(type_path))) {
    dir.create(file.path(type_path))
  }
  
  for (year in unique(data$Year)) {
    outputFile <- paste(year, "csv", sep=".")
    outputFilePath <- paste(type_path, outputFile, sep='/')
    write.table(
      data[Type == type & Year == year],
      file.path(outputFilePath),
      sep=",",
      row.names=F,
      na = "null"
    )
  }
}


## Process Starts and Stops
starts <- read.csv(paste0(raw_path, "/", starts_filename), stringsAsFactors = F, header = T, check.names = F)
stops <- read.csv(paste0(raw_path, "/", stops_filename), stringsAsFactors = F, header = T, check.names = F)
starts$Type <- "Starts"
stops$Type <- "Stops"

ss_total <- rbind(starts, stops)

ss_total <- ss_total %>% 
  filter(year_filing >= 1980)

#Backfill entity types
backfill_SS <- expand.grid(
  entity_type = c('Domestic Limited Liability Company',   	
                  'Domestic Stock Corporation',	           
                  'Domestic Non-Stock Corporation',	       
                  'Domestic Limited Liability Partnership',
                  'Domestic Limited Partnership',	         
                  'Domestic Statutory Trust',	             
                  'Domestic Benefit Corporation',	         
                  'Foreign Limited Liability Company',      
                  'Foreign Stock Corporation',              
                  'Foreign Non-Stock Corporation',         
                  'Foreign Limited Liability Partnership',  
                  'Foreign Limited Partnership',            
                  'Foreign Statutory Trust'),
  year_filing = unique(ss_total$year_filing),
  month_filing = unique(ss_total$month_filing),
  Type = unique(ss_total$Type),
  stringsAsFactors = F
)

backfill_SS <- backfill_SS[!is.na(backfill_SS$month_filing) & !is.na(backfill_SS$year_filing) & !is.na(backfill_SS$Type),]
backfill_SS <- backfill_SS %>% 
  filter(year_filing >= 1980)

ss_total <- merge(ss_total, backfill_SS, by = c("entity_type", "year_filing", "month_filing", "Type"), all.y=T)

# Aggregate by year, month, type
ss_total <- as.data.table(ss_total)
ss_total2 <- ss_total[,list(Total = .N), by=list(year_filing, month_filing, Type, entity_type)]
ss_total2 <- spread(ss_total2, Type, Total)

# Sum up all entities
SS_CT <- ss_total2 %>% 
  group_by(year_filing, month_filing) %>% 
  summarise(Starts = sum(Starts), 
            Stops = sum(Stops))

SS_CT$entity_type <- 'All Entities'

SS_CT <- as.data.frame(SS_CT, stringsAsFactors = F)
ss_total2 <- rbind(ss_total2, SS_CT)

#calculate net
ss_total2$Net <- ss_total2$Starts - ss_total2$Stops

#Create data set for starts and stops 
ss_final <- ss_total2 %>% 
  select(entity_type, year_filing, month_filing, Starts, Stops, Net) %>% 
  rename("Entity Type" = "entity_type", "Year" = "year_filing", "Month" = "month_filing") %>% 
  arrange(`Entity Type`, Year)

data_path <- paste('starts_stops', month, 'data.csv', sep='/')
write.table(
  ss_final,
  data_path,
  sep = ",",
  row.names = F,
  na = "null"
)

ss_total3 <- gather(ss_total2, Variable, Value, 4:6, factor_key=F)

oldvalues <- c(1,2,3,4,5,6,7,8,9,10,11,12)
newvalues <- c("January", "February", "March", "April", "May", "June", 
               "July", "August", "September", "October", "November", "December") 

ss_total3$Month <- newvalues[ match(ss_total3$month_filing, oldvalues) ]

ss_total3$Date <- paste(ss_total3$Month, ss_total3$year_filing, sep = " ")

ss_total3 <- ss_total3 %>% 
  select(entity_type, Variable, Value, Date)

ss_total3 <- spread(ss_total3, Date, Value)

ss_total3$Variable <- factor(ss_total3$Variable, levels = c("Starts", "Stops", "Net"))


ss_total_final <- ss_total3 %>% 
  select("entity_type", "Variable",
         "January 1997", "February 1997", "March 1997", "April 1997", "May 1997", "June 1997", "July 1997", "August 1997", "September 1997", "October 1997", "November 1997", "December 1997", 
         "January 1998", "February 1998", "March 1998", "April 1998", "May 1998", "June 1998", "July 1998", "August 1998", "September 1998", "October 1998", "November 1998", "December 1998", 
         "January 1999", "February 1999", "March 1999", "April 1999", "May 1999", "June 1999", "July 1999", "August 1999", "September 1999", "October 1999", "November 1999", "December 1999", 
         "January 2000", "February 2000", "March 2000", "April 2000", "May 2000", "June 2000", "July 2000", "August 2000", "September 2000", "October 2000", "November 2000", "December 2000", 
         "January 2001", "February 2001", "March 2001", "April 2001", "May 2001", "June 2001", "July 2001", "August 2001", "September 2001", "October 2001", "November 2001", "December 2001", 
         "January 2002", "February 2002", "March 2002", "April 2002", "May 2002", "June 2002", "July 2002", "August 2002", "September 2002", "October 2002", "November 2002", "December 2002", 
         "January 2003", "February 2003", "March 2003", "April 2003", "May 2003", "June 2003", "July 2003", "August 2003", "September 2003", "October 2003", "November 2003", "December 2003", 
         "January 2004", "February 2004", "March 2004", "April 2004", "May 2004", "June 2004", "July 2004", "August 2004", "September 2004", "October 2004", "November 2004", "December 2004", 
         "January 2005", "February 2005", "March 2005", "April 2005", "May 2005", "June 2005", "July 2005", "August 2005", "September 2005", "October 2005", "November 2005", "December 2005", 
         "January 2006", "February 2006", "March 2006", "April 2006", "May 2006", "June 2006", "July 2006", "August 2006", "September 2006", "October 2006", "November 2006", "December 2006", 
         "January 2007", "February 2007", "March 2007", "April 2007", "May 2007", "June 2007", "July 2007", "August 2007", "September 2007", "October 2007", "November 2007", "December 2007", 
         "January 2008", "February 2008", "March 2008", "April 2008", "May 2008", "June 2008", "July 2008", "August 2008", "September 2008", "October 2008", "November 2008", "December 2008", 
         "January 2009", "February 2009", "March 2009", "April 2009", "May 2009", "June 2009", "July 2009", "August 2009", "September 2009", "October 2009", "November 2009", "December 2009", 
         "January 2010", "February 2010", "March 2010", "April 2010", "May 2010", "June 2010", "July 2010", "August 2010", "September 2010", "October 2010", "November 2010", "December 2010", 
         "January 2011", "February 2011", "March 2011", "April 2011", "May 2011", "June 2011", "July 2011", "August 2011", "September 2011", "October 2011", "November 2011", "December 2011", 
         "January 2012", "February 2012", "March 2012", "April 2012", "May 2012", "June 2012", "July 2012", "August 2012", "September 2012", "October 2012", "November 2012", "December 2012", 
         "January 2013", "February 2013", "March 2013", "April 2013", "May 2013", "June 2013", "July 2013", "August 2013", "September 2013", "October 2013", "November 2013", "December 2013", 
         "January 2014", "February 2014", "March 2014", "April 2014", "May 2014", "June 2014", "July 2014", "August 2014", "September 2014", "October 2014", "November 2014", "December 2014", 
         "January 2015", "February 2015", "March 2015", "April 2015", "May 2015", "June 2015", "July 2015", "August 2015", "September 2015", "October 2015", "November 2015", "December 2015", 
         "January 2016", "February 2016", "March 2016", "April 2016", "May 2016", "June 2016", "July 2016", "August 2016", "September 2016", "October 2016", "November 2016", "December 2016", 
         "January 2017", "February 2017", "March 2017", "April 2017", "May 2017", "June 2017", "July 2017", "August 2017", "September 2017", "October 2017", "November 2017", "December 2017", 
         "January 2018", "February 2018", "March 2018", "April 2018", "May 2018", "June 2018", "July 2018", "August 2018", "September 2018") %>% 
  arrange(Variable) %>%
  rename("Entity Type" = "entity_type")

data_path <- paste('starts_stops', month, 'data.csv', sep='/')
write.table(
  ss_final,
  data_path,
  sep = ",",
  row.names = F,
  na = "null"
)



