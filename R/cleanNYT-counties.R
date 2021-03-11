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
  cleanNYT-counties.R -o <path> [--writeRejects <path>] <path>
  cleanNYT-counties.R (-h | --help)
  cleanNYT-counties.R --version

Options:
  -o <path>              Path to output cleaned data to.
  --writeRejects <path>  Path to output a .csv of rejected FIPS [fips, code, reason]
  <path>                 NYTimes us-counties.csv file [date, county, state, fips, cases, deaths]
  -h --help              Show this screen.
  --version              Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'cleanNYT-counties 0.1')

output_path  <- args$o
data_path    <- args$path
rejects_path <- args$writeRejects

cols_only(
  date   = col_date(format=""),
  fips   = col_character(),
  cases  = col_number(),
  deaths = col_number()
) -> colSpec

ps("Reading case/death file {.file {data_path}}")
d <- read_csv(data_path, col_types = colSpec)
pd()

ps("Removing NA-valued fips (Unknown & Geographic exceptions)")
d <- filter(d, !is.na(fips))
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

ps("Removing territories")
startingFIPS <- unique(shortFIPSStripped$fips)
territoriesStripped <- filter(
  shortFIPSStripped,
  !str_detect(fips, '^69'), # Northern Mariana Islands
  !str_detect(fips, '^72'), # Puerto Rico
  !str_detect(fips, '^78')  # Virgin Islands
)
endingFIPS <- unique(territoriesStripped$fips)
rejects <- bind_rows(rejects, tibble(
  fips   = setdiff(startingFIPS, endingFIPS),
  code   = 'EXCLUDE_LIST',
  reason = "On the list of excluded counties"
))
pd()

ps("Writing cleaned data to {.file {output_path}}")
write_csv(territoriesStripped, output_path)
pd()

if (!identical(args$writeRejects, FALSE)) {
  ps("Writing rejected counties to {.file {rejects_path}}")
  write_csv(rejects, rejects_path)
  pd()
}

warnings()
