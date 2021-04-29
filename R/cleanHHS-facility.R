#!/usr/bin/env Rscript
suppressPackageStartupMessages( library(tidyverse) )
library(docopt, warn.conflicts = FALSE)
library(cli,    warn.conflicts = FALSE)

require(imputeTS)
require(tempdisagg)
                    
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
#   hhs = "../data-sources/hhs-hospitalizations-by-week.csv"
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

cli_h1("Loading input data")

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

cli_h1("Data cleaning")

ps("Row-level cleaning of admissions data")
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

ps("Identifying implicitly missing weeks for each facility")
# Sometimes, a facility has a missing week (implicitly missing - it's just
# not in the data). To get around this, `allWeeksEachFacilityShouldHave`
# contains a row for each week every facility "should" have. This operates
# on the assumption that a perfect dataset would have a report from every
# facility for each week between the first week reported and the last week
# reported.
allWeeksEachFacilityShouldHave <- cleaned %>%
  group_by(hospital_pk, zip) %>%
  summarize(
    weekstart = seq.Date(
      min(weekstart), max(weekstart), by = '1 week'
    ),
    .groups = 'drop'
  )

# When you left-join `allWeeksEachFacilityShouldHave` to the cleaned tibble,
# you make the missingness explicit because there will be NA-valued admissions
# introduced when there is no corresponding record for a particular week for
# a particular facility.
withImplicitlyMissingWeeks <- left_join(
  allWeeksEachFacilityShouldHave,
  cleaned,
  by = c("hospital_pk", "zip", "weekstart")
)
pd()
nImplicitlyMissing <- nrow(withImplicitlyMissingWeeks) - nrow(cleaned)
cli_alert_warning("{nImplicitlyMissing} implicity missing weeks are now tagged with {.code NA}")

ps("Selecting facilities with >=2 observations")
# A facility can only used if all of its admissions variables have at least
# two weeks where there are non-NA values. Otherwise a spline cannot
# be constructed.
onlyFacilitiesWithAtLeastTwoObservations <- withImplicitlyMissingWeeks %>%
  group_by(hospital_pk) %>%
  filter(
    if_all(
      starts_with("admissions"), # All admissions varialbes
      ~sum(is.na(.)) < n() - 1   # At least two non-missing observations
    )
  )
pd()

nWithTooMuchMissingness <-
  length(unique(withImplicitlyMissingWeeks$hospital_pk)) -
    length(unique(onlyFacilitiesWithAtLeastTwoObservations$hospital_pk))
cli_alert_warning("{nWithTooMuchMissingness} facilities removed for having too much missingness")

# Because this uses an inner join rather than a left join, this operation
# will remove:
#
# - Everything in Puerto Rico and other US territories (because the crosswalk file lacks them)
# - Seemingly, some random zip code in Arkansas (might be an invalid zip code)
ps("Joining admissions data to HSAs")
joined <- inner_join(
  onlyFacilitiesWithAtLeastTwoObservations,
  select(crosswalk, zip = zipcode18, hsanum),
  by = 'zip'
)
pd()

##############################################################################
##                  BEGINNING OF WEEK => DAY CONVERSION                     ##
##############################################################################

# These next few lines are just an example. In reality, they probably aren't
# appropriate, because moving from week=>day will increase the number of rows
# in the `tibble` which doesn't work when using dplyr::mutate

# Quick function to compute the week total of daily observations
weeksum <- function(x) unname(tapply(x, (seq_along(x)-1)%/%7, sum)) 

# Poisson likelihood + spline function
PLL <- function(par, spline_mat, DATA){
  pred_hosp_d <- exp(as.numeric(spline_mat%*%par)) # predicted daily hospitalizations
  pred_hosp_w <- weeksum(pred_hosp_d) # weeksums
  DATA[is.na(DATA)] <- round(pred_hosp_w[is.na(DATA)]) # impute NA values with modelled weeksums
  LL <- -sum(dpois(DATA, pred_hosp_w, log = TRUE)) # evaluate likelihood
  return(LL)
}

