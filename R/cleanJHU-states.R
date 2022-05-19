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
  cleanJHU-states.R -o <path> [--writeRejects <path>] [--prefill <path>] [--splicedate <date/path>] [--writeMetadata <path>] --reportsPath <path>
  cleanJHU-states.R (-h | --help)
  cleanJHU-states.R --version

Options:
  -o <path>                 Path to output cleaned data to.
  --writeRejects <path>     Path to output a .csv of rejected FIPS [fips, code, reason]
  --writeMetadata <path>    Where to save a .json of metadata about the result of each state
  --prefill <path>          Prepend JHU case-death data using data from <path> [date, state, cases, deaths, fracpos, volume]
  --splicedate <date/path>  When --prefill is specified, --splicedate changes the "prepend" date to a date within the JHU timeseries, instead of at the beginning. If a <path> is passed w/ columns [state,date], those dates are used as splicedates instead. If no splicedate is specified for a state, the first day of JHU data will be used as the date. WARNING: the case where date > max(date) is not handled, so you must ensure that your splice dates are realistic.
  --reportsPath <path>      Directory where the daily US reports live inside the JHU repo
  -h --help                 Show this screen.
  --version                 Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'cleanJHU-states 0.1')

output_path   <- args$o
reports_path  <- args$reportsPath
rejects_path  <- args$writeRejects
prefill_path  <- args$prefill
metadata_path <- args$writeMetadata

cols_only(
  Province_State     = col_character(),
  Confirmed          = col_double(),
  Deaths             = col_double(),
  Total_Test_Results = col_double()
) -> colSpec

cols_only(
  Province_State     = col_character(),
  Confirmed          = col_double(),
  Deaths             = col_double()
) -> colSpecBackup

cols_only(
  date   = col_date(format = ""),
  state  = col_character(),
  cases  = col_double(),
  deaths = col_double(),
  fracpos= col_double(),
  volume = col_double()
) -> colSpecPrefill

if (!is.null(args$prefill)) {
  ps("Reading prefill file {.file {prefill_path}}")
  prefill <- read_csv(prefill_path, col_types = colSpecPrefill)
  pd()
}

