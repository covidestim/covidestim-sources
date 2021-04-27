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
  # admissionsPedsConfirmed = col_double(),
  # admissionsPedsSuspected = col_double(),
  # admissionsAdultsConfirmed.min = col_double(),
  # admissionsAdultsConfirmed.max = col_double(),
  # admissionsAdultsSuspected.min = col_double(),
  # admissionsAdultsSuspected.max = col_double(),
  # admissionsPedsConfirmed.min = col_double(),
  # admissionsPedsConfirmed.max = col_double(),
  # admissionsPedsSuspected.min = col_double(),
  # admissionsPedsSuspected.max = col_double(),
  hsanum = col_double()
) -> cleanedhhsSpec

ps("Reading cleaned HHS hospital admission file {.file {args$cleanedhhs}}")
cleanedhhs <- read_csv(args$cleanedhhs, col_types = cleanedhhsSpec)
pd()

ps("Reading FIPS-HSA mapping file {.file {args$mapping}}")
fipsMapping <- read_csv(args$mapping, col_types = 'cnn')
pd()

censoredSum <- function(v) ifelse(-999999 %in% v, -999999, sum(v))

ps("Computing admissions by HSA")
admissionsByHHS <- cleanedhhs %>% group_by(hsanum, weekstart) %>%
  summarize(across(starts_with("admissions"), censoredSum)) %>%
  ungroup
pd()

ps("Computing per-county admissions using FIPS=>HSA mappings")
admissionsByFIPS <- fipsMapping %>%
  left_join(admissionsByHHS, by = c("hsa" = "hsanum")) %>%
  group_by(fips, weekstart) %>%
  summarize(across(starts_with("admissions"), censoredSum)) %>%
  ungroup
pd()

out <- admissionsByFIPS

ps("Writing output data to {.file {output_path}}")
write_csv(out, output_path)
pd()

