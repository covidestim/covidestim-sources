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
  --hhs <path>          Path to HHS dataset, available online as "COVID-19 Reported Patient Impact and Hospital Capacity by Facility"
  -h --help             Show this screen.
  --version             Show version.

' -> doc

# Shorthand for important CLI package functions
ps <- cli_process_start
pd <- cli_process_done

args   <- docopt(doc, version = 'cleanHHS.R 0.1')

# Fake args for debugging/development
# args <- list(
#   o = 'DELTEEME',
#   crosswalk = "../data-sources/ZipHsaHrr18.csv",
#   hhs = "../hhs_tmp.csv"
# )

output_path    <- args$o
crosswalk_path <- args$crosswalk
hhs_path       <- args$hhs

# These are the "atypical" columns that we get from calling the `healthdata.gov`
# API. The remaining columns contain the admissions data, and are numeric.
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
  col_types = 'ccccccc' # (all characters)
)
pd()

ps("Reading HHS file {.file {hhs_path}}")
hhs <- read_csv(
  hhs_path,
  col_types = hhsSpec
)
pd()

# Any negative number that is not -999999 is coerced to NA
# (-999999 is the code used for numbers which fall between 1-3)
cleanAdmissions <- function(v) case_when(
  is.na(v)     ~ as.numeric(NA),
  v == -999999 ~ -999999,
  v < 0        ~ as.numeric(NA), # Assume any non-999999 negative numbers are nonsensical
  TRUE         ~ v # Default case
)

# Computes min/max for censored data
admissionsMin <- function(v) ifelse(v == -999999, 1, v)
admissionsMax <- function(v) ifelse(v == -999999, 3, v)

ps("Cleaning admissions data")
cleaned <- transmute(
  hhs,
  hospital_pk, hospital_name, # Facility uid and name
 
  # Fix non-5-digit zips (there are a bunch of these)
  zip = str_pad(zip, width = 5, side = 'left', pad = '0'), 

  # Rename
  weekstart = collection_week,

  # These are the only four outcomes we care about for now, here they are given
  # simpler names.
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

# Because this uses an inner join rather than a left join, this operation
# will remove:
#
# - Everything in Puerto Rico and other US territories (because the crosswalk file lacks them)
# - Seemingly, some random zip code in Arkansas (might be an invalid zip code)
ps("Joining admissions data to HSAs")
joined <- inner_join(cleaned, select(crosswalk, zip = zipcode18, hsanum), by = 'zip')
pd()

##############################################################################
##                  BEGINNING OF WEEK => DAY CONVERSION                     ##
##############################################################################

# These next few lines are just an example. In reality, they probably aren't
# appropriate, because moving from week=>day will increase the number of rows
# in the `tibble` which doesn't work when using dplyr::mutate

# Dummy functions
weekToDay <- function(v) {
  # 'v' is a numeric vector containing admissions data, by week.

  # For now, return v unmodified
  v
}

byday <- group_by(joined, hospital_pk) %>%
  mutate_at(vars(starts_with("admissions")), ~weekToDay(.))

##############################################################################
##                     END OF WEEK => DAY CONVERSION                        ##
##############################################################################

out <- byday

ps("Writing joined admissions data to {.file {output_path}}")
write_csv(out, output_path)
pd()

