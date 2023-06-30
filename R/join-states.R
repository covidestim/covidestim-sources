#!/usr/bin/Rscript
library(docopt)
library(cli)
suppressMessages( library(tidyverse) )

ps <- cli_process_start; pd <- cli_process_done

'State data

Usage:
  join-states.R -o <path> --jhu <path> [--cdc <path>] --vaxboost <path> --rr <path> [--hosp <path>] --metadataJHU <path> --rejectsJHU <path> [--covidestim <logical>] [--weekly <logical>] [--writeRejects <path>] [--writeMetadata <path>]
  join-states.R (-h | --help)
  join-states.R --version

Options:
  -o <path>               Path to output joined weekly data to
  --jhu <path>            Path to joined case-death data
  --cdc <path>            (optional) Path to cdc case data
  --hosp <path>           (optional) Path to hospitalizations data
  --vaxboost <path>       Path to cleaned vaccination-booster data
  --rr <path>             Path to rr data
  --covidestim <logical>  Logical (TRUE by default) to indicate whether data should be filtered to be suitable for covidestim run
  --weekly <logical>      Logical (TRUE by default) to indicate whether data should be aggregated to weekly level or daily level
  --metadataJHU <path>    Where metadata .json describing JHU data is stored
  --rejectsJHU <path>     Path to rejected JHU FIPS [fips, code, reason]
  --writeRejects <path>   (optional) Path to output a .csv of rejected FIPS [fips, code, reason]   
  --writeMetadata <path>  (optional) Where to save metadata about all case/death/vaccine/boost/hospi data
  -h --help               Show this screen.
  --version               Show version.

' -> doc

args <- docopt(doc, version = 'join-states.R 0.1')

output_path <-  args$o
ps("covidestim argument is {args$covidestim}")
pd()


# Design ------------------------------------------------------------------


if(!is.null(args$covidestim)){
  is_covidestim <- as.logical(args$covidestim)
} else {
  is_covidestim <- TRUE
}

if(!is.null(args$weekly)){
  is_weekly <- as.logical(args$weekly)
} else {
  is_weekly <- TRUE
}


# Column specifications ---------------------------------------------------
jhuSpec <- cols(
  date = col_date(),
  state = col_character(),
  cases = col_number(),
  deaths = col_number(),
  fracpos = col_number(),
  volume = col_number()
)

cdcSpec <- cols(state = col_character(),
                date = col_date(),
                cases = col_number())

rrSpec <- cols(
  Date = col_date(),
  FIPS = col_character(),
  StateName = col_character(),
  RR = col_number()
)

vaxSpec <- cols(
  date = col_date(),
  state = col_character(),
  boost_n = col_number(),
  first_dose_n = col_number(),
  boost_cum = col_number(),
  first_dose_cum = col_number()
)

hospSpec <- cols(
  state = col_character(),
  weekstart = col_date(format = ""),
  admissionsAdultsConfirmed = col_double(),
  admissionsAdultsSuspected = col_double(),
  admissionsPedsConfirmed = col_double(),
  admissionsPedsSuspected = col_double(),
  averageAdultInpatientsConfirmed = col_double(),
  averageAdultInpatientsConfirmedSuspected = col_double(),
  averageAdultICUPatientsConfirmed = col_double(),
  averageAdultICUPatientsConfirmedSuspected = col_double(),
  covidRelatedEDVisits = col_double(),
  
  admissionsAdultsConfirmed_min  = col_double(),
  admissionsAdultsConfirmed_max  = col_double(),
  admissionsAdultsConfirmed_max2 = col_double(),
  
  admissionsAdultsSuspected_min  = col_double(),
  admissionsAdultsSuspected_max  = col_double(),
  admissionsAdultsSuspected_max2 = col_double(),
  
  admissionsPedsConfirmed_min  = col_double(),
  admissionsPedsConfirmed_max  = col_double(),
  admissionsPedsConfirmed_max2 = col_double(),
  
  admissionsPedsSuspected_min  = col_double(),
  admissionsPedsSuspected_max  = col_double(),
  admissionsPedsSuspected_max2 = col_double(),
  
  averageAdultInpatientsConfirmed_min  = col_double(),
  averageAdultInpatientsConfirmed_max  = col_double(),
  averageAdultInpatientsConfirmed_max2 = col_double(),
  
  averageAdultInpatientsConfirmedSuspected_min  = col_double(),
  averageAdultInpatientsConfirmedSuspected_max  = col_double(),
  averageAdultInpatientsConfirmedSuspected_max2 = col_double(),
  
  averageAdultICUPatientsConfirmed_min  = col_double(), 
  averageAdultICUPatientsConfirmed_max  = col_double(), 
  averageAdultICUPatientsConfirmed_max2 = col_double(), 
  
  averageAdultICUPatientsConfirmedSuspected_min  = col_double(), 
  averageAdultICUPatientsConfirmedSuspected_max  = col_double(), 
  averageAdultICUPatientsConfirmedSuspected_max2 = col_double(), 
  
  # Note: `_coverage` variable is not available for this outcome
  covidRelatedEDVisits_min  = col_double(),
  covidRelatedEDVisits_max  = col_double()
  # covidRelatedEDVisits_max2 = col_double(),
)

