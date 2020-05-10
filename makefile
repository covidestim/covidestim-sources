nyt  := data-sources/nytimes-data
cvdt := data-sources/covidtracking-data

data: data-products/nytimes-counties.csv data-products/covidtracking-states.csv

clean: 
	@rm -f data-products/nytimes-counties.csv data-products/covidtracking-states.csv

data-products/nytimes-counties.csv: $(nyt)/us-counties.csv src/file_history.sh
	git submodule update --remote $(nyt)
	./src/file_history.sh $(nyt) us-counties.csv > $@

data-products/covidtracking-states.csv: $(cvdt)/data/states_daily_4pm_et.csv \
  src/file_history.sh
	git submodule update --remote $(cvdt)
	./src/file_history.sh $(cvdt) data/states_daily_4pm_et.csv > $@
