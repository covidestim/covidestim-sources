#!/usr/bin/Rscript
library(docopt)
library(cli)
suppressMessages( library(tidyverse) )

ps <- cli_process_start; pd <- cli_process_done

'Join JHU-vax-boost with Hospitalizations data for counties

Usage:
  join-case-hosp-data.R -o <path> --casedeath <path> --hosp <path> --cdcCases <path> --cdcMetadata <path> --metadata <path> [--writeMetadata <path>]
  join-case-hosp-data.R (-h | --help)
  join-case-hosp-data.R --version

Options:
  -o <path>               Path to output joined data to.
  --casedeath <path>      Path to joined case-death-rr-booster data
  --hosp <path>           Path to cleaned hospitalizations data
  --cdcCases <path>       Path to cleaned CDC data
  --cdcMetadata <path>    Path to JSON metadata for the cleaned CDC data
  --metadata <path>       Path to JSON metadata about the cases/deaths/vaccines/boost of each county
  --writeMetadata <path>  Where to save metadata about all case/death/vaccine/boost/hospi data
  -h --help               Show this screen.
  --version               Show version.

' -> doc

args <- docopt(doc, version = 'join-case-hosp-data.R 0.1')

output_path <-  args$o

cols(
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
) -> cleanedhhsSpec

cols(fips = col_character(),
     date = col_date(),
     cases = col_number()) -> cdcCols

cli_h1("Loading input data")

ps("Loading JHU case-death-vaccinated-booster data from {.file {args$casedeath}}")
case_death <- read_csv(
  args$casedeath,
  col_types = cols(
    date = col_date(),
    fips = col_character(),
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
            ## weekstart is a Sunday, date (weekend) should be a Thursday, so add 4 days to match
            fips = fips,
            hosp = admissionsAdultsConfirmed_min) %>%
  drop_na(date)
pd()

ps("Filtering rejected counties from hospitalzations data")
hosp %>% filter(fips %in% unique(case_death$fips)) -> hosp
pd()

ps("Loading CDC cases data from {.file {args$cdcCases}}")
cdcCases <- read_csv(
  args$cdcCases,
  col_types = cdcCols
)
pd()


ps("Filtering rejected counties from cdc cases data")
cdcCases %>% filter(fips %in% unique(case_death$fips)) -> cdcCases
pd()

ps("Loading metadata from {.file {args$metadata}}")
metadata <- jsonlite::read_json(args$metadata, simplifyVector = T)
pd()

ps("Loading metadata from {.file {args$cdcMetadata}}")
cdcMetadata <- jsonlite::read_json(args$cdcMetadata, simplifyVector = T)
pd()

ps("Matching week end dates")

lastCaseDates <- cdcCases %>%
  group_by(fips) %>%
  summarize(lastCaseDate = max(date, na.rm = TRUE))

firstHospDates <- hosp %>%
  group_by(fips) %>%
  summarize(firstHospDate = min(date, na.rm = TRUE))

lastHospDates <- hosp %>%
  group_by(fips) %>%
  summarize(lastHospDate = max(date, na.rm = TRUE))

fullDates <- full_join(firstHospDates,
                       lastCaseDates, 
                       by = "fips") %>%
  full_join(lastHospDates, by = "fips") %>%
  drop_na() %>%
  group_by(fips) %>%
  summarize(date = seq.Date(firstHospDate,
                            lastCaseDate,
                            by = '1 week'),
            missing_hosp = if_else(date > lastHospDate,
                               TRUE,
                               FALSE),
            .groups = 'drop') 

fullDatesJoin <- fullDates %>% select(date, fips)

pd()

ps("Checking that the date ranges match")
maxDate <- max(fullDatesJoin$date)
maxCaseDate <- max(cdcCases$date)

if(maxDate != maxCaseDate){
  stop("maxCaseDate is not equal to the max HospDate, adjust the CDC date range")
}
pd()

ps("Joining JHU-vax-boost , CDC, and hospitalizations data")

case_death %>%
  group_by(fips) %>%
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
             by = c("fips", "date")) -> case_death_join

jhu_fips <- unique(case_death_join$fips)
cdc_fips <- unique(cdcCases$fips)
hosp_fips <- unique(hosp$fips)

case_death_join %>% 
  left_join(cdcCases %>% 
              rename(cdccase = cases),
            by = c("date", "fips")) %>%
  mutate(cases = case_when(date > as.Date("2023-02-14") ~ round(cdccase),
                           TRUE ~ cases)) %>%
  dplyr::select(-cdccase) -> case_death_cdc_join


hosp %>% 
  right_join(fullDates,
             by = c("fips", "date")) %>%
  full_join(case_death_cdc_join,
            by = c("fips", "date")) %>%
  filter(fips %in% jhu_fips &
           fips %in% cdc_fips &
           fips %in% hosp_fips) -> joined

pd()

ps("Removing Nebraska counties data manually")
nebraskaClipped <- filter(
  joined,
  !(str_detect(fips, '^31'))
)

pd()
cli_h1("Processing")

ps("Replacing NA hospitalizations and deaths data with {.code 0}")
replaced <- replace_na(nebraskaClipped, list(hosp = 0, deaths = 0))
pd()


ps("Filter out counties that lack initial immunity estimates")
immNAfips <- c("16033", "31165", "31183", "46102")
replaced <- filter(replaced, !fips %in% immNAfips)
pd()

ps("Selecting variables and data after December 1 2021")
final <- replaced %>%
  select(fips, date,
         cases, deaths,
         hosp, RR,
         boost,
         missing_hosp) %>% 
  filter(date > as.Date("2021-12-01"))
pd()

ps("Filtering out counties without hospitalizations data after December 1 2021")
noHospFips <- final %>%
  group_by(fips) %>%
  summarize(noHospData = if_else(all(missing_hosp == TRUE),
                                 TRUE,
                                 FALSE)) %>%
  filter(noHospData == TRUE) %>% pull(fips)

final <- final %>% filter(! fips %in% noHospFips)
pd()

ps("Adjusting lastCaseDate and lastHospDate for Tennessee")

maxDate <- max(final$date)

lastDates <- lastHospDates %>%
  left_join(lastCaseDates, by = "fips") %>%
  mutate(lastHospDate = case_when(str_detect(fips, '^47') & lastHospDate == max(lastCaseDate) ~ lastHospDate - 7,
                                  # if the lastHospDate, that is, week ENDING in DATE is larger than the maximum date in the data
                                  # that is, the last complete week, the maxDate should be reduced by one week
                                  lastHospDate > maxDate ~ maxDate,
                                  TRUE ~ lastHospDate),
         lastCaseDate = case_when(str_detect(fips, '^47') & lastCaseDate == max(lastCaseDate) ~ lastCaseDate - 7,
                                  TRUE ~ lastCaseDate))

# checking what the current last case and last hosp dates are in the data
# checking what the current last case and last hosp dates are for Tennessee
# checking that the last data is unreliable (skip?; i.e., force filter for TN)
# writing the lastCaseDate and lastHospDate
#
pd()

ps("Sorting by fips, date")
final <- arrange(final, fips, date)
pd()

cli_h1("Writing")

ps("Writing output to {.file {args$o}}")
write_csv(final, args$o)
pd()

if (!is.null(args$writeMetadata)) {
  ps("Writing metadata to {.file {args$writeMetadata}}")
  metadata <- filter(metadata, fips %in% unique(replaced$fips)) %>%
    left_join(lastDates, by = "fips") 
  jsonlite::write_json(metadata, args$writeMetadata, null = "null")
  pd()
}
