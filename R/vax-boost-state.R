#!/usr/bin/env Rscript
library(dplyr,     warn.conflicts = FALSE)
library(tidyverse, warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
library(stringr,   warn.conflicts = FALSE)
library(lubridate, warn.conflicts = FALSE)
library(purrr,     warn.conflicts = FALSE)
library(usdata,    warn.conflicts = FALSE)
library(spdep,     warn.conflicts = FALSE)
library(raster,    warn.conflicts = FALSE)

'Vax-boost State-data Cleaner

Usage:
  vax-boost-state.R -o <path> --cdcpath <path> --sttpop <path> --nbs <path>
  vax-boost-state.R (-h | --help)
  vax-boost-state.R --version

Options:
  -o <path>                 Path to output cleaned data to.
  -h --help                 Show this screen.
  --cdcpath <path>          Path to the cdc data 
  --sttpop <path>           Path to state population data
  --nbs <path>              Path to state neighbors dataframe
  --version                 Show version.

' -> doc
ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'vax-boost-state 0.1')

output_path   <- args$o
cdcpath       <- args$cdcpath
sttpop        <- args$sttpop
nbspath       <- args$nbs

cols_only(
  Date = col_date(format = "%m/%d/%Y"),
  Location = col_character(),
  Administered_Dose1_Recip = col_double(),
  Administered_Dose1_Pop_Pct = col_double(),
  Series_Complete_Yes = col_double(),
  Series_Complete_Pop_Pct = col_double(),
  Additional_Doses = col_double(),
  Additional_Doses_Vax_Pct = col_double(),
  Second_Booster_Janssen = col_double(),
  Second_Booster_Moderna = col_double(),
  Second_Booster_Pfizer = col_double(),
  Second_Booster_Unk_Manuf = col_double()  ) -> colSpec

ps("Reading cdc vaccinations and booster data by state {.file {cdcpath}}")
cdc <- read_csv(cdcpath, col_types = colSpec)
pd()

ps("Reading statepopulation file from {.file {sttpop}}")
sttpop <- read_csv(sttpop)
pd()

ps("Reading state neightbors file from {.file {nbspath}}")
nbsDF <- read_csv(nbspath)
pd()

cum_To_daily <- function(x) {
  out <- c(x[1], diff(x))
  # replace all negative or NA values by zero
  # this ensures that the cumulative boosters is continuous increasing
  # and that every date has a valid numeric value
  out[which(out < 0 | is.na(out))] <- 0
  return(out)
  }

# function to filter both unreasonable dips and peaks 
# and enforce a monotonic timeseries.
noPeaks <- function(x){
  revx <- rev(x)
  mono_bw <- revx
  mono_fw <- x
  
  #create a monotonic timeseries going forward and backward
  for(i in 2:length(x)){
    if(mono_bw[i] > mono_bw[i-1]) {mono_bw[i] <- mono_bw[i-1]}
    if(mono_fw[i] < mono_fw[i-1]) {mono_fw[i] <- mono_fw[i-1]}
  }
  
  mono_fw_rev <- rev(mono_fw)
  # moving backwards from last observation, 
  # selecting the maximum of the monotonic backwards
  # and monotonic forwards series -- if they are smaller
  # than the previous observation.
  for(i in 2:length(x)){
    revx[i] <- ifelse(mono_bw[i] <= revx[i-1],
                      ifelse(mono_fw_rev[i] <= revx[i-1],
                             max(mono_bw[i],mono_fw_rev[i])[1],
                             mono_bw[i]),
                      mono_fw_rev[i])
  }
  rev(revx)
}
ps("Transforming variables names {.file {cdcpath}}")
cdc %>% 
  transmute(
          state = Location,
          date = Date,
          first_dose_cum = Administered_Dose1_Recip,
          first_dose_cum_pct = Administered_Dose1_Pop_Pct,
          full_vax_cum = Series_Complete_Yes,
          full_vax_cum_pct = Series_Complete_Pop_Pct,
          boost_cum = Additional_Doses,
          boost_cum_pct = Additional_Doses_Vax_Pct,
          boost2_cum = Second_Booster_Janssen + Second_Booster_Moderna + Second_Booster_Pfizer + Second_Booster_Unk_Manuf) %>%
  mutate(state = usdata::abbr2state(state)) %>%
  drop_na(state) %>%
  left_join(sttpop, by = "state") %>%
  ## replace boost_cum_pct by the correct calculation 
  ## (boosters relative to full population instead of full vax)
  ## The cumulative booster percentage reported by the CDC is relative to the 
  ## fully vaccinated pouplation, whereas we want the percentage of the whole population
  ## so, replace the percentage variable with manually computed percentage
  mutate(boost_cum_pct = boost_cum / pop * 100,
         boost2_cum_pct = boost2_cum / pop * 100) %>%
  mutate(boost_cum_pct = replace_na(boost_cum_pct, 0 ),
         boost_cum = replace_na(boost_cum, 0 ),
         boost2_cum_pct = replace_na(boost2_cum_pct, 0),
         boost2_cum = replace_na(boost2_cum, 0))%>%
  group_by(state) %>%
  arrange(date) %>%
  mutate(
    first_dose_cum = noPeaks(first_dose_cum),
    first_dose_cum_pct = noPeaks(first_dose_cum_pct),
    full_vax_cum = noPeaks(full_vax_cum),
    full_vax_cum_pct = noPeaks(full_vax_cum_pct),
    boost_cum = noPeaks(boost_cum),
    boost_cum_pct = noPeaks(boost_cum_pct),
    boost2_cum = noPeaks(boost2_cum),
    boost2_cum_pct = noPeaks(boost2_cum_pct),
    first_dose_n = cum_To_daily(first_dose_cum),
    full_vax_n = cum_To_daily(full_vax_cum),
    boost_n = cum_To_daily(boost_cum),
    boost2_n = cum_To_daily(boost2_cum)) %>%
  ungroup() %>%
  drop_na() -> final
