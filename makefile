# Path to the JHU git submodule's timeseries directory
jhu_data    := data-sources/jhu-data/csse_covid_19_data/csse_covid_19_time_series
jhu_reports := data-sources/jhu-data/csse_covid_19_data/csse_covid_19_daily_reports_us

# Path to NYTimes submodule
nyt := data-sources/nytimes-data

# Short for data-products, data-sources
dp := data-products
ds := data-sources

# Target for the three case/death data files we want to produce
data: $(dp)/covidtracking-smoothed.csv $(dp)/jhu-counties.csv $(dp)/jhu-states.csv

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

# This recipe produces cleaned state-level data from the Covid Tracking Project
# API, but clips it at date %
$(dp)/covidtracking-smoothed-clipped-%.csv: R/cleanCTP.R
	@mkdir -p data-products/
	wget -O ctp_tmp.csv 'https://api.covidtracking.com/v1/states/daily.csv'
	Rscript R/cleanCTP.R -o $@ --maxdate $* ctp_tmp.csv
	@rm -f ctp_tmp.csv

# This recipe produces cleaned county-level data from the JHU repo
$(dp)/jhu-counties.csv $(dp)/jhu-counties-rejects.csv: R/cleanJHU-counties.R \
  $(jhu_data)/time_series_covid19_confirmed_US.csv \
  $(jhu_data)/time_series_covid19_deaths_US.csv \
  data-sources/fipspop.csv
	@mkdir -p data-products/
	Rscript $< -o $(dp)/jhu-counties.csv \
	  --pop data-sources/fipspop.csv \
	  --writeRejects $(dp)/jhu-counties-rejects.csv \
	  --cases  $(jhu_data)/time_series_covid19_confirmed_US.csv \
	  --deaths $(jhu_data)/time_series_covid19_deaths_US.csv

# JHU state data, prefilled with archived covid tracking project data
$(dp)/jhu-states.csv $(dp)/jhu-states-rejects.csv: R/cleanJHU-states.R \
  $(jhu_reports)
	@mkdir -p data-products/
	Rscript $< -o $(dp)/jhu-states.csv \
	  --prefill $(ds)/CTP-backfill-archive.csv \
	  --splicedate splicedates.csv \
	  --writeRejects $(dp)/jhu-states-rejects.csv \
	  --reportsPath  $(jhu_reports)

# JHU state data, prefilled with archived covid tracking project data, however
# the "splice date" can be chosen here. For instance,
# 
#   `make data-products/jhu-states-spliced-2020-10-01.csv`
#
# will splice the data on October 1st: October 2nd will be the first day of
# JHU data.
$(dp)/jhu-states-spliced-%.csv $(dp)/jhu-states-spliced-%-rejects.csv: R/cleanJHU-states.R \
  $(jhu_reports)
	@mkdir -p data-products/
	Rscript $< -o $(dp)/jhu-states-spliced-$*.csv \
	  --prefill $(ds)/CTP-backfill-archive.csv \
	  --splicedate $* \
	  --writeRejects $(dp)/jhu-states-spliced-$*-rejects.csv \
	  --reportsPath  $(jhu_reports)

# JHU state data, no prefill
$(dp)/jhu-states-noprefill.csv $(dp)/jhu-states-noprefill-rejects.csv: R/cleanJHU-states.R \
  $(jhu_reports)
	@mkdir -p data-products/
	Rscript $< -o $(dp)/jhu-states-noprefill.csv \
	  --writeRejects $(dp)/jhu-states-rejects.csv \
	  --reportsPath  $(jhu_reports)


$(dp)/nytimes-counties.csv $(dp)/nytimes-counties-rejects.csv: R/cleanNYT-counties.R \
  $(nyt)/us-counties.csv
	@mkdir -p data-products/
	Rscript $< -o $(dp)/nytimes-counties.csv \
	  --writeRejects $(dp)/nytimes-counties-rejects.csv \
	  $(nyt)/us-counties.csv

$(dp)/vaccines-counties.csv:
	@mkdir -p data-products/
	Rscript -e "readr::write_csv(vaccineAdjust::run(), '$@')"

$(dp)/case-death-rr.csv: R/join-JHU-vaccines.R \
  $(dp)/vaccines-counties.csv $(dp)/jhu-counties.csv
	@mkdir -p data-products
	Rscript $< -o $@ \
	  --vax $(dp)/vaccines-counties.csv \
	  --jhu $(dp)/jhu-counties.csv
