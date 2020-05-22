# Paths to the three Git submodules containing nytimes, covidtracking, nyc data
nyt  := data-sources/nytimes-data
cvdt := data-sources/covidtracking-data
nyc  := data-sources/nychealth-data

# Target for the three history files we want to produce, and the cleaned
# cases/deaths/test-positivity data file (using Ken's script)
data: data-products/nytimes-counties.csv \
  data-products/covidtracking-states.csv \
  data-products/nychealth-chd.csv \
  data-products/covidtracking-smoothed.csv

clean: 
	@rm -f data-products/nytimes-counties.csv \
	  data-products/covidtracking-states.csv \
	  data-products/nychealth-chd.csv \
	  data-products/covidtracking-smoothed.csv

# The next three recipes pull all updates from the submodule remotes, and rerun
# the file_history.sh script to concatenate all the committed versions of the 
# two files and append the commit date to the end of each row
data-products/nytimes-counties.csv: $(nyt)/us-counties.csv src/file_history.sh
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
data-products/covidtracking-smoothed.csv: $(cvdt)/data/states_daily_4pm_et.csv \
  R/cleanCTP.R
	@mkdir -p data-products/
	git submodule update --remote $(cvdt)
	Rscript R/cleanCTP.R -o ../$@ ../$<
