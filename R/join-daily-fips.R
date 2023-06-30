#!/usr/bin/Rscript
library(docopt)
library(cli)
suppressMessages( library(tidyverse) )

ps <- cli_process_start; pd <- cli_process_done

'Daily FIPS data

Usage:
  join-daily-fips.R -o <path> --jhu <path> --vaxboost <path> --rr <path> --metadataJHU <path> --rejectsJHU <path> [--covidestim <logical>] [--nyt <path>] [--rejectsNYT <path>] [--imputeNE <path>] [--statemap <path>] [--writeRejects <path>] [--writeMetadata <path>]
  join-daily-fips.R (-h | --help)
  join-daily-fips.R --version

Options:
  -o <path>               Path to output joined weekly data to
  --jhu <path>            Path to joined case-death data
  --vaxboost <path>       Path to cleaned vaccination-booster data
  --rr <path>             Path to rr data
  --metadataJHU <path>    Where metadata .json describing JHU data is stored
  --rejectsJHU <path>     Path to rejected JHU FIPS [fips, code, reason]
  --covidestim <logical>  Logical indicator: should data fit the covidestim model? By default TRUE
  --nyt <path>            (optional) Path to nyt data
  --rejectsNYT <path>     (required if nyt) Path to rejected NYT FIPS [fips, code, reason]
  --imputeNE <path>       (optional) Path to stateJHU data. If included Nebraska counties are imputed
  --statemap <path>       (required if imputeNE) Path to .csv mapping from FIPS=>state [fips, state]
  --writeRejects <path>   (optional) Path to output a .csv of rejected FIPS [fips, code, reason]   
  --writeMetadata <path>  (optional) Where to save metadata about all case/death/vaccine/boost/hospi data
  -h --help               Show this screen.
  --version               Show version.

' -> doc

args <- docopt(doc, version = 'join-daily-fips.R 0.1')

output_path <-  args$o

if(!is.null(args$covidestim)){
  is_covidestim <- as.logical(args$covidestim)
} else {
  is_covidestim <- TRUE
}

# Case and death data -----------------------------------------------------
cli_h1("Case and death data")

ps("Loading JHU case-death data from {.file {args$jhu}}")
jhu <- read_csv(
  args$jhu,
  col_types = cols(
    date = col_date(),
    fips = col_character(),
    cases = col_number(),
    deaths = col_number()
  )
)
pd()

ps("Loading JHU metadata from {.file {args$metadataJHU}}")
metadataJHU <- jsonlite::read_json(args$metadataJHU, simplifyVector = T)
pd()

ps("Loading JHU rejects .csv from {.file {args$rejectsJHU}}")
rejectsJHU <- read_csv(args$rejectsJHU, col_types = "ccc")
pd()


# NYT case and death data -------------------------------------------------


if(!is.null(args$nyt)) {
  ps("Loading NYT case-death data from {.file {args$nyt}}")
  nyt <- read_csv(args$nyt, col_types = cols(
    date = col_date(),
    fips = col_character(),
    cases = col_number(),
    deaths = col_number()
  ))
  pd()

  ps("Loading NYT metadata from {.file {args$metadataNYT}}")
  metadataNYT <- jsonlite::read_json(args$metadataNYT, simplifyVector = T)
  pd()
  
  ps("Loading NYT rejects .csv from {.file {args$rejectsNYT}}")
  rejectsNYT <- read_csv(args$rejectsNYT, col_types = "ccc")
  pd()
  
  cli_h1("ID'ing counties which are unique to NYT")
  NYTunique <- full_join(
    count(nyt, fips),
    count(jhu, fips),
    by = 'fips',
    suffix = c('.nyt', '.jhu')
  ) %>% filter(is.na(n.jhu) & !is.na(n.nyt)) %>% pull(fips)
  
  cli_h3("Unique to NYT:")
  cli_ul()
  walk(NYTunique, cli_li)
  cli_end()
  
  ps("Row binding JHU and unique NYT county data")
  casedeath <- bind_rows(
    jhu,
    filter(nyt, fips %in% NYTunique)
  )
  pd()
  
  ps("Merging metadata")
  
  metadata <- bind_rows(metadataJHU %>% mutate(dataSource = "jhu"),
                          filter( metadataNYT, fips %in% NYTunique))
                            
  pd()
  
} else {
  casedeath <- jhu
  metadata <- metadataJHU
}


