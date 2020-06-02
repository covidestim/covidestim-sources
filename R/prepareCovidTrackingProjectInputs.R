
library(lubridate)
library(ggplot2)
library(reshape2)
library(openintro)
library(dplyr)
library(ggpubr)
library(gridExtra)
library(readr)

# Read Covid Tracking Project data
CTP <-
  "https://raw.githubusercontent.com/COVID19Tracking/covid-tracking-data/master/data/states_daily_4pm_et.csv"
CTP_download <- read.csv(url(CTP), stringsAsFactors = F)

# Reverse dataframe
CTP_data <- CTP_download[nrow(CTP_download):1, ]

# Lubridate date
CTP_data$date <- ymd(CTP_data$date)

# Replace the state/territory abbreviations with state/territory names
CTP_data$state[which(CTP_data$state == "AS")] <- "American Samoa"
CTP_data$state[which(CTP_data$state == "PR")] <- "Puerto Rico"
CTP_data$state[which(CTP_data$state == "GU")] <- "Guam"
CTP_data$state[which(CTP_data$state == "VI")] <- "Virgin Islands"
CTP_data$state[which(CTP_data$state == "MP")] <-
  "Northern Mariana Islands"
CTP_data$state[which(
  CTP_data$state != "American Samoa" &
    CTP_data$state != "Puerto Rico" &
    CTP_data$state != "Guam" &
    CTP_data$state != "Virgin Islands" &
    CTP_data$state != "Northern Mariana Islands"
)] <-
  abbr2state(CTP_data$state[(
    CTP_data$state != "American Samoa" &
      CTP_data$state != "Puerto Rico" &
      CTP_data$state != "Guam" &
      CTP_data$state != "Virgin Islands" &
      CTP_data$state != "Northern Mariana Islands"
  )])
state_names <- unique(CTP_data$state)

##################################
##                              ##
##   Clean & Prepare the data   ##
##                              ##
##################################

# Initialize a dataframe to hold all the results
CTP_cleaned <-
  data.frame(
    date = as.Date(character()),
    state = character(),
    cum_cases = double(),
    cum_totalTests = double(),
    cum_deaths = double(),
    daily_casesFilled = double(),
    daily_deathsFilled = double(),
    daily_fractionPositive=double(),
    daily_fractionPositive_15dayMovingAvg = double(),
    stringsAsFactors = F
  )

# Iterate through each state to clean data and add smoothed fraction positive
for (i in 1:length(state_names)) {
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
  # cumulative count increasesd  monotonically.
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
  "daily_fractionPositive_15dayMovingAvg" = "fracpos"
) -> final_vars

# The final CTP data frame
final.df <- CTP_cleaned[, names(final_vars)]

write_csv(final_vars, "cleaned.csv")

########################
##                    ##
## Visualize the data ##
##                    ##
########################

visualizeCasesDeaths.df <-
  CTP_cleaned[, c(
    "date",
    "state",
    "daily_casesFilled",
    "daily_deathsFilled"
  )]

visualizeCasesDeaths.df.long <-
  melt(visualizeCasesDeaths.df,
       id.vars = c("date", "state"))

visualizeFracPos.df <-
  CTP_cleaned[, c("date",
                  "state",
                  "daily_fractionPositive",
                  "daily_fractionPositive_15dayMovingAvg"
                  )]
visualizeFracPos.df.long <-
  melt(visualizeFracPos.df, id.vars = c("date", "state"))

# Arrange state/territory names in alphabetical order
state_names_sort <- sort(state_names)

# Initialize list to store plots
plots <- vector(mode = "list", length = length(state_names_sort))

for (i in 1:length(state_names)) {
  visualizeCasesDeaths.df.long.state <-
    visualizeCasesDeaths.df.long[which(visualizeCasesDeaths.df.long$state ==
                                                     state_names_sort[i]), ]
  plotCasesDeaths <-
    ggplot(data = visualizeCasesDeaths.df.long.state, aes(x = date, y = value, color = variable)) +
    geom_line(
      data = filter(
        visualizeCasesDeaths.df.long.state,
        variable == "daily_casesFilled"
      )
    ) +
    geom_line(
      data = filter(
        visualizeCasesDeaths.df.long.state,
        variable == "daily_deathsFilled"
      )
    ) +
    labs(title = paste0(state_names_sort[i], " Daily Counts")) +
    theme_light() +
    xlim(min(visualizeFracPos.df.long$date),
         max(visualizeFracPos.df.long$date))
  
  visualizeFracPos.df.long.state <-
    visualizeFracPos.df.long[which(visualizeFracPos.df.long$state == state_names_sort[i]), ]
  plotFracPos <-
    ggplot(data = visualizeFracPos.df.long.state, aes(x = date, y = value, color = variable)) +
    geom_point(data = filter(
      visualizeFracPos.df.long.state,
      variable == "daily_fractionPositive"
      )
    ) +
    geom_line(
      data = filter(
        visualizeFracPos.df.long.state,
        variable == "daily_fractionPositive_15dayMovingAvg"
      )
    ) +
    labs(title = paste0(state_names_sort[i], " Daily Fraction Test Positive")) +
    theme_light() +
    xlim(min(visualizeFracPos.df.long$date),
         max(visualizeFracPos.df.long$date)) +
    ylim(0, 1)
  
  plots[[i]] <- ggpubr::ggarrange(plotCasesDeaths,
                                  plotFracPos,
                                  nrow = 2,
                                  ncol = 1,
                                  align = "v")
  rm(plotCasesDeaths, plotFracPos)
  
}

#######################
##                   ##
## Save plots as PDF ##
##                   ##
#######################

ggsave(
  paste0("dataInputs_", Sys.Date(), ".pdf"),
  marrangeGrob(grob = plots, nrow = 1, ncol = 1)
)
