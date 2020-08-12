library(dplyr,     warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
                    
'NYTimes County-data Cleaner

Usage:
  cleanNYT-counties.R -o <path> <path>
  cleanNYT-counties.R (-h | --help)
  cleanNYT-counties.R --version

Options:
  -o <path>             Path to output cleaned data to.
  <path>                Input .csv from the NYTimes GitHub
  -h --help             Show this screen.
  --version             Show version.

' -> doc

arguments   <- docopt(doc, version = 'cleanNYT-counties 0.1')

input_path  <- arguments$path
output_path <- arguments$o

cols_only(
  date   = col_date(format = '%Y-%m-%d'),
  county = col_character(),
  state  = col_character(),
  fips   = col_character(),
  cases  = col_number(),
  deaths = col_number()
) -> col_types.nytimes

cli_process_start("Loading NYTimes data from {.file {input_path}}")
nytimes <- read_csv(input_path, col_types = col_types.nytimes)
cli_process_done()

# Filter out any areas that don't have a fips code and aren't the "merged" NYC
# synthetic FIPS. This is detailed on the NYTimes GitHub geogrpahic exceptions
# page.
nytimes <- filter(nytimes, !is.na(fips) || county == 'New York City')
nytimes <- mutate(nytimes, fips = ifelse(county == 'New York City', "00000", fips))

cli_process_start("Computing marginal cases and removing negative values")
nytimes <- group_by(nytimes, fips) %>%
  mutate_at(c('cases', 'deaths'), ~. - lag(., 1, default = 0)) %>%
  mutate_at(c('cases', 'deaths'), pmax, 0)
cli_process_done()

nytimes <- select(nytimes, date, fips, cases, deaths)

badFIPS <- group_by(nytimes, fips) %>%
  summarize(n=n(), min_date = min(date), max_date = max(date),
            validDateRange = n-1 == as.double(difftime(max_date, min_date)),
            noNAs = !any(is.na(cases) | is.na(deaths))) %>%
  filter(!validDateRange | !noNAs) %>%
  pull(fips)

cli_alert_info("Removed {length(badFIPS)} bad FIPS codes")

filtered <- filter(nytimes, !(fips %in% badFIPS), !is.na(fips))

write_csv(filtered, output_path)

cli_alert_success("Wrote cleaned data to {.file {output_path}}")

warnings()
