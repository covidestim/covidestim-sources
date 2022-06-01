#!/usr/bin/env Rscript
library(dplyr,     warn.conflicts = FALSE)
library(tidyverse, warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
library(stringr,   warn.conflicts = FALSE)
library(lubridate, warn.conflicts = FALSE)
library(purrr,     warn.conflicts = FALSE)
library(usdata,    warn.conflicts = FALSE)

'Vax-boost County-data Cleaner

Usage:
  vax-boost-county.R -o <path> --cdcpath <path> --statepath <path> --fipspoppath <path>
  vax-boost-county.R (-h | --help)
  vax-boost-county.R --version

Options:
  -o <path>                 Path to output cleaned data to.
  -h --help                 Show this screen.
  --cdcpath <path>          Path to the cdc data 
  --statepath <path>        Path to the cleaned state vax data 
  --fipspoppath <path>      Path to fipspop file
  --version                 Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'vax-boost-county 0.1')
output_path   <- args$o
cdcpath <- args$cdcpath
statepath <- args$statepath
fipspoppath <- args$fipspoppath

cols_only(
  Date = col_date(format = "%m/%d/%Y"),
  FIPS = col_character(),
  Recip_State = col_character(),
  Completeness_pct = col_number(),
  Administered_Dose1_Recip = col_number(),
  Administered_Dose1_Pop_Pct = col_number(),
  Series_Complete_Yes = col_number(),
  Series_Complete_Pop_Pct = col_number(),
  Booster_Doses = col_number(),
  Booster_Doses_Vax_Pct = col_number()
  ) -> colSpec

cols_only(
  date = col_date(),
  state = col_character(),
  first_dose_cum = col_double(),
  first_dose_cum_pct = col_double(),
  first_dose_n = col_double(),
  full_vax_cum = col_double(),
  full_vax_cum_pct = col_double(),
  full_vax_n = col_double(),
  boost_cum = col_double(),
  boost_cum_pct = col_double(),
  boost_n = col_double()
) -> colSpecState

ps("Reading cdc vaccinations and booster data by county {.file {args$cdcpath}}")
cdc <- read_csv(cdcpath, col_types = colSpec) 
pd()

ps("Reading cleaned vaccinations and booster data by state {.file {args$statepath}}")
stt_vax <- read_csv(statepath, col_types = colSpecState) 
pd()

ps("Reading fipspop mapping {.file {args$fipspoppath}}")
fipspop <- read_csv(fipspoppath)
pd()

ps("Renaming variables names {.file {args$cdcpath}}")
cdc %>% 
  mutate(state = usdata::abbr2state(Recip_State)) %>%
  transmute(
  fips = FIPS,
  date = Date,
  state = state,
  completeness_pct = Completeness_pct,
  first_dose_cum = Administered_Dose1_Recip,
  first_dose_cum_pct = Administered_Dose1_Pop_Pct,
  full_vax_cum = Series_Complete_Yes,
  full_vax_cum_pct = Series_Complete_Pop_Pct,
  boost_cum = Booster_Doses,
  boost_cum_pct = Booster_Doses_Vax_Pct) -> cdcClean
pd()

ps("Generate dates for the county data until October 21, 2021")
## October 21, because all states report their first cumulative counts on
## October 20.
allFipsDates <- cdcClean %>%
  group_by(fips) %>%
  summarize(date = seq.Date(as.Date("2021-10-21"), as.Date("2021-12-16"), 1),
            .groups = 'drop') %>%
  ungroup()
pd()

ps("Transform data to be monotonically increasing from last observed date")

## Start at the end of the timeseries; if the previous value is higher,
## replace with the last value.
monoInc <- function(x){
  x.bw <- rev(x)
  x.bw[which(is.na(x.bw))] <- 0
  for(i in 2:length(x)){
    if(x.bw[i] > x.bw[i-1]) x.bw[i] <- x.bw[i-1]
  }
  rev(x.bw)
}

cdcClean %>% 
  group_by(fips) %>%
  arrange(date) %>%
  mutate(boost_cum_pct = monoInc(boost_cum_pct)) %>%
  ungroup() -> cdcClean2

pd()

ps("Calculate the county/state fraction for first available date after December 16, 2021")
cdcClean2 %>% 
  right_join(stt_vax %>% 
               transmute(date = date,
                         state = state,
                         boost.stt = boost_cum_pct
                          ), by = c("state", "date")) %>%
  filter(date >= as.Date("2021-12-16")) %>%
  mutate(rr = boost_cum_pct / boost.stt) %>%
  group_by(fips) %>%
  arrange(date) %>%
  mutate(rr_first = first(na.omit(rr))) %>%
  ungroup() %>%
  filter(date == as.Date("2021-12-16")) %>%
  mutate(rr = if_else(state == "Hawaii", # Hawaii counties are all missing; impute with state estimates
                      1,
                      # if there is no data on a date; impute the ratio with the state estimates
                      if_else(is.na(rr_first), 
                              1,
                              rr_first
                              )
                      )
         ) -> fipsStateFrac

pd()

ps("Prefill and impute the county booster data")

cum_To_daily <- function(x) {
  out <- c(x[1], diff(x))
  # replace all negative or NA values by zero
  # this ensures that the cumulative boosters is continuous increasing
  # and that every date has a valid numeric value
  out[which(out < 0 | is.na(out))] <- 0
  return(out)
}

cdcClean2 %>% 
  drop_na(state) %>%
  full_join(allFipsDates, by = c("fips", "date"))  %>%
  left_join(stt_vax %>% 
              transmute(date = date,
                        state = state,
                        boost.stt = boost_cum_pct
              ), by = c("state", "date")) %>%
  left_join(fipsStateFrac %>% select(fips, rr), by = "fips") %>%
  left_join(fipspop, by = "fips") %>%
  mutate(boost_cum_pct_imp = if_else(date < as.Date("2021-12-16"),
                                     boost.stt * rr,
                                     if_else(boost_cum_pct == 0,
                                             boost.stt,
                                             boost_cum_pct)
                                     ),
         boost_cum_imp = round(boost_cum_pct_imp / 100 * pop)
         ) %>%
  filter(fips != "UNK") %>%
  group_by(fips) %>%
  arrange(date) %>%
  mutate(
    first_dose_n = cum_To_daily(first_dose_cum),
    full_vax_n = cum_To_daily(full_vax_cum),
    boost_n = cum_To_daily(boost_cum_imp)
  ) %>%
  ungroup() -> final

pd()

ps("Writing cleaned data to {.file {output_path}}")
write_csv(final, output_path)
pd()
