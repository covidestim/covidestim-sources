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

args <- docopt(doc, version = 'cleanHHS.R 0.1')

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
  geocoded_hospital_address = col_character(),
  hhs_ids = col_character(),
  is_corrected = col_logical()
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
cleanCensored <- function(v) case_when(
  is.na(v)     ~ as.numeric(NA),
  v == -999999 ~ -999999,
  v < 0        ~ as.numeric(NA), # Assume any non-999999 negative numbers are nonsensical
  TRUE         ~ v # Default case
)

# Computes min/max for censored data
censoredMin <- function(v) ifelse(v == -999999, 1, v)
censoredMax <- function(v) ifelse(v == -999999, 3, v)

prefixes <- c("admissions", "averageAdult", "covidRelated")

valueVariables <- c(
  "admissionsAdultsConfirmed",
  "admissionsAdultsSuspected",
  "admissionsPedsConfirmed",
  "admissionsPedsSuspected",
  "averageAdultInpatientsConfirmed",
  "averageAdultInpatientsConfirmedSuspected",
  "averageAdultICUPatientsConfirmed",
  "averageAdultICUPatientsConfirmedSuspected",
  "covidRelatedEDVisits"
)

# The "covid-related ED visits" outcome doesn't have coverage available -
# maybe it's a weekly report and not reported to HHS on a daily basis. So,
# we can't compute the `_max2` outcome on this, because there was apparently
# only "one" report.
valueVariablesWithCoverageAvailable <- c(
  "admissionsAdultsConfirmed",
  "admissionsAdultsSuspected",
  "admissionsPedsConfirmed",
  "admissionsPedsSuspected",
  "averageAdultInpatientsConfirmed",
  "averageAdultInpatientsConfirmedSuspected",
  "averageAdultICUPatientsConfirmed",
  "averageAdultICUPatientsConfirmedSuspected"
  # "covidRelatedEDVisits"
)

# See note above.
valueAndBoundsVariables <- c(
  valueVariables,
  paste0(valueVariables, "_min"),
  paste0(valueVariables, "_max"),
  paste0(valueVariablesWithCoverageAvailable, "_max2")
)

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
  admissionsPedsSuspected   = previous_day_admission_pediatric_covid_suspected_7_day_sum,

  # Number of reports for a particular outcome received in a particular week.
  admissionsAdultsConfirmed_nobs = previous_day_admission_adult_covid_confirmed_7_day_coverage,
  admissionsAdultsSuspected_nobs = previous_day_admission_adult_covid_suspected_7_day_coverage,
  admissionsPedsConfirmed_nobs   = previous_day_admission_pediatric_covid_confirmed_7_day_coverage,
  admissionsPedsSuspected_nobs   = previous_day_admission_pediatric_covid_suspected_7_day_coverage,

  # HHS Definition:
  #
  # Average number of patients currently hospitalized in an adult inpatient bed
  # who have laboratory-confirmed COVID-19, including those in observation
  # beds. This average includes patients who have both laboratory-confirmed
  # COVID-19 and laboratory-confirmed influenza.
  averageAdultInpatientsConfirmed = total_adult_patients_hospitalized_confirmed_covid_7_day_avg,
  averageAdultInpatientsConfirmed_nobs = total_adult_patients_hospitalized_confirmed_covid_7_day_coverage,

  averageAdultInpatientsConfirmedSuspected = total_adult_patients_hospitalized_confirmed_and_suspected_covid_7_day_avg,
  averageAdultInpatientsConfirmedSuspected_nobs = total_adult_patients_hospitalized_confirmed_and_suspected_covid_7_day_coverage,

  # HHS Definition:
  #
  # Average number of patients currently hospitalized in a designated adult ICU
  # bed who have laboratory-confirmed COVID-19. Including patients who have
  # both laboratory-confirmed COVID-19 and laboratory-confirmed influenza in
  # this field reported in the 7-day period.
  averageAdultICUPatientsConfirmed = staffed_icu_adult_patients_confirmed_covid_7_day_avg,
  averageAdultICUPatientsConfirmed_nobs = staffed_icu_adult_patients_confirmed_covid_7_day_coverage,
  
  averageAdultICUPatientsConfirmedSuspected = staffed_icu_adult_patients_confirmed_and_suspected_covid_7_day_avg,
  averageAdultICUPatientsConfirmedSuspected_nobs = staffed_icu_adult_patients_confirmed_and_suspected_covid_7_day_coverage,
  
  # HHS Definition:
  #
  # Sum of total number of ED visits who were seen on the previous calendar day
  # who had a visit related to COVID-19 (meets suspected or confirmed
  # definition or presents for COVID diagnostic testing – do not count patients
  # who present for pre-procedure screening) reported in 7-day period.
  covidRelatedEDVisits = previous_day_covid_ED_visits_7_day_sum,
) %>%
  # Clean all the admissions data
  mutate(across(all_of(valueVariables), cleanCensored)) %>%
  # Compute min/max of censored data
  mutate(
    across(
      all_of(valueVariables),
      list(
        min = censoredMin,
        max = censoredMax
      ),
      .names = "{.col}_{.fn}"
    )
  ) %>%
  # Compute max2
  #
  # If there are six reports in a week, for the purposes of this analysis,
  # we will assume that those six reports are for only six days, and the 
  # seventh day's data just never gets reported. The `_max2` variable is an
  # estimation of what the outcome would be if the "missing" days were filled
  # in with the average rate of admissions.
  mutate(
    admissionsAdultsConfirmed_max2 = 
      admissionsAdultsConfirmed_max * 7/admissionsAdultsConfirmed_nobs,
    admissionsAdultsSuspected_max2 = 
      admissionsAdultsSuspected_max * 7/admissionsAdultsSuspected_nobs,
    admissionsPedsConfirmed_max2 = 
      admissionsPedsConfirmed_max * 7/admissionsPedsConfirmed_nobs,
    admissionsPedsSuspected_max2 = 
      admissionsPedsSuspected_max * 7/admissionsPedsSuspected_nobs,

    # These two have already been averaged by HHS over the number of 
    # reports they got that week so it's pointless to apply our methodology
    # to thse two quantities - these are the only two quantities tht are
    # averages.
    averageAdultInpatientsConfirmed_max2 = averageAdultInpatientsConfirmed_max,
    averageAdultICUPatientsConfirmed_max2 = averageAdultICUPatientsConfirmed_max,

    averageAdultInpatientsConfirmedSuspected_max2 = averageAdultInpatientsConfirmedSuspected_max,
    averageAdultICUPatientsConfirmedSuspected_max2 = averageAdultICUPatientsConfirmedSuspected_max,
  ) %>%
  # We don't need the `_nobs` variables anymore
  select(-ends_with("_nobs"))
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
  mutate_at(vars(all_of(valueAndBoundsVariables)), weekToDay)

##############################################################################
##                     END OF WEEK => DAY CONVERSION                        ##
##############################################################################

out <- byday

ps("Writing joined admissions data to {.file {output_path}}")
write_csv(out, output_path)
pd()

