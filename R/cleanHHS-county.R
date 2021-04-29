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
#   o = "test.csv",
#   cleanedhhs = "../data-products/hhs-hospitalizations-by-facility.csv", 
#   mapping = "../data-sources/fips-hsa-mapping.csv"
# )

output_path <-  args$o

cols_only(
  hospital_pk = col_character(),
  zip = col_character(),
  date = col_date(format = ""),
  admissionsAdultsConfirmed = col_double(),
  admissionsAdultsSuspected = col_double(),
  admissionsPedsConfirmed = col_double(),
  admissionsPedsSuspected = col_double(),

  # These are columns generated in `cleanHHS-facility.R` which assume that
  # censored values resolve to either the minimum or maximum of their range
  # (the range being 1-3 admissions in a week). We won't process these here
  # because it's only the above four variables which are imputed. In fact, the
  # commented variables below may not even exist!

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

ps("Computing admissions by HSA")
admissionsByHHS <- cleanedhhs %>% group_by(hsanum, date) %>%
  summarize(across(starts_with("admissions"), sum), .groups = "drop")
pd()

ps("Computing per-county admissions using FIPS => HSA mappings")
admissionsByFIPS <- fipsMapping %>%
  inner_join(admissionsByHHS, by = c("hsa" = "hsanum")) %>%
  group_by(fips, date) %>%
  summarize(
    admissionsAdultsSuspected = sum(admissionsAdultsSuspected * proportion),
    admissionsAdultsConfirmed = sum(admissionsAdultsConfirmed * proportion),
    admissionsPedsSuspected   = sum(admissionsPedsSuspected * proportion),
    admissionsPedsConfirmed   = sum(admissionsPedsConfirmed * proportion),
    .groups = "drop"
  )
pd()

out <- admissionsByFIPS

ps("Writing output data to {.file {output_path}}")
write_csv(out, output_path)
pd()