#week to day function
legacyWeekToDay <- function(v){

  nweeks <- length(v)
  v[v == -999999] <- 2 # replace censored values with 2 
  n_spl <- 10

  # use a natural cubic spline to constrain second derivative at the margins to be 0
  spline_mat <- as.matrix(
    as.data.frame(
      splines::ns(1:(nweeks*7), df = n_spl, intercept = TRUE)
    )
  )

  nruns <- 10
  inits <- optims <- vector("list", nruns)
  vals <- vector(length = nruns)
  set.seed(123)
  
  #optimize over the Poisson likelihood function
  for(i in 1:nruns){
    inits[[i]] <- rnorm(n_spl)

    optims[[i]] <- optim(
      inits[[i]],
      PLL,
      DATA = v, spline_mat = spline_mat, 
      method = "BFGS",
      control = list(maxit = 1000)
    )

    vals[i] <- optims[[i]]$value
  }

  # use the parameters from the maximum optimization run
  res <- exp(
    as.numeric(
      spline_mat %*% optims[[which(vals == max(vals))[1]]]$par
    )
  )

  return(res)

  # res <- as.data.frame(cbind(v, matrix(res, nrow = nweeks, byrow = TRUE)))
  # colnames(res) <- c("sum", paste0("Day", 1:7))
  # return(res)
}

# function to disaggregate weekly to daily data
# censored data are replaced with a default value of 2
# NA values are imputed using a natural spline interpolation
# daily values are created using the denton cholette method
# which minimized the sum of second order differences
# from the weekly observations 

weekToDay <- function(v){
  
  v[which(v==-999999)] <- 2 
  v <- ts(v, start = 1)
  
  # imputa NA values
  v <- imputeTS::na_interpolation(v, option = "spline", method =  "natural")
  v[which(v < 0 )] <- 0 # force negative values to be 0
  
  # create daily values
  v <- predict(
    tempdisagg::td(
      v ~ 1,
      conversion = "sum", # Maintain a consistent weekly sum
      to = 7, 
      method = "denton-cholette",
      h = 2
    )
  )

  v[which(v < 0)] <- 0 # force negative values to be 0
  
  return(v)
}

cli_h1("Imputing per-facility weekly admissions and moving from week=>day")

nfacilities <- unique(joined$hospital_pk) %>% length

# In reverse order because of display issues
sb4 <- cli_status("{symbol$arrow_right} [4/4] Confirmed peds (0%) 0/{nfacilities}")
sb3 <- cli_status("{symbol$arrow_right} [3/4] Suspected peds (0%) 0/{nfacilities}")
sb2 <- cli_status("{symbol$arrow_right} [2/4] Confirmed adults (0%) 0/{nfacilities}")
sb1 <- cli_status("{symbol$arrow_right} [1/4] Suspected adults (0%) 0/{nfacilities}")
totalRuntime <- 0

CLIWeekToDay <- function(..., name, sb, id) {
  start <- Sys.time()
  result <- weekToDay(...)

  dt <- as.numeric(Sys.time() - start)
  totalRuntime <<- totalRuntime + dt
  meanRuntime <- totalRuntime / id
  cli_status_update(id = sb, "{symbol$arrow_right} {name} ({scales::percent(id/nfacilities)}) {id}/{nfacilities}, mean time {prettyunits::pretty_sec(meanRuntime)}")

  if (id == nfacilities) {
    cli_status_clear()
    cli_alert_success("{name} (100%)")
    totalRuntime <<- 0
  }

  result
}

# Impute and convert to per-day representation
byday <- group_by(joined, hospital_pk) %>%
  arrange(weekstart) %>%
  summarize(
    zip = first(zip),
    date = seq.Date(
      min(weekstart),
      max(weekstart) + lubridate::days(6),
      by = '1 day'
    ),
    admissionsAdultsSuspected = CLIWeekToDay(admissionsAdultsSuspected, name="[1/4] Suspected adults", sb=sb1, id=cur_group_id()),
    admissionsAdultsConfirmed = CLIWeekToDay(admissionsAdultsConfirmed, name="[2/4] Confirmed adults", sb=sb2, id=cur_group_id()),
    admissionsPedsSuspected = CLIWeekToDay(admissionsPedsSuspected, sb=sb3, name="[3/4] Suspected peds", id=cur_group_id()),
    admissionsPedsConfirmed = CLIWeekToDay(admissionsPedsConfirmed, sb=sb4, name="[4/4] Confirmed peds", id=cur_group_id()),
    hsanum = first(hsanum),
    .groups = "drop"
  )

##############################################################################
##                     END OF WEEK => DAY CONVERSION                        ##
##############################################################################

cli_h1("Writing output data")

# force new columns into the data.frame
out <- byday

ps("Writing joined admissions data to {.file {output_path}}")
write_csv(out, output_path)
pd()