pd()

ps("Finding illegal vax/boost data and replacing with neighbors")
illegalStateFirstVax <- final %>% 
  filter(first_dose_cum > pop) %>% 
  pull(state) %>% unique

illegalStateBoost <- final %>% 
  filter(boost_cum > pop) %>% 
  pull(state) %>% unique

illegalStateBoost2 <- final %>%
  filter(boost2_cum > boost_cum) %>%
  pull(state) %>% unique

illStates <- c(illegalStateBoost, illegalStateFirstVax, illegalStateBoost2)
allStates <- unique(final$state)
goodStates <- allStates[!allStates %in% illStates]



## pivot final dataframe to long format with columns for 'type' (cum/cum_pct/n)
## and rows for 'name' of the variable (boost/full_vax/first_dose)
final %>%
  pivot_longer(-c(date,state,pop),
               names_to = c("name", "type"),
               names_pattern = "(boost2|boost|full_vax|first_dose)_(cum_pct|cum|n)") %>%
  pivot_wider(names_from = type, values_from = value) -> final_pivot

## create national average; only taking states that have no illegal input
## and rescale the outcome variables relative to population size (note, this is 
## diffferently done for percentage and count variables)
final_pivot %>%
  filter(state %in% goodStates) %>%
group_by(date, name) %>%
  summarize(n = sum(n/sum(pop)),
            cum = sum(cum/sum(pop)),
            cum_pct = sum(cum_pct * (pop/sum(pop))),
            .groups = "drop") -> nationalAvg

## create average of (valid) neighbors by origin state
final_pivot %>% 
  right_join(nbsDF %>% 
              filter(!nbs %in% illStates) %>% 
              filter(! is.na(nbs)), 
            by = c("state" = "nbs")) %>%
  group_by(date, origin, name) %>%
  summarize(n = sum(n/sum(pop)),
            cum = sum(cum/sum(pop)),
            cum_pct = sum(cum_pct * (pop/sum(pop))),
            .groups = "drop") -> nbsAvg
### this does NOT have all the states in 'state'
### specifically, states that do not have any valid neighbors
### are not present in this dataset
## which will render their n/cum/cum_pct <_nbs> NA as desired

## which states have any valid neighbords?
hasValidNbs <- nbsDF %>%
  filter(! nbs %in% illStates) %>%
  filter(! is.na(nbs)) %>%
  pull(origin) %>% unique

## append the national and neighbor averaged to the dataframe
final_pivot %>%
  left_join(nationalAvg, by = c("date", "name"),
            suffix = c("", "_nat")) %>%
  left_join(nbsAvg, by = c("date" = "date", "state" = "origin", "name" = "name"),
            suffix = c("_obs", "_nbs")) %>%
  pivot_longer(-c(state,date,pop,name),
               names_to = c("quantity", "original"),
               names_pattern = "(cum|cum_pct|n)_(obs|nbs|nat)") %>%
  pivot_wider(names_from = original,
              values_from = value) %>%
  ## replace the observed values when there are illegal data; 
  ## replace with national average if there are no valid neighbords
  ## and replace with neighbor average if there are valid neighbors
  ## note that the calculation is different for count variables and percentages
  ## in all other cases, replace with the original value.
  mutate(obs = case_when(state %in% illStates & ! state %in% hasValidNbs & quantity == "cum_pct" ~ round(nat),
                       state %in% illStates & state %in% hasValidNbs & quantity == "cum_pct" ~ round(nbs),
                       state %in% illStates & ! state %in% hasValidNbs & quantity != "cum_pct" ~ round(nat*pop),
                       state %in% illStates & state %in% hasValidNbs & quantity != "cum_pct" ~round(nbs*pop),
                       state %in% goodStates ~ obs)) %>%
  dplyr::select(state,date,pop,name,quantity,obs) %>%
  pivot_wider(names_from = c(name, quantity),
              values_from = obs)-> final_replaced


pd()



ps("Writing cleaned data to {.file {output_path}}")
write_csv(final_replaced, output_path)
pd()


