# Paths to the three Git submodules containing nytimes, covidtracking, nyc data
nyt       := data-sources/nytimes-data
cvdt      := data-sources/covidtracking-data
nyc       := data-sources/nychealth-data
jhu       := data-sources/jhu-data
jhu_data  := data-sources/jhu-data/csse_covid_19_data/csse_covid_19_time_series

# Target for the three history files we want to produce, and the cleaned
# cases/deaths/test-positivity data file (using Ken's script)
data: data-products/nytimes-counties.csv \
  data-products/covidtracking-states.csv \
  data-products/nychealth-chd.csv \
  data-products/covidtracking-smoothed.csv

clean: 
	@rm -f $(data)

# The next three recipes pull all updates from the submodule remotes, and rerun
# the file_history.sh script to concatenate all the committed versions of the 
# three files and append the commit date to the end of each row
data-products/nytimes-counties-history.csv: $(nyt)/us-counties.csv src/file_history.sh
	@mkdir -p data-products/
	git submodule update --remote $(nyt)
	./src/file_history.sh $(nyt) us-counties.csv > $@

data-products/covidtracking-states.csv: $(cvdt)/data/states_daily_4pm_et.csv \
  src/file_history.sh
	@mkdir -p data-products/
	git submodule update --remote $(cvdt)
	./src/file_history.sh $(cvdt) data/states_daily_4pm_et.csv > $@

data-products/nychealth-chd.csv: $(nyc)/case-hosp-death.csv src/file_history.sh
	@mkdir -p data-products/
	git submodule update --remote $(nyc)
	./src/file_history.sh $(nyc) case-hosp-death.csv > $@

# This recipe produces smoothed test-positivty data from the Covid Tracking
# Project
# data-products/covidtracking-smoothed.csv: $(cvdt)/data/states_daily_4pm_et.csv \
#   R/cleanCTP.R
# 	@mkdir -p data-products/
# 	git submodule update --remote $(cvdt)
# 	Rscript R/cleanCTP.R -o $@ $<

data-products/covidtracking-smoothed.csv: R/cleanCTP.R
	@mkdir -p data-products/
	wget -O ctp_tmp.csv 'https://api.covidtracking.com/v1/states/daily.csv'
	Rscript R/cleanCTP.R -o $@ ctp_tmp.csv
	@rm -f ctp_tmp.csv

# This recipe produces cleaned county-level data from the NYTimes repo
data-products/nytimes-counties.csv: $(nyt)/us-counties.csv \
  R/cleanNYT-counties.R
	@mkdir -p data-products/
	git submodule update --remote $(nyt)
	Rscript R/cleanNYT-counties.R -o $@ $<

# This recipe produces cleaned county-level data from the JHU repo
data-products/jhu-counties.csv: R/cleanJHU-counties.R \
  $(jhu_data)/time_series_covid19_confirmed_US.csv \
  $(jhu_data)/time_series_covid19_deaths_US.csv
	@mkdir -p data-products/
	git submodule update --remote $(jhu)
	Rscript $< -o $@ \
	  --cases  $(jhu_data)/time_series_covid19_confirmed_US.csv \
	  --deaths $(jhu_data)/time_series_covid19_deaths_US.csv
