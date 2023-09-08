#!/usr/bin/Rscript
library(docopt)
library(cli)
suppressMessages( library(tidyverse) )

ps <- cli_process_start; pd <- cli_process_done

'Join JHU-vax-boost with Hospitalizations data for states

Usage:
  join-state-case-hosp-data.R -o <path> --casedeath <path> --hosp <path> --cdcCases <path> --metadata <path> [--writeMetadata <path>]
  join-state-case-hosp-data.R (-h | --help)
  join-state-case-hosp-data.R --version

Options:
  -o <path>               Path to output joined data to.
  --casedeath <path>      Path to joined case-death-rr-booster data
  --hosp <path>           Path to cleaned hospitalizations data
  --cdcCases <path>       Path to cleaned CDC case data
  --metadata <path>       Path to JSON metadata about the cases/deaths/vaccines/boost of each state
  --writeMetadata <path>  Where to save metadata about all case/death/vaccine/boost/hospi data
  -h --help               Show this screen.
  --version               Show version.

' -> doc

args <- docopt(doc, version = 'join-state-case-hosp-data.R 0.1')

output_path <-  args$o

cols(
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
) -> cleanedhhsSpec


cols(state = col_character(),
     date = col_date(),
     cases = col_number()) -> cdcCols

cli_h1("Loading input data")

ps("Loading JHU case-death-vaccinated-booster data from {.file {args$casedeath}}")
case_death <- read_csv(
  args$casedeath,
  col_types = cols(
    date = col_date(),
    state = col_character(),
    cases = col_number(),
    deaths = col_number(),
    RR = col_number(),
    boost_n = col_number()
  )
)
pd()

ps("Loading hospitalizations data from {.file {args$hosp}}")
hosp <- read_csv(
  args$hosp,
  col_types = cleanedhhsSpec
) %>%
  transmute(date = weekstart + 4,
            # weekstart = a Sunday, date = the week-end should be Thursday(to match case data)
            state = state,
            hosp = admissionsAdultsConfirmed_min)
pd()
ps("Filtering out rejected states from hospitalizations data")
hosp %>% filter(state %in% unique(case_death$state)) -> hosp
pd()


ps("Loading CDC cases data from {.file {args$cdcCases}}")
cdcCases <- read_csv(
  args$cdcCases,
  col_types = cdcCols
)
pd()

ps("Filtering rejected counties from cdc cases data")
cdcCases %>% filter(state %in% unique(case_death$state)) -> cdcCases
pd()

ps("Loading metadata from {.file {args$metadata}}")
metadata <- jsonlite::read_json(args$metadata, simplifyVector = T)
pd()

ps("Matching weekstart dates")

lastCaseDates <- cdcCases %>%
  group_by(state) %>%
  summarize(lastCaseDate = max(date, na.rm = TRUE))

firstHospDates <- hosp %>%
  group_by(state) %>%
  summarize(firstHospDate = min(date, na.rm = TRUE))

lastHospDates <- hosp %>%
  group_by(state) %>%
  summarize(lastHospDate = max(date, na.rm = TRUE))

fullDates <- full_join(firstHospDates,
                       lastCaseDates, 
                       by = "state") %>%
  full_join(lastHospDates, by = "state") %>%
  drop_na() %>%
  group_by(state) %>%
  summarize(date = seq.Date(firstHospDate,
                            # choose last of case and hosp dates, to ensure latest data is used
                            max(lastCaseDate, lastHospDate),
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
firstHospDate <- min(hosp$date, na.rm = TRUE)
lastHospDate <- max(hosp$date, na.rm = TRUE)

if(! maxDate %in% seq.Date(firstHospDate, lastHospDate, by = 7)){
  stop("maxCaseDate is not in the HospDate range, check the dates and make sure the week-ends are matching")
}
pd()

ps("Joining JHU-vax-boost and hospitalizations data")

jhu_state <- unique(case_death$state)
cdc_state <- unique(cdcCases$state)
hosp_state <- unique(hosp$state)

case_death %>%
  group_by(state) %>%
  arrange(date) %>%
  ## Compute the weekly rolling sum of cases, deaths, boosters;
  ## so that no matter the observed hospitalizations date;
  ## the daily data will always be a weekly aggregate.
  ## Future implementation: make sure that any daily dates past
  ## the last weekly date; are still added into a 'lastWeek',
  ## so that estimates can still be updated daily.
  mutate(cases = c(rep(0,6), zoo::rollsum(cases, 7)),
         deaths = c(rep(0,6), zoo::rollsum(deaths, 7)),
         boost = c(rep(0,6), zoo::rollsum(boost_n, 7))
  ) %>%
  ungroup() %>%
  ## Filter the fullDates in the case_death data
  right_join(fullDatesJoin,
             by = c("state", "date")) -> case_death_join

case_death_join %>% 
  left_join(cdcCases %>% 
              rename(cdccase = cases),
            by = c("date", "state")) %>%
  mutate(cases = case_when(date > as.Date("2023-02-14") ~ round(cdccase),
                           TRUE ~ cases)) %>%
  dplyr::select(-cdccase) -> case_death_cdc_join

hosp %>% 
  right_join(fullDates,
             by = c("state", "date")) %>%
  full_join(case_death_cdc_join,
            by = c("state", "date")) %>%
  filter(state %in% jhu_state &
           state %in% cdc_state &
           state %in% hosp_state) -> joined

pd()

cli_h1("Processing")

ps("Replacing NA hospitalizations, cases and deaths data with {.code 0}")
replaced <- replace_na(joined, list(hosp = 0, deaths = 0, cases = 0))
pd()

ps("Selecting variables and data after December 1 2021")
final <- replaced %>%
  select(state, date,
         cases, deaths,
         RR,
         hosp,
         boost,
         missing_hosp) %>%
  filter(date > as.Date("2021-12-01"))
pd()

ps("Adjusting lastCaseDate and lastHospDate for Tennessee")
maxDate <- max(final$date)

lastDates <- lastCaseDates %>%
  left_join(lastHospDates, by = "state") %>%
  mutate(
    # lastCaseDate = case_when(state == "Tennessee" & lastCaseDate == max(lastCaseDate, na.rm = TRUE) ~ lastCaseDate - 7,
                          # TRUE ~ lastCaseDate),# outdated, case data is always smaller than hospitalization data
         lastHospDate = case_when(state == "Tennessee" & lastHospDate >= max(lastCaseDate, na.rm = TRUE) ~ lastHospDate - 7,
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

ps("Sorting by state, date")
final <- arrange(final, state, date)
pd()

cli_h1("Writing")

ps("Writing output to {.file {args$o}}")
write_csv(final, args$o)
pd()

if (!is.null(args$writeMetadata)) {
  ps("Writing metadata to {.file {args$writeMetadata}}")
  metadata <- filter(metadata, state %in% unique(replaced$state)) %>%
    left_join(lastDates, by = "state")
  jsonlite::write_json(metadata, args$writeMetadata, null = "null")
  pd()
}
