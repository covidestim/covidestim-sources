#!/usr/bin/Rscript
library(docopt)
library(cli)
suppressMessages( library(tidyverse) )

ps <- cli_process_start; pd <- cli_process_done

'JHU County-data / Booster-data Joiner

Usage:
  join-JHU-vaccines-boost.R -o <path> --jhuVax <path> --boost <path> --metadata <path> [--writeRejects <path>] [--writeMetadata <path>]
  join-JHU-vaccines-boost.R (-h | --help)
  join-JHU-vaccines-boost.R --version

Options:
  -o <path>               Path to output joined data to.
  --jhuVax <path>         Path to joined JHU-vaccinated county-level data
  --boost <path>          Path to cleaned booster data
  --metadata <path>       Path to JSON metadata about the cases/deaths/vaccines of each county
  --writeRejects <path>   Path to output a .csv of rejected FIPS [fips, code, reason]
  --writeMetadata <path>  Where to save metadata about all case/death/vaccine/boost data
  -h --help               Show this screen.
  --version               Show version.

' -> doc

args <- docopt(doc, version = 'join-JHU-vaccines-boost.R 0.1')
rejects_path      <- args$writeRejects

cli_h1("Loading input data")

ps("Loading JHU case-death-vaccinated data from {.file {args$jhuVax}}")
jhu_vax <- read_csv(
  args$jhuVax,
  col_types = cols(
    date = col_date(),
    fips = col_character(),
    cases = col_number(),
    deaths = col_number(),
    RR = col_number()
  )
)
pd()

ps("Loading vaccine data from {.file {args$boost}}")
boost <- read_csv(
  args$boost,
  col_types = cols(
    date = col_date(),
    fips = col_character(),
    boost_n = col_number(),
    first_dose_n = col_number(),
    boost_cum_pop = col_number(),
    first_dose_cum_pop = col_number()
  )
) %>%
  mutate(boost_n_old = boost_n,
         boost_n = boost_n + first_dose_n)
pd()

ps("Loading metadata from {.file {args$metadata}}")
metadata <- jsonlite::read_json(args$metadata, simplifyVector = T)
pd()


ps("Joining JHU-vax and boost data")
left_join(
  jhu_vax,
  select(boost, date, fips, boost_n),
  by = c("date", "fips")
) -> joined
pd()

cli_h1("Processing")

ps("Replacing NA booster data with {.code 0}")
replaced <- replace_na(joined, list(boost_n = 0))
pd()

ps("Filtering illegal input data (vaccines and booster)")
## Exclude any county which reports a cumulative first_dose,
## cumulative booster dose, or single date 
illegalFipsFirstVax <- boost %>% 
  filter(first_dose_cum_pop > pop) %>% 
  pull(fips) %>% unique

illegalFipsBoost <- boost %>% 
  filter(boost_cum_pop > pop) %>% 
  pull(fips) %>% unique

replaced %>% 
  filter(!fips %in% illegalFipsBoost) %>%
  filter(! fips %in% illegalFipsFirstVax) -> replaced
pd()

cli_h1("Writing")

ps("Writing output to {.file {args$o}}")
write_csv(replaced, args$o)
pd()

if (!is.null(args$writeMetadata)) {
  ps("Writing metadata to {.file {args$writeMetadata}}")
  metadata <- filter(metadata, fips %in% unique(replaced$fips))
  jsonlite::write_json(metadata, args$writeMetadata, null = "null")
  pd()
}

rejects <- tibble(
  fips = illegalFipsBoost,
  code = 'ILL_BOOST',
  reason = "Illegal booster data"
)

rejects <- bind_rows(rejects, tibble(
  fips = illegalFipsFirstVax,
  code = 'ILL_FIRST_VAX',
  reason = "Illegal first vaccination data"
))

if (!identical(args$writeRejects, FALSE)) {
  ps("Writing rejected counties to {.file {rejects_path}}")
  write_csv(rejects, rejects_path)
  pd()
}