# Reading in data files ---------------------------------------------------

cli_h1("Reading in data files")

cli_h2("Case and death data files")

ps("Reading in JHU data from {.file {args$jhu}}")
jhu <- read_csv(args$jhu, col_types = jhuSpec)
pd()

ps("Loading JHU metadata from {.file {args$metadataJHU}}")
metadataJHU <- jsonlite::read_json(args$metadataJHU, simplifyVector = T)
pd()

ps("Loading JHU rejects .csv from {.file {args$rejectsJHU}}")
rejectsJHU <- read_csv(args$rejectsJHU, col_types = "ccc")
pd()


if(!is.null(args$cdc)){
  ps("Reading in the CDC case data")
  cdc <- read_csv(args$cdc, col_types = cdcSpec) %>%
    rename(cdcCases = cases)
  pd()
}

cli_h2("Vaccination data")

ps("Loading vaccine data from {.file {args$vaxboost}}")
boost <- read_csv(args$vaxboost, col_types = vaxSpec) %>%
  transmute(
    date, state,
    boost_n, first_dose_n,
    vax_boost_n = boost_n + first_dose_n)
pd()

ps("Loading vaccine IFR adjustment data from {.file {args$rr}}")
rr <- read_csv(args$rr, col_types = rrSpec) %>%
  transmute(state = FIPS,
         date = Date,
         RR)
pd()

if(!is.null(args$hosp)){
  ps("Loading hospitalizations data from {.file {args$hosp}}")
  ## NOTE THAT DATE = WEEKEND HERE, because the CDC data is by week-end
  hosp <- read_csv(args$hosp, col_types = hospSpec) %>%
    transmute(date = weekstart + 6,
              state = state,
              hosp = admissionsAdultsConfirmed_min) %>%
    drop_na(date)
  pd()
  
}

# Creating the data --------------------------------------------------

cli_h1("Joining the data sources")

  ps("JHU case data")
  joined <- jhu
  metadata <- metadataJHU %>% mutate(dataSource = "jhu")
  pd()
 
# Weekly / CDC inclusion? -------------------------------------------------

if(!is.null(args$cdc)){
  
  ps("Joining the daily and weekly data")
  joined <- joined %>%
    full_join(cdc, by = c("state", "date")) %>%
    mutate(cases = case_when(date > as.Date("2023-02-14") ~ cdcCases,
                             TRUE ~ cases))
  pd()
  
}

minCompleteDate <- min(joined$date)
maxCompleteDate <- max(joined$date)

# Joining hospitalization data --------------------------------------------


if(!is.null(args$hosp)){
  
  ps("Joining hospitalizations data and casedeath data")
  joined <- joined %>% 
    full_join(hosp, by = c("date", "state")) 
  pd()
  
  maxCompleteDate <- min(maxCompleteDate, max(hosp$date))

}

# Joining vaxxincation data  -------------------------------------------------------

ps("Left joining casedeath, vaxboost and RR dataframes")
joined <- joined %>% 
  full_join(boost, by = c("date","state")) %>%
  full_join(rr, by = c("date", "state"))
pd()

maxCompleteDate <- min(maxCompleteDate, max(boost$date), max(rr$date))
dailyVaxDates <- seq(min(boost$date), max(boost$date), by = 1)
maxDailyDate <- dailyVaxDates[which(! dailyVaxDates %in% unique(boost$date))[1]]

# Filtering to desired settings -------------------------------------------

filtered <- joined 

# Aggregating to weekly data ----------------------------------------------