reader <- function(fname) {
  ps("Reading daily report {.file {basename(fname)}}")
  d <- tryCatch(
    read_csv(fname, col_types = colSpec),
    warning = function(c) read_csv(fname, col_types = colSpecBackup)
  )

  if (!"Total_Test_Results" %in% names(d))
    d <- mutate(d, Total_Test_Results = 0)

  d <- rename(
    d,
    state  = Province_State,
    cases  = Confirmed,
    deaths = Deaths,
    volume = Total_Test_Results
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
    deaths = pmax(deaths - lag(deaths, default = 0), 0),
    volume = pmax(volume - lag(volume, default = 0), 0),
    fracpos = ifelse(volume > 0, cases/volume, 0)
  )

# Reorder to maintain parity with .csv structure for CTP
d <- select(d, date, state, cases, deaths, fracpos, volume)

ps("Removing states with fewer than 60 days observations")

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

final <- shortStatesStripped

# Handle the --prefill flag
if (!is.null(args$prefill)) {
  customSpliceDateFilePresent <- FALSE
  splicedate <- as.Date('1970-01-01') # Dummy value

  if (!is.null(args$splicedate) && !file.exists(args$splicedate)) {
    splicedate <- as.Date(args$splicedate)
    cli_alert_info("Custom splicedate used: {args$splicedate}")
  } else if (!is.null(args$splicedate) && file.exists(args$splicedate)) {
    customSpliceDateFilePresent <- TRUE
    customSpliceDates <- read_csv(
      args$splicedate,
      col_types = cols_only(
        state = col_character(),
        date = col_date(format="")
      )
    )
    cli_alert_info("Custom splicedate file used: {.file {args$splicedate}}")
  }

  JHU <- final
  CTP <- prefill # Assuming prefill source is CTP

  JHUcumulative <- group_by(JHU, state) %>%
    arrange(date) %>%
    mutate_at(c('cases', 'deaths'), cumsum) %>%
    ungroup

  # Find first day-of-data for each state in JHU dataset
  JHUsplicedates <- JHU %>% group_by(state) %>%
    # The max(min()) is there to prevent a splicedate which was specified before
    # the beginning of the JHU timeseries to be used - instead, min(date) will be
    # used. Then, the case where splicedate > max(date) is handled.
    summarize(date.splice = max(min(date), splicedate) %>% min(., max(date)))

  if (customSpliceDateFilePresent) {
    # Process the custom file by joining it to the already-computed splicedates.
    # These dates will all be equal to min(date). Then, take the max(), to
    # protect against the case where a splicedate specified in the file is 
    # actually earlier than the first day of JHU data
    amendedJHUsplicedates <-
      left_join(JHUsplicedates, customSpliceDates, by = 'state') %>%
      transmute(
        state,
        date.splice = pmax(date.splice, date, na.rm = TRUE)
      )

    JHUsplicedates <<- amendedJHUsplicedates
  }

  ps("Calculating per-state, per-outcome scaling factors")
  # Calculate the scaling factor neccessary for the cumulative
  # cases/deaths of CTP data to match JHU's ccases/cdeaths on the
  # first day of intersection
  JHUscale <- JHUsplicedates %>%
    left_join(
      JHUcumulative %>% select(state, date, cases, deaths),
      by = c('state', 'date.splice' = 'date')
    ) %>%
    left_join(
      CTP %>%
        select(state, date, cases, deaths) %>%
        group_by(state) %>%
        # incidence -> cumulative incidence
        mutate_at(c('cases', 'deaths'), cumsum) %>%
        ungroup,
      by     = c('state', 'date.splice' = 'date'),
      suffix = c('.jhu', '.ctp')
    ) %>%
    transmute(
      state,
      cases.scale  = case_when(
        is.na(cases.ctp) ~ 1, # When there's no CTP data (Puerto Rico)
        cases.ctp == 0   ~ 1, # Prevent /0 error
        TRUE             ~ cases.jhu/cases.ctp
      ),
      deaths.scale = case_when(
        is.na(deaths.ctp) ~ 1,# ""
        deaths.ctp == 0   ~ 1,# ""
        TRUE              ~ deaths.jhu/deaths.ctp
      )
    )
  pd()

  cli_alert_info("`JHUsplicedates`:")
  print(JHUsplicedates, n=200)
  cli_alert_info("`JHUscale`:")
  print(JHUscale, n=200)

  # Perform the scaling operation on all CTP days that are on or before
  # "computed" splice date for each state. Floor everything to keep it
  # integer-valued.
  ps("Scaling")
  scaled_prefill <- CTP %>%
    left_join(JHUscale, by = 'state') %>%
    left_join(JHUsplicedates, by = 'state', suffix = c('', '.max')) %>%
    filter(date <= date.splice) %>%
    transmute(
      date,
      state,
      cases  = floor(cases * cases.scale),
      deaths = floor(deaths * deaths.scale),
      fracpos,
      volume
    )
  pd()

  # Attach the scaled CTP rows and sort again.
  # Get rid of the first day of JHU data for each state. This is 
  # because it's a data dump, and will instead be filled in by the CTP
  # data
  prefilled <- bind_rows(
    scaled_prefill,
    JHU %>% left_join(JHUsplicedates, by = 'state') %>%
      group_by(state) %>%
      filter(date > date.splice) %>%
      ungroup %>%
      select(-date.splice)
  ) %>%
    arrange(state, date)

  final <<- prefilled

  cli_alert_success("Prefill complete")
}

ps("Writing cleaned data to {.file {output_path}}")
write_csv(final, output_path)
pd()

if (!is.null(args$writeMetadata)) {
  ps("Writing metadata to {.file {metadata_path}}")
  metadata <- group_by(final, state) %>%
    summarize(
      minInputDate = min(date),
      maxInputDate = max(date)
    )
  jsonlite::write_json(metadata, metadata_path, null = "null")
  pd()
}

if (!is.null(args$writeRejects)) {
  ps("Writing rejected counties to {.file {rejects_path}}")
  write_csv(rejects, rejects_path)
  pd()
}

warnings()
