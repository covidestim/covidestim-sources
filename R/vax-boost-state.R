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

'Vax-boost State-data Cleaner

Usage:
  vax-boost-state.R -o <path> --cdcpath <path>
  vax-boost-state.R (-h | --help)
  vax-boost-state.R --version

Options:
  -o <path>                 Path to output cleaned data to.
  -h --help                 Show this screen.
  --cdcpath <path>          Path to the cdc data 
  --version                 Show version.

' -> doc
ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'vax-boost-state 0.1')

output_path   <- args$o
cdcpath       <- args$cdcpath

cols_only(
  Date = col_date(format = "%m/%d/%Y"),
  Location = col_character(),
  Administered_Dose1_Recip = col_double(),
  Administered_Dose1_Pop_Pct = col_double(),
  Series_Complete_Yes = col_double(),
  Series_Complete_Pop_Pct = col_double(),
  Additional_Doses = col_double(),
  Additional_Doses_Vax_Pct = col_double()
  ) -> colSpec

ps("Reading cdc vaccinations and booster data by state {.file {cdcpath}}")
cdc <- read_csv(cdcpath, col_types = colSpec)
pd()

cum_To_daily <- function(x) {
  out <- c(x[1], diff(x))
  # replace all negative or NA values by zero
  # this ensures that the cumulative boosters is continuous increasing
  # and that every date has a valid numeric value
  out[which(out < 0 | is.na(out))] <- 0
  return(out)
  }

ps("Transforming variables names {.file {cdcpath}}")
cdc %>% transmute(
          state = Location,
          date = Date,
          first_dose_cum = Administered_Dose1_Recip,
          first_dose_cum_pct = Administered_Dose1_Pop_Pct,
          full_vax_cum = Series_Complete_Yes,
          full_vax_cum_pct = Series_Complete_Pop_Pct,
          boost_cum = Additional_Doses,
          boost_cum_pct = Additional_Doses_Vax_Pct) %>%
  mutate(state = usdata::abbr2state(state)) %>%
  group_by(state) %>%
  arrange(date) %>%
  mutate(
    first_dose_n = cum_To_daily(first_dose_cum),
    full_vax_n = cum_To_daily(full_vax_cum),
    boost_n = cum_To_daily(boost_cum)
    ) %>%
  ungroup() %>%
  drop_na() -> final
pd()


ps("Writing cleaned data to {.file {output_path}}")
write_csv(final, output_path)
pd()


