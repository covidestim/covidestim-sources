#!/usr/bin/env Rscript

# dataframe "daily_cases_deaths_fractionPositive" with date, state, daily cases, daily deaths, and smoothened daily fraction positive ~ line 75

library(lubridate)
library(ggplot2)
library(reshape2)
library(openintro)

CTP <- "https://raw.githubusercontent.com/COVID19Tracking/covid-tracking-data/master/data/states_daily_4pm_et.csv"
CTP_download <- read.csv(url(CTP),stringsAsFactors = F)

# The data at the top of the file are the most recent dates
CTP_data <- CTP_download[nrow(CTP_download):1,]

# lubridate
CTP_data$date <- ymd(CTP_data$date)

# replace the state abbreviations with state names
CTP_data$state[which(CTP_data$state=="AS")] <- "American Samoa"
CTP_data$state[which(CTP_data$state=="PR")] <- "Puerto Rico"
CTP_data$state[which(CTP_data$state=="GU")] <- "Guam"
CTP_data$state[which(CTP_data$state=="VI")] <- "Virgin Islands"
CTP_data$state[which(CTP_data$state=="MP")] <- "Northern Mariana Islands"
CTP_data$state[which(CTP_data$state!="American Samoa"&CTP_data$state!="Puerto Rico"&CTP_data$state!="Guam"&CTP_data$state!="Virgin Islands"&CTP_data$state!="Northern Mariana Islands")] <- abbr2state(CTP_data$state[(CTP_data$state!="American Samoa"&CTP_data$state!="Puerto Rico"&CTP_data$state!="Guam"&CTP_data$state!="Virgin Islands"&CTP_data$state!="Northern Mariana Islands")])

state_names <- unique(CTP_data$state)

# initialize single dataframe => date, state, daily positive (dp), daily increase in tests (dt), daily fraction postiive smoothed (df), daily deaths

CTP_movingAverages <- data.frame(date=as.Date(character()),state=character(),cum_cases=double(),cum_totalTests=double(),cum_deaths=double(),daily_cases=double(),daily_totalTests=double(),daily_deaths=double(),cum_casesFilled=double(),cum_deathsFilled=double(),cum_totalTestsFilled=double(),daily_cases_9dayMovingAverage=double(),daily_totalTests_9dayMovingAverage=double(),daily_fractionPositive=double(),daily_fractionPositiveSmoothened=double(),stringsAsFactors = F)

# for loop to add incident cases, incident deaths, and rbind dataset 
for(i in 1:length(state_names)){
  
  temp_data <- CTP_data[which(CTP_data$state==state_names[i]),]
  temp_data <- temp_data[,c("date","state","positive","totalTestResults","death")]
  colnames(temp_data) <- c("date","state","cum_cases","cum_totalTests","cum_deaths")
  
  # add zero to cumulative cases
  cum_cases <- c(0,temp_data$cum_cases)
  cum_deaths <- c(0,temp_data$cum_deaths)
  cum_totalTests <- c(0,temp_data$cum_totalTests)
  
  # fill in cumulative cases
  for(i in 2:length(cum_cases)){
    cum_cases[i] <- max(cum_cases[1:i],na.rm = T)
    cum_deaths[i] <- max(cum_deaths[1:i],na.rm = T)
    cum_totalTests[i] <- max(cum_totalTests[1:i],na.rm=T)
  }
  
  # calculate daily
  temp_data$daily_cases <- diff(cum_cases)
  temp_data$daily_deaths <- diff(cum_deaths)
  temp_data$daily_totalTests <- diff(cum_totalTests)
  
  # save filled cum cases
  temp_data$cum_casesFilled <- cum_cases[-1]
  temp_data$cum_deathsFilled <- cum_deaths[-1]
  temp_data$daily_totalTestsFilled <- cum_totalTests[-1]
  
  # create moving averages
  temp_data$daily_cases_9dayMovingAverage <- rep(NA,nrow(temp_data))
  temp_data$daily_totalTests_9dayMovingAverage <- rep(NA,nrow(temp_data))
  
  # 7 day moving averages
  for(k in 5:(nrow(temp_data)-4)){
    temp_data$daily_cases_9dayMovingAverage[k] <- mean(temp_data$daily_cases[(k-4):(k+4)])
    temp_data$daily_totalTests_9dayMovingAverage[k] <- mean(temp_data$daily_totalTests[(k-4):(k+4)])
  }
  
  temp_data$daily_fractionPositive <- temp_data$daily_cases/temp_data$daily_totalTests
  temp_data$daily_fractionPositiveSmoothened <- temp_data$daily_cases_9dayMovingAverage/temp_data$daily_totalTests_9dayMovingAverage
  
  CTP_movingAverages <- rbind(CTP_movingAverages,temp_data)
  remove(temp_data)
  
}

daily_cases_deaths_fractionPositive <- CTP_movingAverages[,c("date","state","daily_cases","daily_deaths","daily_fractionPositiveSmoothened")]

## Visualize the data

CTP_daily_cases_tests <- CTP_movingAverages[,c("date","state","daily_cases","daily_totalTests")]
CTP_daily_cases_tests_long <- melt(CTP_daily_cases_tests,id.vars=c("date","state"))

CTP_fractionPositive <- CTP_movingAverages[,c("date","state","daily_fractionPositive","daily_fractionPositiveSmoothened")]
CTP_fractionPositive_long <- melt(CTP_fractionPositive,id.vars=c("date","state"))

# view daily cases and tests
ggplot(data=CTP_daily_cases_tests_long,aes(x=date,y=value,color=variable))+
  geom_line()+
  facet_wrap(~state, scales="free")+
  theme_minimal()

# view fraction positive and smoothened fraction positive
ggplot(data=CTP_fractionPositive_long,aes(x=date,y=value,color=variable))+
  geom_line()+
  facet_wrap(~state, scales="free")+
  theme_minimal()
  
# view daily deaths
ggplot(data=CTP_movingAverages,aes(x=date,y=daily_deaths))+
  geom_line()+
  facet_wrap(~state, scales="free")+
  theme_minimal()

