#!/usr/bin/Rscript
library(docopt)
library(cli)
suppressMessages( library(tidyverse) )

ps <- cli_process_start; pd <- cli_process_done

'FIPS data

Usage:
  join-fips.R -o <path> --jhu <path> [--cdc <path>] --vaxboost <path> --rr <path> [--hosp <path>] [--covidestim <logical>] [--weekly <logical>] --metadataJHU <path> --rejectsJHU <path> [--nyt <path>] [--metadataNYT <path>] [--rejectsNYT <path>] [--imputeNE <path>] [--statemap <path>] [--writeRejects <path>] [--writeMetadata <path>]
  join-fips.R (-h | --help)
  join-fips.R --version

Options:
  -o <path>               Path to output joined weekly data to
  --jhu <path>            Path to joined case-death data
  --cdc <path>            (optional) Path to cdc case data
  --vaxboost <path>       Path to cleaned vaccination-booster data
  --rr <path>             Path to rr data
  --hosp <path>           (optional) Path to hospitalizations data
  --covidestim <logical>  Logical (TRUE by default) to indicate whether data should be filtered to be suitable for covidestim run
  --weekly <logical>      Logical (TRUE by default) to indicate whether data should be aggregated to weekly level or daily level
  --metadataJHU <path>    Where metadata .json describing JHU data is stored
  --rejectsJHU <path>     Path to rejected JHU FIPS [fips, code, reason]
  --nyt <path>            (optional) Path to nyt data
  --metadataNYT <path>    Where metadata .json describing NYT data is stored
  --rejectsNYT <path>     (required if nyt) Path to rejected NYT FIPS [fips, code, reason]
  --imputeNE <path>       (optional) Path to stateJHU data. If included Nebraska counties are imputed
  --statemap <path>       (required if imputeNE) Path to .csv mapping from FIPS=>state [fips, state]
  --writeRejects <path>   (optional) Path to output a .csv of rejected FIPS [fips, code, reason]   
  --writeMetadata <path>  (optional) Where to save metadata about all case/death/vaccine/boost/hospi data
  -h --help               Show this screen.
  --version               Show version.

' -> doc

args <- docopt(doc, version = 'join-fips.R 0.1')

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
  fips = col_character(),
  cases = col_number(),
  deaths = col_number()
)

nytSpec <- cols(
  date = col_date(),
  fips = col_character(),
  cases = col_number(),
  deaths = col_number())

cdcSpec <- cols(fips = col_character(),
                date = col_date(),
                cases = col_number())

stateSpec <- cols(
  date = col_date(),
  state = col_character(),
  cases = col_number(),
  deaths = col_number(),
  fracpos = col_number(),
  volume = col_number())

rrSpec <- cols(
  Date = col_date(),
  FIPS = col_character(),
  StateName = col_character(),
  RR = col_number()
)

vaxSpec <- cols(
  date = col_date(),
  fips = col_character(),
  boost_n = col_number(),
  first_dose_n = col_number(),
  boost_cum = col_number(),
  first_dose_cum = col_number()
)

