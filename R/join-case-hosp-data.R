#!/usr/bin/Rscript
library(docopt)
library(cli)
suppressMessages( library(tidyverse) )

ps <- cli_process_start; pd <- cli_process_done

'Join JHU-vax-boost with Hospitalizations data for counties

Usage:
  join-case-hosp-data.R -o <path> --casedeath <path> --hosp <path> --metadata <path> [--writeMetadata <path>]
  join-case-hosp-data.R (-h | --help)
  join-case-hosp-data.R --version

Options:
  -o <path>               Path to output joined data to.
  --casedeath <path>      Path to joined case-death-rr-booster data
  --hosp <path>           Path to cleaned hospitalizations data
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
)
pd()

ps("Loading metadata from {.file {args$metadata}}")
metadata <- jsonlite::read_json(args$metadata, simplifyVector = T)
pd()

ps("Joining JHU-vax-boost and hospitalizations data")
hosp %>% 
  rename(date = weekstart,
         hospi = admissionsAdultsConfirmed_min) %>%
  left_join(case_death %>%
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
              ungroup(), 
            by = c("fips", "date")) -> joined

pd()

cli_h1("Processing")

ps("Replacing NA hospitalizations data with {.code 0}")
replaced <- replace_na(joined, list(hospi = 0, hospi_roll = 0))
pd()

ps("Selecting variables")
final <- replaced %>%
  select(fips, date,
         cases, deaths,
         hospi, hospi_roll,
         boost)
pd()

cli_h1("Writing")

ps("Writing output to {.file {args$o}}")
write_csv(final, args$o)
pd()

if (!is.null(args$writeMetadata)) {
  ps("Writing metadata to {.file {args$writeMetadata}}")
  metadata <- filter(metadata, fips %in% unique(replaced$fips))
  jsonlite::write_json(metadata, args$writeMetadata, null = "null")
  pd()
}
