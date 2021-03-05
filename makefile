# Path to the JHU git submodule's timeseries directory
jhu_data  := data-sources/jhu-data/csse_covid_19_data/csse_covid_19_time_series
jhu_reports := data-sources/jhu-data/csse_covid_19_data/csse_covid_19_daily_reports_us

# Path to NYTimes submodule
nyt := data-sources/nytimes-data

# Short for data-products
dp := data-products

# Target for the three history files we want to produce, and the cleaned
# cases/deaths/test-positivity data file (using Ken's script)
data: $(dp)/covidtracking-smoothed.csv $(dp)/jhu-counties.csv

clean: 
	@rm -f $(data)

# This recipe produces smoothed test-positivty data from the Covid Tracking
# Project.
# However they transitioned away from offering data through Git and moved to
# a purely api-based approach
#
# data-products/covidtracking-smoothed.csv: $(cvdt)/data/states_daily_4pm_et.csv \
#   R/cleanCTP.R
# 	@mkdir -p data-products/
# 	git submodule update --remote $(cvdt)
# 	Rscript R/cleanCTP.R -o $@ $<

# This recipe produces cleaned state-level data from the Covid Tracking Project
# API.
$(dp)/covidtracking-smoothed.csv: R/cleanCTP.R
	@mkdir -p data-products/
	wget -O ctp_tmp.csv 'https://api.covidtracking.com/v1/states/daily.csv'
	Rscript R/cleanCTP.R -o $@ ctp_tmp.csv
	@rm -f ctp_tmp.csv

# This recipe produces cleaned county-level data from the JHU repo
$(dp)/jhu-counties.csv $(dp)/jhu-counties-rejects.csv: R/cleanJHU-counties.R \
  $(jhu_data)/time_series_covid19_confirmed_US.csv \
  $(jhu_data)/time_series_covid19_deaths_US.csv
	@mkdir -p data-products/
	Rscript $< -o $(dp)/jhu-counties.csv \
	  --writeRejects $(dp)/jhu-counties-rejects.csv \
	  --cases  $(jhu_data)/time_series_covid19_confirmed_US.csv \
	  --deaths $(jhu_data)/time_series_covid19_deaths_US.csv

$(dp)/jhu-states.csv $(dp)/jhu-states-rejects.csv: R/cleanJHU-states.R \
  $(jhu_reports)
	@mkdir -p data-products/
	Rscript $< -o $(dp)/jhu-states.csv \
	  --writeRejects $(dp)/jhu-states-rejects.csv \
	  --reportsPath  $(jhu_reports)

$(dp)/nytimes-counties.csv $(dp)/nytimes-counties-rejects.csv: R/cleanNYT-counties.R \
  $(nyt)/us-counties.csv
	@mkdir -p data-products/
	Rscript $< -o $(dp)/nytimes-counties.csv \
	  --writeRejects $(dp)/nytimes-counties-rejects.csv \
	  $(nyt)/us-counties.csv
