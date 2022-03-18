#!/usr/bin/env Rscript
suppressPackageStartupMessages( library(tidyverse) )
library(docopt, warn.conflicts = FALSE)
library(cli,    warn.conflicts = FALSE)
                    
'HHS Hospitalizations-data per-county aggregator

Usage:
  cleanHHS.R -o <path> --cleanedhhs <path> --mapping <path>
  cleanHHS.R (-h | --help)
  cleanHHS.R --version

Options:
  -o <path>             Path to output cleaned data to.
  --cleanedhhs <path>   Cleaned HHS hospitalizations data, at the facility level
  --mapping <path>      FIPS => HSA mapping, for splitting HSAs up according to population
  -h --help             Show this screen.
  --version             Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'cleanHHS-county.R 0.1')

# Fake args for debugging/development
# args <- list(
#   cleanedhhs = "../data-products/hhs-hospitalizations-by-facility.csv", 
#   hsapolygons = "../data-sources/hsa-shapefile/HsaBdry_AK_HI_unmodified.shp", 
#   cbgpolygons = "../data-sources/cb_2019_us_bg_500k/cb_2019_us_bg_500k.shp", 
#   cbgpop = "../data-sources/population_by_cbg.csv",
# )

output_path <-  args$o

cols(
  hospital_pk = col_character(),
  hospital_name = col_character(),
  zip = col_character(),
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
  covidRelatedEDVisits_max  = col_double(),
  # covidRelatedEDVisits_max2 = col_double(),

  hsanum = col_double()
) -> cleanedhhsSpec

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

ps("Reading cleaned HHS hospital admission file {.file {args$cleanedhhs}}")
cleanedhhs <- read_csv(args$cleanedhhs, col_types = cleanedhhsSpec)
pd()

ps("Reading FIPS-HSA mapping file {.file {args$mapping}}")
fipsMapping <- read_csv(args$mapping, col_types = 'cnn')
pd()

censoredSum <- function(v) ifelse(-999999 %in% v, -999999, sum(v))

ps("Computing admissions by HSA")
admissionsByHHS <- cleanedhhs %>% group_by(hsanum, weekstart) %>%
  summarize(across(all_of(valueAndBoundsVariables), censoredSum), .groups = 'drop')
pd()

rescaleFacilitiesForWeek <- function(outcome, proportion)
  ifelse(outcome == -999999, -999999, outcome * proportion)

ps("Computing per-county admissions using FIPS=>HSA mappings")
admissionsByFIPS <- fipsMapping %>%
  left_join(admissionsByHHS, by = c("hsa" = "hsanum")) %>%
  group_by(fips, weekstart) %>%
  mutate(
    across(
      all_of(valueAndBoundsVariables),
      ~rescaleFacilitiesForWeek(.x, proportion)
    )
  ) %>%
  summarize(across(all_of(valueAndBoundsVariables), censoredSum), .groups = 'drop') %>%
  mutate(across(all_of(valueAndBoundsVariables), round))
pd()

out <- admissionsByFIPS

ps("Writing output data to {.file {output_path}}")
write_csv(out, output_path)
pd()

