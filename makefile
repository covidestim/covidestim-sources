# Path to the JHU git submodule's timeseries directory
jhu_data    := data-sources/jhu-data/csse_covid_19_data/csse_covid_19_time_series
jhu_reports := data-sources/jhu-data/csse_covid_19_data/csse_covid_19_daily_reports_us

# Path to NYTimes submodule
nyt := data-sources/nytimes-data

# Short for data-products, data-sources
dp := data-products
ds := data-sources

clean: 
	@rm -rf data-products

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
$(dp)/jhu-counties.csv $(dp)/jhu-counties-rejects.csv $(dp)/jhu-counties-metadata.json &: R/cleanJHU-counties.R \
  $(jhu_data)/time_series_covid19_confirmed_US.csv \
  $(jhu_data)/time_series_covid19_deaths_US.csv \
  data-sources/fipspop.csv \
  data-sources/county-nonreporting.csv
	@mkdir -p data-products/
	Rscript $< -o $(dp)/jhu-counties.csv \
	  --pop data-sources/fipspop.csv \
	  --nonreporting data-sources/county-nonreporting.csv \
	  --writeRejects $(dp)/jhu-counties-rejects.csv \
	  --writeMetadata $(dp)/jhu-counties-metadata.json \
	  --cases  $(jhu_data)/time_series_covid19_confirmed_US.csv \
	  --deaths $(jhu_data)/time_series_covid19_deaths_US.csv

# JHU state data, prefilled with archived covid tracking project data
$(dp)/jhu-states.csv $(dp)/jhu-states-rejects.csv $(dp)/jhu-states-metadata.json &: R/cleanJHU-states.R \
  $(jhu_reports) \
  splicedates.csv \
  $(ds)/CTP-backfill-archive.csv
	@mkdir -p data-products/
	Rscript $< -o $(dp)/jhu-states.csv \
	  --prefill $(ds)/CTP-backfill-archive.csv \
	  --splicedate splicedates.csv \
	  --writeRejects $(dp)/jhu-states-rejects.csv \
	  --writeMetadata $(dp)/jhu-states-metadata.json \
	  --reportsPath  $(jhu_reports)

$(dp)/nytimes-counties.csv $(dp)/nytimes-counties-rejects.csv &: R/cleanNYT-counties.R \
  $(nyt)/us-counties.csv
	@mkdir -p data-products/
	Rscript $< -o $(dp)/nytimes-counties.csv \
	  --writeRejects $(dp)/nytimes-counties-rejects.csv \
	  $(nyt)/us-counties.csv

$(dp)/vaccines-counties.csv:
	@mkdir -p data-products/
	Rscript -e "readr::write_csv(vaccineAdjust::run(), '$@')" || \
	  gunzip < data-sources/vaccines-backup.csv.gz > $@

$(dp)/case-death-rr.csv $(dp)/case-death-rr-metadata.json &: R/join-JHU-vaccines.R \
  $(dp)/vaccines-counties.csv \
  $(dp)/jhu-counties.csv \
  $(dp)/jhu-counties-metadata.json
	@mkdir -p data-products
	Rscript $< -o $(dp)/case-death-rr.csv \
	  --writeMetadata $(dp)/case-death-rr-metadata.json \
	  --metadata $(dp)/jhu-counties-metadata.json \
	  --vax $(dp)/vaccines-counties.csv \
	  --jhu $(dp)/jhu-counties.csv

$(dp)/case-death-rr-state.csv $(dp)/case-death-rr-state-metadata.json &: R/join-state-JHU-vaccines.R \
  $(dp)/vaccines-counties.csv \
  $(dp)/jhu-states.csv \
  $(dp)/jhu-states-metadata.json
	@mkdir -p data-products
	Rscript $< -o $(dp)/case-death-rr-state.csv \
   	  --writeMetadata $(dp)/case-death-rr-state-metadata.json \
	  --metadata $(dp)/jhu-states-metadata.json \
	  --vax $(dp)/vaccines-counties.csv \
	  --jhu $(dp)/jhu-states.csv

$(dp)/hhs-hospitalizations-by-facility.csv: R/cleanHHS-facility.R \
	$(ds)/ZipHsaHrr18.csv \
	$(ds)/hhs-hospitalizations-by-week.csv
	Rscript $< -o $@ \
	  --crosswalk $(ds)/ZipHsaHrr18.csv \
	  --hhs $(ds)/hhs-hospitalizations-by-week.csv

# Hospitalizations by county: aggregates hospitalizations by facility into
# counties using "fips-hsa-mapping.csv"
$(dp)/hhs-hospitalizations-by-county.csv: R/cleanHHS-county.R \
	$(dp)/hhs-hospitalizations-by-facility.csv \
	$(ds)/fips-hsa-mapping.csv
	Rscript $< -o $@ \
	  --cleanedhhs $(dp)/hhs-hospitalizations-by-facility.csv \
	  --mapping $(ds)/fips-hsa-mapping.csv

# Using data from DHHS's API, cleans the data, which is at the facility level,
# and annotates each faility with a HSA, using the zip code. Also, computes
# .min and .max columns to compensate for censoring done when there are 1-3
# hospitalizations in a given week
$(dp)/hhs-hospitalizations-by-facility.csv: R/cleanHHS-facility.R \
	$(ds)/ZipHsaHrr18.csv \
	$(ds)/hhs-hospitalizations-by-week.csv
	Rscript $< -o $@ \
	  --crosswalk $(ds)/ZipHsaHrr18.csv \
	  --hhs $(ds)/hhs-hospitalizations-by-week.csv

# Creates the file which states, for each HSA, the proportion of the HSA
# population that lies within any intersecting county.
$(ds)/fips-hsa-mapping.csv: R/fips-hsa-mapping.R \
	$(ds)/hsa-polygons/HsaBdry_AK_HI_unmodified.shp \
	$(ds)/cbg-polygons/cb_2019_us_bg_500k.shp \
	$(ds)/population_by_cbg.csv
	Rscript $< -o $@ \
	  --hsapolygons $(ds)/hsa-polygons/HsaBdry_AK_HI_unmodified.shp \
	  --cbgpolygons $(ds)/cbg-polygons/cb_2019_us_bg_500k.shp \
	  --cbgpop $(ds)/population_by_cbg.csv

# Performs the API call to healthdata.gov to fetch latest hospitalizations
# data.
$(ds)/hhs-hospitalizations-by-week.csv:
	wget -O $@ 'https://healthdata.gov/api/views/anag-cw7u/rows.csv?accessType=DOWNLOAD'
