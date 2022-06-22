#!/usr/bin/Rscript
library(docopt)
library(cli)
suppressMessages( library(tidyverse) )

ps <- cli_process_start; pd <- cli_process_done

'JHU State-data / Booster-data Joiner

Usage:
  join-state-JHU-vaccines-boost.R -o <path> --jhuVax <path> --boost <path> --metadata <path> [--writeMetadata <path>]
  join-state-JHU-vaccines-boost.R (-h | --help)
  join-state-JHU-vaccines-boost.R --version

Options:
  -o <path>               Path to output joined data to.
  --jhuVax <path>        Path to joined JHU-vaccinated state-level data
  --boost <path>          Path to cleaned booster data
  --metadata <path>       Path to JSON metadata about the cases/deaths/vaccines of each state
  --writeMetadata <path>  Where to save metadata about all case/death/vaccine/boost data
  -h --help               Show this screen.
  --version               Show version.

' -> doc

args <- docopt(doc, version = 'join-state-JHU-vaccines-boost.R 0.1')

cli_h1("Loading input data")

ps("Loading JHU case-death-vaccinated data from {.file {args$jhuVax}}")
jhu_vax <- read_csv(
  args$jhuVax,
  col_types = cols(
    date = col_date(),
    state = col_character(),
    cases = col_number(),
    deaths = col_number(),
    RR = col_number(),
    fracpos = col_number(),
    volume = col_number()
  )
)
pd()

ps("Loading vaccine data from {.file {args$boost}}")
boost <- read_csv(
  args$boost,
  col_types = cols(
    date = col_date(),
    state = col_character(),
    boost_n = col_number(),
    first_dose_n = col_number()
  )
) %>%
  mutate(boost_n = boost_n + first_dose_n)
pd()

ps("Loading metadata from {.file {args$metadata}}")
metadata <- jsonlite::read_json(args$metadata, simplifyVector = T)
pd()

ps("Joining JHU-vax and boost data")
left_join(
  jhu_vax,
  select(boost, date, state, boost_n),
  by = c("date", "state")
) -> joined
pd()

cli_h1("Processing")

ps("Replacing NA booster data with {.code 0}")
replaced <- replace_na(joined, list(boost_n = 0))
pd()

cli_h1("Writing")

ps("Writing output to {.file {args$o}}")
write_csv(replaced, args$o)
pd()

if (!is.null(args$writeMetadata)) {
  ps("Writing metadata to {.file {args$writeMetadata}}")
  metadata <- filter(metadata, state %in% unique(replaced$state))
  jsonlite::write_json(metadata, args$writeMetadata, null = "null")
  pd()
}
