#!/usr/bin/env Rscript
suppressPackageStartupMessages( library(tidyverse) )
library(docopt, warn.conflicts = FALSE)
library(cli,    warn.conflicts = FALSE)

'HHS Hospitalizations-data per-state aggregator

Usage:
  cleanHHS-state.R -o <path> --cleanedhhs <path> --mapping <path>
  cleanHHS-state.R (-h | --help)
  cleanHHS-state.R --version

Options:
  -o <path>             Path to output cleaned data to.
  --cleanedhhs <path>   Cleaned HHS hospitalizations data, at the county level
  --mapping <path>      FIPS => STATE mapping, for aggregating FIPS to STATE
  -h --help             Show this screen.
  --version             Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'cleanHHS-state.R 0.1')

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

valueAndBoundsVariables <- c(
  valueVariables,
  paste0(valueVariables, "_min"),
  paste0(valueVariables, "_max"),
  paste0(valueVariablesWithCoverageAvailable, "_max2")
)


ps("Reading cleaned hospitalizations by county file {.file {args$cleanedhhs}}")
cleanedhhs <- read_csv(args$cleanedhhs, col_types = cleanedhhsSpec)
pd()

ps("Reading FIPS-HSA mapping file {.file {args$mapping}}")
fipsState <- read_csv(args$mapping, col_types = 'cc')
pd()

ps("Summarizing admissions by state")
admissionsByState <- cleanedhhs %>% left_join(fipsState, by = "fips") %>%
  drop_na(state) %>%
  group_by(state, weekstart) %>%
  summarize(across(all_of(valueAndBoundsVariables), sum), .groups = 'drop')
pd()

out <- admissionsByState

ps("Writing output data to {.file {output_path}}")
write_csv(out, output_path)
pd()

