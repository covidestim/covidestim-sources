library(lubridate, warn.conflicts = FALSE)
library(ggplot2,   warn.conflicts = FALSE)
library(dplyr,     warn.conflicts = FALSE)
library(readr,     warn.conflicts = FALSE)
library(docopt,    warn.conflicts = FALSE)
library(magrittr,  warn.conflicts = FALSE)
library(cli,       warn.conflicts = FALSE)
                    
'CTP Cleaner

Usage:
  cleanCTP.R -o <path> [--graphs <path>] <path>
  cleanCTP.R (-h | --help)
  cleanCTP.R --version

Options:
  -o <path>             Path to output cleaned data to.
  --graphs <path>       File to save .pdf of data-related figures to
  -h --help             Show this screen.
  --version             Show version.

' -> doc

arguments   <- docopt(doc, version = 'CTP Cleaner 0.1')

input_path  <- arguments$path
output_path <- arguments$o
graphs_path <- arguments$graphs

cols_only(
  date                     = col_date(format = '%Y%m%d'),
  state                    = col_character(),
  positive                 = col_number(),
  negative                 = col_number(),
  pending                  = col_number(),
  hospitalizedCurrently    = col_number(),
  hospitalizedCumulative   = col_number(),
  inIcuCurrently           = col_number(),
  inIcuCumulative          = col_number(),
  onVentilatorCurrently    = col_number(),
  onVentilatorCumulative   = col_number(),
  recovered                = col_number(),
  dataQualityGrade         = col_character(),
  lastUpdateEt             = col_datetime(format = '%m/%d/%Y %H:%M'),
  hash                     = col_character(),
  death                    = col_number(),
  hospitalized             = col_number(),
  total                    = col_number(),
  totalTestResults         = col_number(),
  posNeg                   = col_number(),
  fips                     = col_number(),
  deathIncrease            = col_number(),
  hospitalizedIncrease     = col_number(),
  negativeIncrease         = col_number(),
  positiveIncrease         = col_number(),
  totalTestResultsIncrease = col_number()
) -> col_types.covidtracking

cli_alert_info("Loading CTP data from {.file {input_path}}")
cli_process_start("Loading CTP data from {.file {input_path}}")
CTP_loaded <- read_csv(input_path, col_types = col_types.covidtracking)
cli_process_done()

# Reverse dataframe
CTP_data <- CTP_loaded[nrow(CTP_loaded):1, ]

# Lubridate date
CTP_data$date <- ymd(CTP_data$date)

c(
  "AS" = "American Samoa",
  "PR" = "Puerto Rico",
  "GU" = "Guam",
  "VI" = "Virgin Islands",
  "MP" = "Northern Mariana Islands"
) -> excluded_states

statesMap <- c(state.name, "District of Columbia")
names(statesMap) <- c(state.abb, "DC")

CTP_data <- dplyr::filter(CTP_data, ! state %in% names(excluded_states))
CTP_data <- dplyr::mutate(CTP_data, state = statesMap[state])
state_names <- unique(CTP_data$state)

##################################
##                              ##
##   Clean & Prepare the data   ##
##                              ##
##################################

# Initialize a dataframe to hold all the results
CTP_cleaned <-
  data.frame(
    date                                  = as.Date(character()),
    state                                 = character(),
    cum_cases                             = double(),
    cum_totalTests                        = double(),
    cum_deaths                            = double(),
    daily_casesFilled                     = double(),
    daily_deathsFilled                    = double(),
    daily_fractionPositive                = double(),
    daily_fractionPositive_15dayMovingAvg = double(),
    stringsAsFactors                      = FALSE
  )

