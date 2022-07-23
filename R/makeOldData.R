#!/usr/bin/Rscript
'Fake archival data creator

Usage:
  makeOldData.R -o <dir> --timeseries <path> --metadata <path> --rejects <path> --weeks-back <n> --key <string>
  makeOldData.R (-h | --help)
  makeOldData.R --version

Options:
  --timeseries <path>  Path to timeseries data
  --metadata <path>  Path to JSON metadata
  --rejects <path>  Path to rejects CSV
  --weeks-back <n>  The number of weeks to go back [default: 0]
  --key <string>  fips or state
  -o <dir>  The directory to write the data.csv, metadata.json, and rejects.csv files
  -h --help  Show this screen.
  --version  Show version.

' -> doc

suppressPackageStartupMessages({
  library(docopt)
  library(jsonlite)
  library(tidyverse)
  library(glue)
})

args <- docopt(doc, version = 'makeOldData.R 0.1')
args$weeks_back <- as.numeric(args$weeks_back)

#############################
#####  Rejects           ####
#############################

# Just copy the rejects file without modification
rejects <- read_csv(args$rejects, col_types = cols(.default = col_character()))
write_csv(rejects, glue("{args$o}/rejects.csv"))

#############################
#####  Timeseries        ####
#############################

# Assume the other vars are characters, because we don't need to interact with 
# them.
timeseries <- read_csv(
  args$timeseries,
  col_types = cols(date = col_date(), .default = col_character())
)

# Chop off the last --weeks-back dates
timeseries_dates_original <- unique(timeseries$date) %>% sort
timeseries_dates_new <-
  timeseries_dates_original[1:(length(timeseries_dates_original) - args$weeks_back)]

timeseries_new <- filter(timeseries, date %in% timeseries_dates_new)
write_csv(timeseries_new, glue("{args$o}/data.csv"))

#############################
#####  Metadata          ####
#############################

metadata <- read_json(args$metadata, simplifyVector = T)

max_dates <- group_by_at(timeseries_new, args$key) %>%
  summarize(maxInputDate = max(as.Date(date)), .groups = 'drop') 

# Revise the `maxInputDate` and `lastHospDate`. `lastHospDate` is a special
# case, because it might still be earlier in time than `lastHospDate`.
metadata_new <- inner_join(
  metadata, max_dates, by = args$key, suffix=c(".metadata", ".max_dates")
) %>% mutate(
  maxInputDate = maxInputDate.max_dates,
  lastHospDate = pmin(as.Date(lastHospDate), maxInputDate.max_dates),
  maxInputDate.metadata = NULL,
  maxInputDate.max_dates = NULL
)

write_json(metadata_new, glue("{args$o}/metadata.csv"), auto_unbox = T)
