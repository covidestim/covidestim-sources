#!/usr/bin/env Rscript
library(dplyr,     warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
                    
'JHU County-data Cleaner

Usage:
  cleanJHU-counties.R -o <path> --cases <path> --deaths <path>
  cleanJHU-counties.R (-h | --help)
  cleanJHU-counties.R --version

Options:
  -o <path>             Path to output cleaned data to.
  --cases <path>        Path to the cases data 
  --deaths <path>       Path to the deaths data
  <path>                Input .csv from the NYTimes GitHub
  -h --help             Show this screen.
  --version             Show version.

' -> doc

args   <- docopt(doc, version = 'cleanJHU-counties 0.1')

output_path <- args$o
cases_path  <- args$cases
deaths_path <- args$deaths

cols_only(
  # Fill me in
) -> col_types.jhuCases

cols_only(
  # Fill me in
) -> col_types.jhuDeaths

cli_process_start("Loading JHU cases data from {.file {cases_path}}")
cases <- read_csv(cases_path, col_types = col_types.jhuCases)
cli_process_done()

cli_process_start("Loading JHU deaths data from {.file {deaths_path}}")
deaths <- read_csv(deaths_path, col_types = col_types.jhuDeaths)
cli_process_done()

# ...

write_csv(filtered, output_path)

cli_alert_success("Wrote cleaned data to {.file {output_path}}")

warnings()