# Nebraska county imputation ----------------------------------------------

if(!is.null(args$imputeNE)){
  cli_h1("Imputation of Nebraska counties")
  ps("Loading the state input data from {args$imputeNE}")
  jhuState <- read_csv(args$imputeNE, col_types = cols(
    date = col_date(),
    state = col_character(),
    cases = col_number(),
    deaths = col_number(),
    fracpos = col_number(),
    volume = col_number()))
  pd()
  
  ps("Loading FIPS-state map from {.file {args$statemap}}")
  statemap <- read_csv(
    args$statemap,
    col_types = 'cc'
  )
  pd()
  
  ps("Projecting Nebraska counties")
  
  # find the cumulative cases / deaths at state level
  nebraskaState <- jhuState %>%
    filter(state == "Nebraska") %>%
    arrange(date) %>%
    mutate(cum_case = cumsum(cases),
           cum_death = cumsum(deaths)) %>%
    filter(date == as.Date("2021-06-30"))
  
  # find cumulative cases / deaths at county level,
  # and compute ratio wrt national level
  nebraskaCounties <- filter(
    casedeath, str_detect(fips, '^31')) %>%
    group_by(fips) %>%
    arrange(date) %>%
    mutate(cum_case = cumsum(cases),
           cum_death = cumsum(deaths)) %>% 
    ungroup() %>%
    filter(date == as.Date("2021-06-30")) %>%
    mutate(rel_case = cum_case/nebraskaState$cum_case,
           rel_death = cum_death/nebraskaState$cum_death) %>%
    select(fips, rel_case, rel_death)
  
  # rename variables in state data
  state_data <- jhuState %>% filter(state == "Nebraska") %>%
    rename(case_state = cases,
           death_state = deaths) 
  
  # create projection for fips in Nebraska and after June 30 2021.
  
  allDates <- casedeath %>%
    left_join(statemap, by = "fips") %>%
    filter(state == "Nebraska") %>% 
    select(date, fips) %>%
    group_by(fips) %>%
    summarize(date = seq.Date(max(date), max(state_data$date), by = 1), .groups = 'drop') %>%
    ungroup()
  
  proj_data <- casedeath %>% 
    full_join(allDates, by = c("fips","date")) %>%
    left_join(statemap, by = "fips") %>%
    left_join(state_data, by = c("date","state")) %>%
    left_join(nebraskaCounties, by = "fips") %>%
    mutate(case_proj = if_else(str_detect(fips, "^31") & 
                                 date > as.Date("2021-06-30"),
                               case_state * rel_case,
                               cases),
           death_proj = if_else(str_detect(fips, "^31") &
                                  date > as.Date("2021-06-30"),
                                death_state * rel_death,
                                deaths),
           case_proj = round(case_proj),
           death_proj = round(death_proj)
    )
  
  # select and rename variables for writing
  final_with_projection <- proj_data %>%
    select(date, fips, case_proj, death_proj) %>%
    rename(cases = case_proj,
           deaths = death_proj)
  pd()
  
  casedeath <- final_with_projection
}

if(is_covidestim == TRUE){
ps("Removing entries after Dec 1 2021 for covidestim fitting")
casedeath <- casedeath %>%
  filter(date < as.Date("2021-12-01"))
pd()
}
# Vaccination data --------------------------------------------------------

cli_h1("Joining case-deaths and vaccination data")