# Iterate through each state to clean data and add smoothed fraction positive
cli_process_start("Applying moving average to states")
for (i in 1:length(state_names)) {

  state_name <- state_names[i]

  c(
    "date"             = "date",
    "state"            = "state",
    "positive"         = "cum_cases",
    "totalTestResults" = "cum_totalTests",
    "death"            = "cum_deaths"
  ) -> name_mapping
  
  # Initialize a temporary dataframe
  temp_data           <- CTP_data[which(CTP_data$state == state_names[i]), ]
  temp_data           <- temp_data[, names(name_mapping)]
  colnames(temp_data) <- name_mapping
  
  # For days in which the daily difference is below zero (for example, a data
  # audit resulting in a downward revision of the cumulative count), we adjust
  # the difference of that and subsequent days to zero until the cumulative
  # count rises above the previous maximum cumulative count, such that the
  # cumulative count increasesd monotonically.
  cum_cases  <- c(0, temp_data$cum_cases)
  cum_deaths <- c(0, temp_data$cum_deaths)
  for (i in 2:length(cum_cases)) {
    cum_cases[i]  <- max(cum_cases[1:i], na.rm = T)
    cum_deaths[i] <- max(cum_deaths[1:i], na.rm = T)
  }
  temp_data$daily_casesFilled  <- diff(cum_cases)
  temp_data$daily_deathsFilled <- diff(cum_deaths)

  ####################
  ##                ##
  ## MOVING AVERAGE ##
  ##                ##
  ####################
  
  # calculate the crude daily incidence, total teaths, and deaths from 
  # cumulative data
  daily_cases      <- diff(c(0, temp_data$cum_cases))
  daily_totalTests <- diff(c(0, temp_data$cum_totalTests))

  # Prepare positives by censoring counts from days in which daily cases
  # are less than 1
  daily_cases[which(daily_cases < 0)] <- NA
  
  # Prepare total tests by censoring counts from days in which daily total tests
  # are less than 1 or if daily cases are greater than daily total tests
  problem_indices <- which(
    daily_totalTests < 0 |
      (daily_cases > daily_totalTests)
  )
  daily_totalTests[problem_indices] <- NA

  # Compute the 15-day moving average
  daily_case_15dayMovingAvg       <- rep(NA, nrow(temp_data))
  daily_totalTests_15dayMovingAvg <- rep(NA, nrow(temp_data))
  for (k in 1:nrow(temp_data)) {
    startIdx <- max(1, k - 7)
    endIdx   <- min(nrow(temp_data), k + 7)
    Idxs     <- startIdx:endIdx
    daily_case_15dayMovingAvg[k]       <- mean(daily_cases[Idxs], na.rm=T)
    daily_totalTests_15dayMovingAvg[k] <- mean(daily_totalTests[Idxs], na.rm=T)
  }
  
  # Calculate raw fraction positive
  temp_data$daily_fractionPositive <-
    daily_cases / daily_totalTests

  temp_data$daily_totalTests <- tidyr::replace_na(daily_totalTests, 0)

  # Calculate smooth fraction positive from moving average
  temp_data$daily_fractionPositive_15dayMovingAvg <-
    daily_case_15dayMovingAvg / daily_totalTests_15dayMovingAvg

  # For any days in which the fifteen-day moving average of positive tests was
  # is greater than or equal to the fifteen-day moving average of total tests,
  # we use the fraction positive computed from the previous days' moving
  # averages, allowing us to accommodate data from states that report negative
  # tests on a weekly or biweekly basis. For the first
  # day, if the moving avg. of cases is greater than or equal to the moving avg
  # of the total number of tests, set the fraction positive to the max value of
  # 0.9.
  temp_data$daily_fractionPositive_15dayMovingAvg[1] <-
    ifelse(
      daily_case_15dayMovingAvg[1] >=
        daily_totalTests_15dayMovingAvg[1],
      0.9,
      temp_data$daily_fractionPositive_15dayMovingAvg[1]
    )
  for (j in 2:(nrow(temp_data))) {
    if (daily_case_15dayMovingAvg[j] >=
        daily_totalTests_15dayMovingAvg[j]) {

      temp_data$daily_fractionPositive_15dayMovingAvg[j] <-
        temp_data$daily_fractionPositive_15dayMovingAvg[j - 1]
    }
  }
  
  # Cap the moving average at 0.9
  temp_data$daily_fractionPositive_15dayMovingAvg <-
    ifelse(
      temp_data$daily_fractionPositive_15dayMovingAvg > 0.90,
      0.9,
      temp_data$daily_fractionPositive_15dayMovingAvg
    )

  ######################
  ##                  ##
  ## Correct bad data ##
  ##                  ##
  ######################

  # Colorado has a few NA testing-volume entries in their first few days
  if (identical(state_name, 'Colorado'))
    temp_data <- filter(temp_data, date > as.Date("2020-03-11"))

  #####################
  ##                 ##
  ## BUILD DATAFRAME ##
  ##                 ##
  #####################

  CTP_cleaned <- rbind(CTP_cleaned, temp_data)
  
  rm(
    name_mapping, temp_data, cum_cases, cum_deaths, daily_cases,
    daily_totalTests, problem_indices, startIdx, endIdx, Idxs,
    daily_case_15dayMovingAvg, daily_totalTests_15dayMovingAvg
  )
  
}
cli_process_done()

###################
##               ##
## WRITE THE csv ##
##               ##
###################

# The variables that will be part of the cleaned data
c(
  "date"                                  = "date",
  "state"                                 = "state",
  "daily_casesFilled"                     = "cases",
  "daily_deathsFilled"                    = "deaths",
  "daily_fractionPositive_15dayMovingAvg" = "fracpos",
  "daily_totalTests"                      = "volume"
) -> final_vars

# The final CTP data frame             
final.df <- CTP_cleaned[, names(final_vars)]
colnames(final.df) <- final_vars

write_csv(final.df, output_path)
cli_alert_success("Wrote cleaned data to {.file {output_path}}")

if (is.null(graphs_path))
  quit()

warnings()
