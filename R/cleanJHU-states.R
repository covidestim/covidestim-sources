#!/usr/bin/env Rscript
library(dplyr,     warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
library(stringr,   warn.conflicts = FALSE)
library(lubridate, warn.conflicts = FALSE)
library(purrr,     warn.conflicts = FALSE)
                    
'JHU State-data Cleaner

Usage:
  cleanJHU-states.R -o <path> [--writeRejects <path>] --reportsPath <path>
  cleanJHU-states.R (-h | --help)
  cleanJHU-states.R --version

Options:
  -o <path>              Path to output cleaned data to.
  --writeRejects <path>  Path to output a .csv of rejected FIPS [fips, code, reason]
  --reportsPath <path>   Directory where the daily US reports live inside the JHU repo
  -h --help              Show this screen.
  --version              Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'cleanJHU-states 0.1')

output_path  <- args$o
reports_path <- args$reportsPath
rejects_path <- args$writeRejects

cols_only(
  Province_State = col_character(),
  Confirmed = col_double(),
  Deaths = col_double()
) -> colSpec

reader <- function(fname) {
  ps("Reading daily report {.file {basename(fname)}}")
  d <- read_csv(fname, col_types = colSpec)
  d <- rename(
    d,
    state  = Province_State,
    cases  = Confirmed,
    deaths = Deaths
  )
  pd()
  d
}

filesToLoad  <- Sys.glob(file.path(reports_path, '*.csv'))
datesOfFiles <- basename(filesToLoad) %>% str_remove('.csv') %>% mdy

d <- map2_dfr(
  filesToLoad,
  datesOfFiles,
  ~reader(.x) %>% mutate(date = .y) %>% select(date, everything())
)

startingStates <- unique(d$state)
allowedStates <- c(state.name, "District of Columbia", "Puerto Rico")


d <- filter(d, state %in% allowedStates) %>%
  arrange(state, date)

rejects <- tibble(
  state = setdiff(startingStates, unique(d$state)),
  code = 'EXCLUDE_LIST',
  reason = "On the list of excluded states"
)

cli_alert_info("Moving from cumulative counts to incidence")
d <- group_by(d, state) %>%
  mutate(
    # Can't have cases or deaths decrease, hence the max()
    cases = pmax(cases - lag(cases, default = 0), 0),
    deaths = pmax(deaths - lag(deaths, default = 0), 0)
  )

ps("Removing counties with fewer than 60 days' observations")

startingStates <- unique(d$state)
shortStatesStripped <- group_by(d, state) %>% filter(n() > 60) %>% ungroup

endingStates <- unique(shortStatesStripped$state)
rejects <- bind_rows(
  rejects,
  tibble(
    state = setdiff(startingStates, endingStates),
    code = 'UNDER60',
    reason = "Fewer than 60 days of data"
  )
)
pd()

ps("Writing cleaned data to {.file {output_path}}")
write_csv(shortStatesStripped, output_path)
pd()

if (!identical(args$writeRejects, FALSE)) {
  ps("Writing rejected counties to {.file {rejects_path}}")
  write_csv(rejects, rejects_path)
  pd()
}

warnings()
