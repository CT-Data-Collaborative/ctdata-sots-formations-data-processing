library(data.table)

month <- '09_28_2017'
formations_filename <- 'formations.csv'
address_filename <- 'addresses.csv'
raw_path <- paste('extracts/', month, '/', sep='')

formations_path <- paste(raw_path, formations_filename, sep='')
address_path <- paste(raw_path, address_filename, sep='')

# Read formations
formations <- fread(formations_path) # remove drop to keep id_bus_flng
formations <- formations[between(year, 1980, 2017)]

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
setkey(counties, `County FIPS`)

data[, `County FIPS` := substr(FIPS, 1, 5)]
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