if(is_weekly == TRUE){
  
  ps("Matching week end dates")
  
  lastCaseDates <- cdc %>%
    group_by(state) %>%
    summarize(lastCaseDate = max(date, na.rm = TRUE))
  lastHospDates <- hosp %>%
    group_by(state) %>%
    summarize(lastHospDate = max(date, na.rm = TRUE))
  lastVaxDates <- boost %>%
    group_by(state) %>%
    summarize(lastVaxDate = max(date, na.rm = TRUE))
  
  firstCaseDates <- jhu %>% 
    group_by(state) %>%
    summarize(firstCaseDate = min(date, na.rm = TRUE))
  firstHospDates <- hosp %>%
    group_by(state) %>%
    summarize(firstHospDate = min(date, na.rm = TRUE))
  
  fullDates <- full_join(firstHospDates,
                         firstCaseDates, 
                         by = "state") %>%
    full_join(lastVaxDates, by = "state") %>%
    full_join(lastHospDates, by = "state") %>%
    full_join(lastCaseDates, by = "state") %>%
    mutate(firstDate = case_when(firstHospDate > firstCaseDate ~ firstHospDate,
                                 TRUE ~ firstCaseDate),
           lastDate = case_when(lastHospDate > lastCaseDate &
                                  lastVaxDate > lastCaseDate ~ lastCaseDate,
                                lastHospDate > lastVaxDate &
                                  lastCaseDate > lastVaxDate ~ lastVaxDate,
                                lastCaseDate > lastHospDate &
                                  lastVaxDate > lastHospDate ~ lastHospDate),
           firstDate = case_when(firstDate < lastDate ~ firstDate)) %>%
    drop_na() %>%
    group_by(state) %>%
    summarize(date = seq.Date(firstDate,
                              lastDate,
                              by = '1 week'),
              missing_hosp = if_else(date > lastHospDate,
                                     TRUE,
                                     FALSE),
              .groups = 'drop') 
  
  fullDatesJoin <- fullDates %>% select(date, state)
  
  pd()
  
  ps("Checking that the date ranges match")
  maxDate <- max(fullDatesJoin$date)
  maxCaseDate <- max(cdcCases$date)
  
  if(maxDate != maxCaseDate){
    stop("maxCaseDate is not equal to the max HospDate, adjust the CDC date range")
  }
  pd()
  
  cli_h1("Aggregating to weekly data")
  
  filtered <- filtered %>%
    group_by(state) %>%
    arrange(date) %>%
    ## Compute the weekly rolling sum of cases, deaths, boosters;
    mutate(cases = c(rep(0,6), zoo::rollsum(cases, 7)),
           deaths = c(rep(0,6), zoo::rollsum(deaths, 7)),
           boost = c(rep(0,6), zoo::rollsum(boost_n, 7)),
           hosp = c(rep(0,6), zoo::rollsum(hosp, 7)),
           vax_boost = c(rep(0,6), zoo::rollsum(vaxboost_n, 7)),
           first_dose = c(rep(0,6), zoo::rollsum(first_dose_n, 7)),
    ) %>%
    ungroup() %>%
    ## Filter the fullDates in the case_death data
    right_join(fullDatesJoin,
               by = c("state", "date"))
} else {
  filtered <- filtered
}

# Filtering data for covidestim window ------------------------------------
# Defining and extracting min and max dates --------------------------------------------

if(is_covidestim == TRUE){
  if(is_weekly == TRUE){
    minDate = as.Date("2021-12-01")
    maxDate = maxCompleteDate
  } else {
    minDate = minCompleteDate
    maxDate = as.Date("2021-12-01")
  }
} else {
  minDate = minCompleteDate
  if(is_weekly == TRUE){
    maxDate = max(joined$date)
  } else {
    maxDate = maxDailyDate
  }
}

cli_h2("Subsetting data to appropriate timewindow for covidestim output")

filtered <- filtered %>%
  filter(date >= minDate & date < maxDate) 


# Final processing --------------------------------------------------------
cli_h1("Processing")

final <- filtered

# Remove illegal, invalid or excluded counties ----------------------------

if(is_covidestim == TRUE) {
 
    ps("Replacing NA values with {.code 0} and selecting variables")
  final <- replace_na(final, list(deaths = 0, boost = 0, vaxboost = 0, first_dose = 0))
  pd()
  
  if(is_weekly == TRUE) {
    final <- replace_na(final, list(hosp = 0)) %>%
      dplyr::select(state, date,
                    cases, deaths,
                    hosp, RR,
                    boost = vaxboost,
                    missing_hosp)
    
  } else {
    final <- final %>% select(state, date,
                              cases, deaths,
                              boost, vaxboost, first_dose, RR)
  }
  
  pd()
  
}

cli_h1("Writing")

ps("Writing output to {.file {args$o}}")
write_csv(final, args$o)
pd()

# For later : adjust the metadata to actually have the max

### FOr later: check the Tennessee code for the covidestim runs, and confirm all the metadata gets output correctly
### For later: change the required name for covidestim variable from boost to vaxboost, to remain consistent naming

if (!is.null(args$writeMetadata)) {
  
  ps("Adjusting lastCaseDate and lastHospDate for Tennessee")
  maxDate <- max(final$date)
  
  lastDates <- lastCaseDates %>%
    left_join(lastHospDates, by = "state") %>%
    mutate(lastCaseDate = case_when(state == "Tennessee" & lastCaseDate == max(lastCaseDate, na.rm = TRUE) ~ lastCaseDate - 7,
                                    TRUE ~ lastCaseDate),
           lastHospDate = case_when(state == "Tennessee" & lastHospDate == max(lastCaseDate, na.rm = TRUE) ~ lastHospDate - 7,
                                    # if the lastHospDate, that is, week ENDING in DATE is larger than the maximum date in the data
                                    # that is, the last complete week, the maxDate should be reduced by one week
                                    lastHospDate > maxDate ~ maxDate,
                                    TRUE ~ lastHospDate))
  
  
  # checking what the current last case and last hosp dates are in the data
  # checking what the current last case and last hosp dates are for Tennessee
  # checking that the last data is unreliable (skip?; i.e., force filter for TN)
  # writing the lastCaseDate and lastHospDate
  #
  pd()
  
  ps("Writing metadata to {.file {args$writeMetadata}}")
  metadata <- metadata %>% mutate(maxObservedInputDate = maxInputDate,
                                  maxInputDate = min(c(maxInputDate,as.Date("2021-12-31")))) %>%
    left_join(lastDates)
  jsonlite::write_json(metadata, args$writeMetadata, null = "null")
  pd()
}

