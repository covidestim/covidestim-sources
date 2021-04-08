#!/usr/bin/env Rscript
suppressPackageStartupMessages( library(tidyverse) )
library(docopt, warn.conflicts = FALSE)
library(cli,    warn.conflicts = FALSE)
                    
'HHS Hospitalizations-data Cleaner

Usage:
  cleanHHS.R -o <path> --crosswalk <path> --hhs <path>
  cleanHHS.R (-h | --help)
  cleanHHS.R --version

Options:
  -o <path>             Path to output cleaned data to.
  --crosswalk <path>    Path to Dartmouth Atlas zip code crosswalks (zip => hss => hrr)
  --hhs <path>          Path to HHS dataset, "COVID-19 Reported Patient Impact and Hospital Capacity by Facility"
  -h --help             Show this screen.
  --version             Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args   <- docopt(doc, version = 'cleanHHS.R 0.1')

# Fake args for debugging/development
# args <- list(
#   o = 'DELTEEME',
#   crosswalk = "../data-sources/ZipHsaHrr18.csv",
#   hhs = "../hhs_tmp.csv"
# )

output_path <-  args$o
crosswalk_path <- args$crosswalk
hhs_path <- args$hhs

hhsSpec <- cols(
  .default = col_double(),
  hospital_pk = col_character(),
  collection_week = col_date(format = "%Y/%m/%d"),
  state = col_character(),
  ccn = col_character(),
  hospital_name = col_character(),
  address = col_character(),
  city = col_character(),
  zip = col_character(),
  hospital_subtype = col_character(),
  fips_code = col_character(),
  is_metro_micro = col_logical(),
  geocoded_hospital_address = col_character()
)

ps("Reading crosswalk file {.file {crosswalk_path}}")
crosswalk <- read_csv(
  crosswalk_path,
  col_types = 'ccccccc'
)
pd()

ps("Reading HHS file {.file {hhs_path}}")
hhs <- read_csv(
  hhs_path,
  col_types = hhsSpec
)
pd()

# Any negative number that is not -999999 is coerced to NA
cleanAdmissions <- function(v) case_when(
  is.na(v)     ~ as.numeric(NA),
  v == -999999 ~ -999999,
  v < 0        ~ as.numeric(NA),
  TRUE         ~ v
)

# Computes min/max for censored data
admissionsMin <- function(v) ifelse(v == -999999, 1, v)
admissionsMax <- function(v) ifelse(v == -999999, 3, v)

ps("Cleaning admissions data")
cleaned <- transmute(
  hhs,
  hospital_pk, hospital_name,

  zip = str_pad(zip, width = 5, side = 'left', pad = '0'), # Fix non-5-digit zips

  weekstart = collection_week,

  admissionsAdultsConfirmed = previous_day_admission_adult_covid_confirmed_7_day_sum,
  admissionsAdultsSuspected = previous_day_admission_adult_covid_suspected_7_day_sum,
  admissionsPedsConfirmed   = previous_day_admission_pediatric_covid_confirmed_7_day_sum,
  admissionsPedsSuspected   = previous_day_admission_pediatric_covid_suspected_7_day_sum
) %>%
  # Clean all the admissions data
  mutate(across(starts_with("admissions"), cleanAdmissions)) %>%
  # Compute min/max of censored data
  mutate(
    across(
      starts_with("admissions"),
      list(
        min = admissionsMin,
        max = admissionsMax
      ),
      .names = "{.col}.{.fn}"
    )
  )
pd()

# This will remove:
#
# - Everything in Puerto Rico and other US territories
# - Seemingly, some random zip code in Arkansas
ps("Joining admissions data to HSAs")
joined <- inner_join(cleaned, select(crosswalk, zip = zipcode18, hsanum), by = 'zip')
pd()

out <- joined

ps("Writing joined admissions data to {.file {output_path}}")
write_csv(out, output_path)
pd()

