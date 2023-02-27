#!/usr/bin/env Rscript
library(dplyr,     warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(purrr,     warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
library(stringr,   warn.conflicts = FALSE)
library(tidyr,   warn.conflicts = FALSE)

'CDC County-data Cleaner

Usage:
  cleanCDC-counties.R -o <path> --writeMetadata <path> --cases <path>
  cleanCDC-counties.R (-h | --help)
  cleanCDC-counties.R --version

Options:
  -o <path>               Path to output cleaned data to.
  --writeMetadata <path>  Where to output per-county metadata .json file
  --cases <path>          Path to the cases data 
  -h --help               Show this screen.
  --version               Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args   <- docopt(doc, version = 'cleanCDC-counties 0.1')

output_path       <- args$o
cases_path        <- args$cases
metadata_path     <- args$writeMetadata

cols_only(
  county_fips = col_character(), 
  state = col_character(), 
  county_population = col_number(),
  covid_hospital_admissions_per_100k = col_number(), 
  covid_cases_per_100k = col_number(), 
  date_updated = col_date()
) -> colSpec

ps("Loading CDC cases data from {.file {cases_path}}")
cases <- read_csv(cases_path, col_types = colSpec)
pd()

ps("Checking that all reports are one week apart")
maxDate <- max(cases$date_updated)
minDate <- min(cases$date_updated)
allDates <- seq.Date(minDate, maxDate, by = '1 week') 

if(!all(cases$date_updated %in% allDates)){
  stop("Check the dates of the CDC data")
}
pd()

ps("Recomputing new cases by week, date denotes week END")
final <- cases %>%
  transmute(date = date_updated,
            fips = county_fips,
            # state = state,
            cases = covid_cases_per_100k / 100000 * county_population)
            # hosp = covid_hospital_admissions_per_100k * 100000/county_population)
# for future reference: hospitalizations can be checked against the HHS data
pd()

ps("Filtering any regions with NA data") 
Nafips <- final %>%
  group_by(fips) %>%
  summarize(nNa = sum(is.na(cases)), .groups = 'drop') %>%
  filter(nNa != 0) %>%
  pull(fips) %>% unique()

final <- filter(final, ! fips %in% Nafips)
pd()

ps("Filtering any illegal regions")
filterStateFips <- function(df)
  filter(df,
         !is.na(fips),                      # No invalid fips codes
         str_length(fips) == 5)             # No states or territories

filterBannedFips <- function(df)
  filter(df,
         !str_detect(fips, "^800[0-5]\\d"), # The "Out of [statename]" tracts
         !str_detect(fips, "^900[0-5]\\d"), # The "Unassigned" tracts
         !str_detect(fips, "^60\\d{3}"),    # AS
         !str_detect(fips, "^66\\d{3}"),    # MP, GU
         !str_detect(fips, "^69\\d{3}"),    # MP
         !str_detect(fips, "^72\\d{3}"),    # PR
         !str_detect(fips, "^78\\d{3}"),    # VI
         !str_detect(fips, "^72999$"),      # "Unassigned" Puerto Rico
         !str_detect(fips, "^72888$"),      # "Out of" Puerto Rico
         !str_detect(fips, "^88888$"),      # Diamond Princess
         !str_detect(fips, "^99999$"))      # Grand Princess


startingFIPS = unique(final$fips)
final <- final %>% filterBannedFips
endingFIPS = unique(final$fips)
rejects <- tibble(
  fips = setdiff(startingFIPS, endingFIPS),
  code = 'EXCLUDE_LIST',
  reason = "On the list of excluded counties"
)

startingFIPS = unique(final$fips)
final <- final %>% filterStateFips
endingFIPS = unique(final$fips)
rejects <- bind_rows(rejects, tibble(
  fips = setdiff(startingFIPS, endingFIPS),
  code = 'INVALID',
  reason = "Was a state or territory or an incomplete FIPS code"
))

pd()


ps("Writing cleaned data to {.file {output_path}}")
write_csv(final, output_path)
pd()

ps("Writing metadata to {.file {metadata_path}}")
metadata <- final %>%
  group_by(fips) %>%
  summarize(
    minInputDateCDC = min(date),
    maxInputDateCDC = max(date)
  )

jsonlite::write_json(metadata, metadata_path, null = "null")
pd()


warnings()