ps("Loading vaccine data from {.file {args$vaxboost}}")
boost <- read_csv(
  args$vaxboost,
  col_types = cols(
    date = col_date(),
    fips = col_character(),
    boost_n = col_number(),
    first_dose_n = col_number(),
    boost_cum = col_number(),
    first_dose_cum = col_number()
  )
)
boost_ss <- boost %>%
  transmute(
    date, fips,
    boost_n, first_dose_n,
    vax_boost_n = boost_n + first_dose_n)
pd()

ps("Loading vaccine IFR adjustment data from {.file {args$rr}}")
rr <- read_csv(
  args$rr,
  col_types = cols(
    Date = col_date(),
    FIPS = col_character(),
    StateName = col_character(),
    RR = col_number()
  )) %>%
    rename(fips = FIPS,
           date = Date,
           state = StateName)

pd()

ps("Left joining casedeath, vaxboost and RR dataframes")
final <- casedeath %>% 
  left_join(boost_ss, by = c("date","fips")) %>%
  left_join(rr, by = c("date", "fips"))
pd()

cli_h1("Performing checks")

# Check to make sure each county only has non-missing RRs after the initial
# pre-vaccine-data period of NAs.
ps("No missing RRs after first non-missing RR")
NAsAfterBeginning <- final %>% group_by(fips) %>% arrange(date) %>%
  summarize(
    NAsAreOnlyAtTheBeginning = 
      # The latest date which contains an NA-valued RR
      max(date[which(is.na(RR))]) <
      # The earliest date which contains a non-missing RR
      min(date[which(!is.na(RR))])
  ) %>% filter(!NAsAreOnlyAtTheBeginning)

if (nrow(NAsAfterBeginning > 0)) {
  cli_alert_danger("There were missing RRs after the first day of vaccine data for these counties:")
  print(NAsAfterBeginning)
  quit(status = 1)
}
pd()

ps("No unrealistically high or low RRs ({.code RR<0 | RR>1.5})")
AnyUnrealisticValues <- filter(final, RR < 0 | RR > 1.5)

if (nrow(AnyUnrealisticValues) > 0) {
  cli_alert_danger("There unrealistic vaccine RR's for these counties:")
  print(AnyUnrealisticValues)
  quit(status = 1)
}
pd()

cli_h1("Processing")

ps("Replacing missing RRs with {.code 1}")
replaced <- replace_na(final, list(RR = 1))
pd()


ps("Replacing NA booster data with {.code 0}")
replaced <- replace_na(replaced, list(boost_n = 0,
                                      first_dose_n = 0,
                                      vax_boost_n = 0))
pd()

ps("Filtering illegal input data (vaccines and booster)")
## Exclude any county which reports a cumulative first_dose,
## cumulative booster dose, or single date 
illegalFipsFirstVax <- boost %>% 
  filter(first_dose_cum > pop) %>% 
  pull(fips) %>% unique

illegalFipsBoost <- boost %>% 
  filter(boost_cum > pop) %>% 
  pull(fips) %>% unique

replaced %>% 
  filter(!fips %in% illegalFipsBoost) %>%
  filter(! fips %in% illegalFipsFirstVax) -> replaced
pd()

cli_h1("Writing")

ps("Writing output to {.file {args$o}}")
write_csv(final, args$o)
pd()


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

## For later, include in metadata whether imputation has been done
if (!is.null(args$writeMetadata)) {
  ps("Writing metadata to {.file {args$writeMetadata}}")
  if(is_covidestim == TRUE){
  metadata <- metadata %>% mutate(maxInputDate = as.Date("2021-11-30"))
  }
  jsonlite::write_json(metadata, args$writeMetadata, null = "null")
  pd()
}

if (!identical(args$writeRejects, FALSE)) {
  ps("Writing rejected counties to {.file {args$writeRejects}}")
  write_csv(rejects, args$writeRejects)
  pd()
}

