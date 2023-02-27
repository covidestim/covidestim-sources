#!/usr/bin/env Rscript
library(dplyr,     warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(purrr,     warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
library(stringr,   warn.conflicts = FALSE)
library(tidyr,   warn.conflicts = FALSE)

'CDC State-data Cleaner

Usage:
  cleanCDC-state.R -o <path> --cases <path>
  cleanCDC-state.R (-h | --help)
  cleanCDC-state.R --version

Options:
  -o <path>               Path to output cleaned data to.
  --cases <path>          Path to the cases data 
  -h --help               Show this screen.
  --version               Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

detect_all <- function(input, pats) map(pats, ~str_detect(input, .)) %>% reduce(`|`)

args   <- docopt(doc, version = 'cleanCDC-state 0.1')

output_path       <- args$o
cases_path        <- args$cases

cols_only(
  state = col_character(), 
  date_updated = col_character(),
  start_date = col_character(),
  end_date = col_character(),
  new_cases = col_number()
  ) -> colSpec

ps("Loading CDC cases data from {.file {cases_path}}")
cases <- read_csv(cases_path, col_types = colSpec) %>% 
  mutate(
    date_updated = as.Date(date_updated, format = "%m/%d/%Y"),
    start_date = as.Date(start_date, format = "%m/%d/%Y"),
    end_date = as.Date(end_date, format = "%m/%d/%Y")
    )
pd()

ps("Checking if all weeks are valid")
maxDate <- max(cases$date_updated)
minDate <- min(cases$date_updated)
allDates <- seq.Date(minDate, maxDate, by = '1 week') 

if(!all(cases$date_updated %in% allDates)){
  stop("Check the dates of the CDC data")
}
pd()


ps("Filtering data, new cases by week, date denotes week END")
final <- cases %>%
  # NOTE: I am using date_updated here as a proxy for week-end
  # because this one matches with the hospitalizations data from hhs!
  transmute(date = date_updated,
            state = usdata::abbr2state(state),
            cases = new_cases
            ) %>%
  drop_na(state)
pd()

ps("Filtering any regions with NA data") 
NaState <- final %>%
  group_by(state) %>%
  summarize(nNa = sum(is.na(cases)), .groups = 'drop') %>%
  filter(nNa != 0) %>%
  pull(state) %>% unique()

final <- filter(final, ! state %in% NaState)
pd()


ps("Writing cleaned data to {.file {output_path}}")
write_csv(final, output_path)
pd()

warnings()
