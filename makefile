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

# JHU county-level cleaned data
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

# JHU state-level cleaned data, prefilled with archived covid tracking project data
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

# NYTimes county-level cleaned data
$(dp)/nytimes-counties.csv $(dp)/nytimes-counties-rejects.csv $(dp)/nytimes-counties-metadata.json &: R/cleanNYT-counties.R \
  $(nyt)/us-counties.csv \
  data-sources/fipspop.csv \
  data-sources/county-nonreporting.csv
	@mkdir -p data-products/
	Rscript $< -o $(dp)/nytimes-counties.csv \
	  --pop data-sources/fipspop.csv \
	  --nonreporting data-sources/county-nonreporting.csv \
	  --writeMetadata $(dp)/nytimes-counties-metadata.json \
	  --writeRejects $(dp)/nytimes-counties-rejects.csv \
	  $(nyt)/us-counties.csv

# Combination of JHU and NYTimes county-level data. When both data sources
# contain a county, JHU is chosen.
$(dp)/combined-counties.csv $(dp)/combined-counties-rejects.csv $(dp)/combined-counties-metadata.json &: R/combine-JHU-NYT-counties.R \
  $(dp)/nytimes-counties.csv \
  $(dp)/nytimes-counties-rejects.csv \
  $(dp)/nytimes-counties-metadata.json \
  $(dp)/jhu-counties.csv \
  $(dp)/jhu-counties-rejects.csv \
  $(dp)/jhu-counties-metadata.json
	@mkdir -p data-products/
	Rscript $< -o $(dp)/combined-counties.csv \
	  --jhu $(dp)/jhu-counties.csv \
	  --nyt $(dp)/nytimes-counties.csv \
	  --metadataJHU $(dp)/jhu-counties-metadata.json \
	  --metadataNYT $(dp)/nytimes-counties-metadata.json \
	  --rejectsJHU $(dp)/jhu-counties-rejects.csv \
	  --rejectsNYT $(dp)/nytimes-counties-rejects.csv \
	  --writeRejects $(dp)/combined-counties-rejects.csv \
	  --writeMetadata $(dp)/combined-counties-metadata.json

$(dp)/vaccines-counties.csv:
	@mkdir -p data-products/
	Rscript -e "readr::write_csv(vaccineAdjust::run(), '$@')" || \
	  gunzip < data-sources/vaccines-backup.csv.gz > $@

$(dp)/case-death-rr.csv $(dp)/case-death-rr-metadata.json &: R/join-combined-with-vaccines-data.R \
  $(dp)/vaccines-counties.csv \
  $(dp)/combined-counties.csv \
  $(dp)/combined-counties-metadata.json
	@mkdir -p data-products
	Rscript $< -o $(dp)/case-death-rr.csv \
	  --writeMetadata $(dp)/case-death-rr-metadata.json \
	  --vax $(dp)/vaccines-counties.csv \
	  --metadata $(dp)/combined-counties-metadata.json \
	  --casedeath $(dp)/combined-counties.csv

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
