#!/usr/bin/env Rscript
library(dplyr,     warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
library(stringr,   warn.conflicts = FALSE)
library(lubridate, warn.conflicts = FALSE)
library(purrr,     warn.conflicts = FALSE)
                    
'NYT County-data Cleaner

Usage:
  cleanNYT-counties.R -o <path> --pop <path> --nonreporting <path> [--writeRejects <path>] --writeMetadata <path> <path>
  cleanNYT-counties.R (-h | --help)
  cleanNYT-counties.R --version

Options:
  -o <path>               Path to output cleaned data to.
  --pop <path>            Path to population size .csv (for excluding unk. counties)
  --nonreporting <path>   A csv [fipsPattern,date(YYYY-MM-DD)] specifying which counties no longer report deaths
  --writeRejects <path>   Path to output a .csv of rejected FIPS [fips, code, reason]
  --writeMetadata <path>  Where to output per-county metadata .json file
  <path>                  NYTimes us-counties.csv file [date, county, state, fips, cases, deaths]
  -h --help               Show this screen.
  --version               Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'cleanNYT-counties 0.1')

output_path       <- args$o
data_path         <- args$path
rejects_path      <- args$writeRejects
nonreporting_path <- args$nonreporting
metadata_path     <- args$writeMetadata
pop_path          <- args$pop

cols_only(
  date   = col_date(format=""),
  fips   = col_character(),
  cases  = col_number(),
  deaths = col_number()
) -> colSpec

cols(
  fips = col_character(),
  nonReportingBegins = col_date(format = "%Y-%m-%d"),
  nonReportingNote = col_character()
) -> col_types.nonreporting

ps("Reading case/death file {.file {data_path}}")
d <- read_csv(data_path, col_types = colSpec)
pd()

ps("Removing NA-valued fips (Unknown & Geographic exceptions)")
d <- filter(d, !is.na(fips))
pd()

ps("Loading nonreporting information from {.file {nonreporting_path}}")
nonreporting <- read_csv(nonreporting_path, col_types = col_types.nonreporting)
pd()

ps("Loading population size data from {.file {pop_path}}")
popsize <- read_csv(pop_path, col_types = 'cn')
pd()

cli_alert_info("Moving from cumulative counts to incidence")
d <- arrange(d, fips, date) %>% group_by(fips) %>%
  mutate(
    # Can't have cases or deaths decrease, hence the max()
    cases  = pmax(cases - lag(cases, default = 0), 0),
    deaths = pmax(deaths - lag(deaths, default = 0), 0)
  )

ps("Removing counties with fewer than 60 days' observations")

startingFIPS <- unique(d$fips)
shortFIPSStripped <- group_by(d, fips) %>% filter(n() >= 60) %>% ungroup

endingFIPS <- unique(shortFIPSStripped$fips)
rejects <- tibble(
  fips   = setdiff(startingFIPS, endingFIPS),
  code   = 'UNDER60',
  reason = "Fewer than 60 days of data"
)
pd()

ps("Removing states/territories")

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
         !str_detect(fips, "^78\\d{3}"),    # VI
         !str_detect(fips, "^72999$"),      # "Unassigned" Puerto Rico
         !str_detect(fips, "^72888$"),      # "Out of" Puerto Rico
         !str_detect(fips, "^88888$"),      # Diamond Princess
         !str_detect(fips, "^99999$"))      # Grand Princess

startingFIPS <- unique(shortFIPSStripped$fips)
territoriesStripped <- shortFIPSStripped %>% filterStateFips %>% filterBannedFips
endingFIPS <- unique(territoriesStripped$fips)
rejects <- bind_rows(rejects, tibble(
  fips   = setdiff(startingFIPS, endingFIPS),
  code   = 'EXCLUDE_LIST',
  reason = "On the list of excluded counties"
))
pd()

ps("Removing Nebraska counties' data after June 30, 2021")
nebraskaClipped <- filter(
  territoriesStripped,
  !(str_detect(fips, '^31') & (date > as.Date('2021-06-30')))
)
pd()

ps("Removing counties for which we lack population size data")
startingFIPS <- unique(nebraskaClipped$fips)

unknownCountiesStripped <- filter(nebraskaClipped, fips %in% unique(popsize$fips))

endingFIPS <- unique(unknownCountiesStripped$fips)
rejects <- bind_rows(
  rejects,
  tibble(
    fips = setdiff(startingFIPS, endingFIPS),
    code = 'NOPOP',
    reason = "No population size information"
  )
)
pd()

ps("Writing cleaned data to {.file {output_path}}")
write_csv(unknownCountiesStripped, output_path)
pd()

ps("Writing metadata to {.file {metadata_path}}")
metadata <- unknownCountiesStripped %>%
  group_by(fips) %>%
  summarize(
    minInputDate = min(date),
    dataSource   = "nytimes",
    maxInputDate = max(date)
  )

metadata <- left_join(
  metadata,
  nonreporting,
  by = "fips"
)

jsonlite::write_json(metadata, metadata_path, null = "null")
pd()

if (!identical(args$writeRejects, FALSE)) {
  ps("Writing rejected counties to {.file {rejects_path}}")
  write_csv(rejects, rejects_path)
  pd()
}

warnings()