hospSpec <- cols(
  fips = col_character(),
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

if(!is.null(args$nyt)) {
  ps("Loading NYT case-death data from {.file {args$nyt}}")
  nyt <- read_csv(args$nyt, col_types = nytSpec)
  pd()
  
  ps("Loading NYT metadata from {.file {args$metadataNYT}}")
  metadataNYT <- jsonlite::read_json(args$metadataNYT, simplifyVector = T)
  pd()
  
  ps("Loading NYT rejects .csv from {.file {args$rejectsNYT}}")
  rejectsNYT <- read_csv(args$rejectsNYT, col_types = "ccc")
  pd()
}

if(!is.null(args$cdc)){
  ps("Reading in the CDC case data")
  cdc <- read_csv(args$cdc, col_types = cdcSpec) %>%
    rename(cdcCases = cases)
  pd()
}

if(!is.null(args$imputeNE)){
  ps("Loading the state input data from {args$imputeNE}")
  jhuState <- read_csv(args$imputeNE, col_types = stateSpec)
  pd()
  
  ps("Loading FIPS-state map from {.file {args$statemap}}")
  statemap <- read_csv(args$statemap, col_types = 'cc')
  pd()
}

cli_h2("Vaccination data")

ps("Loading vaccine data from {.file {args$vaxboost}}")
boost <- read_csv(args$vaxboost, col_types = vaxSpec) %>%
  transmute(
    date, fips,
    boost_n, first_dose_n,
    vax_boost_n = boost_n + first_dose_n)
pd()

ps("Loading vaccine IFR adjustment data from {.file {args$rr}}")
rr <- read_csv(args$rr, col_types = rrSpec) %>%
  rename(fips = FIPS,
         date = Date,
         state = StateName)
pd()

if(!is.null(args$hosp)){
  ps("Loading hospitalizations data from {.file {args$hosp}}")
  ## NOTE THAT DATE = WEEKEND HERE, because the CDC data is by week-end
  hosp <- read_csv(args$hosp, col_types = hospSpec) %>%
    transmute(date = weekstart + 6,
              fips = fips,
              hosp = admissionsAdultsConfirmed_min) %>%
    drop_na(date)
  pd()
  
}

# Creating the data --------------------------------------------------

cli_h1("Joining the data sources")

if(is.null(args$nyt)) {
  
  ps("JHU case data")
  joined <- jhu
  metadata <- metadataJHU %>% mutate(dataSource = "jhu")
  pd()
  
} else {
  
  cli_h1("ID'ing counties which are unique to NYT")
  NYTunique <- full_join(
    count(nyt, fips),
    count(jhu, fips),
    by = 'fips',
    suffix = c('.nyt', '.jhu')
  ) %>% filter(is.na(n.jhu) & !is.na(n.nyt)) %>% pull(fips)
  
  cli_h3("Unique to NYT:")
  cli_ul()
  walk(NYTunique, cli_li)
  cli_end()
  
  ps("Row binding JHU and unique NYT county data")
  joined <- bind_rows(
    jhu,
    filter(nyt, fips %in% NYTunique)
  )
  pd()
  
  ps("Merging metadata")
  metadata <- bind_rows(metadataJHU %>% mutate(dataSource = "jhu"),
                        filter( metadataNYT, fips %in% NYTunique))
  pd()
  
} 

# Nebraska imputation? ----------------------------------------------------
if(!is.null(args$imputeNE)){
  
  cli_h1("Imputation of Nebraska counties")
  
  ps("Projecting Nebraska counties")
  # find the cumulative cases / deaths at state level
  nebraskaState <- jhuState %>%
    filter(state == "Nebraska") %>%
    arrange(date) %>%
    mutate(cum_case = cumsum(cases),
           cum_death = cumsum(deaths)) %>%
    filter(date == as.Date("2021-06-30"))
  
  # find cumulative cases / deaths at county level,
  # and compute ratio wrt national level
  nebraskaCounties <- filter(
    joined, str_detect(fips, '^31')) %>%
    group_by(fips) %>%
    arrange(date) %>%
    mutate(cum_case = cumsum(cases),
           cum_death = cumsum(deaths)) %>% 
    ungroup() %>%
    filter(date == as.Date("2021-06-30")) %>%
    mutate(rel_case = cum_case/nebraskaState$cum_case,
           rel_death = cum_death/nebraskaState$cum_death) %>%
    select(fips, rel_case, rel_death)
  
  # rename variables in state data
  state_data <- jhuState %>% filter(state == "Nebraska") %>%
    rename(case_state = cases,
           death_state = deaths) 
  
  # create projection for fips in Nebraska and after June 30 2021.
  
  allDates <- joined %>%
    left_join(statemap, by = "fips") %>%
    filter(state == "Nebraska") %>% 
    select(date, fips) %>%
    group_by(fips) %>%
    summarize(date = seq.Date(max(date), max(state_data$date), by = 1), .groups = 'drop') %>%
    ungroup()
  
  proj_data <- joined %>% 
    full_join(allDates, by = c("fips","date")) %>%
    left_join(statemap, by = "fips") %>%
    left_join(state_data, by = c("date","state")) %>%
    left_join(nebraskaCounties, by = "fips") %>%
    mutate(case_proj = if_else(str_detect(fips, "^31") & 
                                 date > as.Date("2021-06-30"),
                               case_state * rel_case,
                               cases),
           death_proj = if_else(str_detect(fips, "^31") &
                                  date > as.Date("2021-06-30"),
                                death_state * rel_death,
                                deaths),
           case_proj = round(case_proj),
           death_proj = round(death_proj)
    )
  
  # select and rename variables for writing
  final_with_projection <- proj_data %>%
    select(date, fips, case_proj, death_proj) %>%
    rename(cases = case_proj,
           deaths = death_proj)
  pd()
  
  joined <- final_with_projection
}

completeFips <- unique(joined$fips)

cli_h1("Joining the data sources")
# Weekly / CDC inclusion? -------------------------------------------------
if(!is.null(args$cdc)){
  
  ps("Joining the daily and weekly data")
  joined <- joined %>%
    full_join(cdc, by = c("fips", "date")) %>%
    mutate(cases = case_when(date > as.Date("2023-02-14") ~ cdcCases,
                             TRUE ~ cases))
  pd()
  
  completeFips <- completeFips[completeFips %in% unique(cdc$fips)]
  
}

minCompleteDate <- min(joined$date)
maxCompleteDate <- max(joined$date)

# Joining hospitalization data --------------------------------------------


if(!is.null(args$hosp)){
  
  ps("Joining hospitalizations data and casedeath data")
  joined <- joined %>% 
    full_join(hosp, by = c("date", "fips")) 
  pd()
  
  maxCompleteDate <- min(maxCompleteDate, max(hosp$date))
  completeFips <- completeFips[completeFips %in% unique(hosp$fips)]
  
}

# Joining vaccincation data  -------------------------------------------------------

ps("Left joining casedeath, vaxboost and RR dataframes")
joined <- joined %>% 
  full_join(boost, by = c("date","fips")) %>%
  full_join(rr, by = c("date", "fips"))
pd()

maxCompleteDate <- min(maxCompleteDate, max(boost$date), max(rr$date))
dailyVaxDates <- seq(min(boost$date), max(boost$date), by = 1)
maxDailyDate <- dailyVaxDates[which(! dailyVaxDates %in% unique(boost$date))[1]]
completeFips <- completeFips[completeFips %in% unique(boost$fips)]

# Filtering to desired settings -------------------------------------------

filtered <- joined 

# Aggregating to weekly data ----------------------------------------------

if(is_weekly == TRUE){
  
  ps("Matching week end dates")
  
  lastCaseDates <- cdc %>%
    group_by(fips) %>%
    summarize(lastCaseDate = max(date, na.rm = TRUE))
  lastHospDates <- hosp %>%
    group_by(fips) %>%
    summarize(lastHospDate = max(date, na.rm = TRUE))
  lastVaxDates <- boost %>%
    group_by(fips) %>%
    summarize(lastVaxDate = max(date, na.rm = TRUE))
  
  firstCaseDates <- jhu %>% 
    group_by(fips) %>%
    summarize(firstCaseDate = min(date, na.rm = TRUE))
  firstHospDates <- hosp %>%
    group_by(fips) %>%
    summarize(firstHospDate = min(date, na.rm = TRUE))
  
  fullDates <- full_join(firstHospDates,
                         firstCaseDates, 
                         by = "fips") %>%
    full_join(lastVaxDates, by = "fips") %>%
    full_join(lastHospDates, by = "fips") %>%
    full_join(lastCaseDates, by = "fips") %>%
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
    group_by(fips) %>%
    summarize(date = seq.Date(firstDate,
                              lastDate,
                              by = '1 week'),
              missing_hosp = if_else(date > lastHospDate,
                                     TRUE,
                                     FALSE),
              .groups = 'drop') 
  
  fullDatesJoin <- fullDates %>% select(date, fips)
  
  pd()
  
  # ps("Checking that the date ranges match")
  # maxDate <- max(fullDatesJoin$date)
  # maxCaseDate <- max(cdc$date)
  # 
  # if(maxDate != maxCaseDate){
  #   stop("maxCaseDate is not equal to the max HospDate, adjust the CDC date range")
  # }
  # pd()
  # 
  cli_h1("Aggregating to weekly data")
  
  filtered <- filtered %>%
    group_by(fips) %>%
    arrange(date) %>%
    ## Compute the weekly rolling sum of cases, deaths, boosters;
    mutate(cases = c(rep(0,6), zoo::rollsum(cases, 7)),
           deaths = c(rep(0,6), zoo::rollsum(deaths, 7)),
           boost = c(rep(0,6), zoo::rollsum(boost_n, 7)),
           hosp = c(rep(0,6), zoo::rollsum(hosp, 7)),
           vax_boost = c(rep(0,6), zoo::rollsum(vax_boost_n, 7)),
           first_dose = c(rep(0,6), zoo::rollsum(first_dose_n, 7)),
    ) %>%
    ungroup() %>%
    ## Filter the fullDates in the case_death data
    right_join(fullDatesJoin,
               by = c("fips", "date"))
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
  filter(date >= minDate & date < maxDate) %>%
  filter(fips %in% completeFips)


# Final processing --------------------------------------------------------
cli_h1("Processing")

final <- filtered

# Remove illegal, invalid or excluded counties ----------------------------

if(is_covidestim == TRUE) {
  ps("Removing Nebraska counties data manually")
  final <- filter(final, !(str_detect(fips, '^31')))
  pd()
  
  ps("Filter out counties that lack initial immunity estimates")
  immNAfips <- c("16033", "31165", "31183", "46102")
  final <- filter(final, !fips %in% immNAfips)
  pd()
  
  ps("Replacing NA values with {.code 0} and selecting variables")
  final <- replace_na(final, list(deaths = 0, boost = 0, vax_boost = 0, first_dose = 0))
  
  if(is_weekly == TRUE) {
    final <- replace_na(final, list(hosp = 0)) %>%
      dplyr::select(fips, date,
                    cases, deaths,
                    hosp, RR,
                    boost = vax_boost,
                    missing_hosp)
    
    ps("Filtering out counties without hospitalizations data after December 1 2021")
    noHospFips <- final %>%
      group_by(fips) %>%
      summarize(noHospData = if_else(all(missing_hosp == TRUE),
                                     TRUE,
                                     FALSE)) %>%
      filter(noHospData == TRUE) %>% pull(fips)
    
    final <- final %>% filter(! fips %in% noHospFips)
    pd()
    
  } else {
    final <- final %>% select(fips, date,
                              cases, deaths, RR,
                              boost, vax_boost, first_dose)
  }
  
  pd()
  
}

cli_h1("Writing")

ps("Writing output to {.file {args$o}}")
write_csv(final, args$o)
pd()

# For later : adjust the metadata to actually have the max


if (!is.null(args$writeMetadata)) {
  ps("Writing metadata to {.file {args$writeMetadata}}")
  metadata <- metadata %>% mutate(maxObservedInputDate = maxInputDate,
                                  maxInputDate = min(c(maxInputDate,as.Date("2021-12-31")))) 
  jsonlite::write_json(metadata, args$writeMetadata, null = "null")
  pd()
}

