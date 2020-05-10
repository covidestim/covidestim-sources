# Paths to the two Git submodules containing nytimes and covidtracking data
nyt  := data-sources/nytimes-data
cvdt := data-sources/covidtracking-data

# Target for the two history files we want to produce
data: data-products/nytimes-counties.csv data-products/covidtracking-states.csv

clean: 
	@rm -f data-products/nytimes-counties.csv data-products/covidtracking-states.csv

# The next two recipes pull all updates from the submodule remotes, and rerun
# the file_history.sh script to concatenate all the committed versions of the 
# two files and append the commit date to the end of each row
data-products/nytimes-counties.csv: $(nyt)/us-counties.csv src/file_history.sh
	mkdir -p data-products/
	git submodule update --remote $(nyt)
	./src/file_history.sh $(nyt) us-counties.csv > $@

data-products/covidtracking-states.csv: $(cvdt)/data/states_daily_4pm_et.csv \
  src/file_history.sh
	mkdir -p data-products/
	git submodule update --remote $(cvdt)
	./src/file_history.sh $(cvdt) data/states_daily_4pm_et.csv > $@
