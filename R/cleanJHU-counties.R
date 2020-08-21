#!/usr/bin/env Rscript
library(dplyr,     warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
library(stringr,   warn.conflicts = FALSE)
                    
'JHU County-data Cleaner

Usage:
  cleanJHU-counties.R -o <path> --cases <path> --deaths <path>
  cleanJHU-counties.R (-h | --help)
  cleanJHU-counties.R --version

Options:
  -o <path>             Path to output cleaned data to.
  --cases <path>        Path to the cases data 
  --deaths <path>       Path to the deaths data
  <path>                Input .csv from the JHU GitHub
  -h --help             Show this screen.
  --version             Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args   <- docopt(doc, version = 'cleanJHU-counties 0.1')

output_path <- args$o
cases_path  <- args$cases
deaths_path <- args$deaths

cols(
  FIPS = col_character()
) -> col_types.jhuCases

cols(
  FIPS = col_character()
) -> col_types.jhuDeaths

ps("Loading JHU cases data from {.file {cases_path}}")
cases <- read_csv(cases_path, col_types = col_types.jhuCases)
pd()

ps("Loading JHU deaths data from {.file {deaths_path}}")
deaths <- read_csv(deaths_path, col_types = col_types.jhuDeaths)
pd()

date_regex <- '\\d+/\\d+/\\d{2}'

reformat <- function(df, data_type = 'cases') {

  # Pivot just the columns that are dates. Name the 'value' key either 'cases'
  # or 'deaths'
  tidyr::pivot_longer(df, matches(date_regex),
                      names_to = 'date', values_to = data_type) %>%

  # Get rid of unneeded columns. The I() construct forces `data_type` to be
  # evaluated as a string, rather than being quoted
  select(date, fips = FIPS, I(data_type)) %>%

  # FIPS is unfortunately specified as a decimal number in the CSV. This hack
  # fixes that.
  mutate(fips = fips %>% as.numeric %>% as.character %>%
         str_pad(., ifelse(str_length(.) > 2, 5, 2), pad = '0')) %>%

  # Reformat the date to be consistent with other `data-products` .csv's.
  mutate_at('date', as.Date, '%m/%d/%y')
}

# Compute the diff to go from cumulative cases/deaths to incident cases/deaths.
# But, don't allow for any days to have negative case/death counts.
nonzeroDiff <- function(vec) pmax(0, vec - lag(vec, default = 0))

filterBadFips <- function(df)
  filter(df,
         !is.na(fips),                      # No invalid fips codes
         str_length(fips) == 5,             # No states or territories
         !str_detect(fips, "^800[0-5]\\d"), # The "Out of [statename]" tracts
         !str_detect(fips, "^900[0-5]\\d"), # The "Unassigned" tracts
         !str_detect(fips, "^60\\d{3}"),    # AS
         !str_detect(fips, "^66\\d{3}"),    # MP, GU
         !str_detect(fips, "^69\\d{3}"),    # MP
         !str_detect(fips, "^72\\d{3}"),    # PR
         !str_detect(fips, "^78\\d{3}"),    # VI
         !str_detect(fips, "^72999$"),      # "Unassigned" Puerto Rico
         !str_detect(fips, "^72888$"),      # "Out of" Puerto Rico
         !str_detect(fips, "^88888$"),      # Diamond Princess
         !str_detect(fips, "^99999$"))      # Grand Princess

ps("Reformatting case/death data, removing bad FIPS codes")
rcases  <- reformat(cases, 'cases')   %>% filterBadFips
rdeaths <- reformat(deaths, 'deaths') %>% filterBadFips
pd()

ps("Joining cases and deaths data")
joined <- full_join(rcases, rdeaths, by = c('fips', 'date'))
pd()

ps("Computing incidences from cumulative data")
diffed <- group_by(joined, fips) %>% arrange(date) %>%
  filter(cases > 0 | deaths > 0) %>%
  mutate_at(c('cases', 'deaths'), nonzeroDiff) %>%
  ungroup %>%
  arrange(fips)
pd()

ps("Writing cleaned data to {.file {output_path}}")
write_csv(diffed, output_path)
pd()

warnings()
