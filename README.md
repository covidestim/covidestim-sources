## Usage

GNU Parallel is required. Install GNU Parallel
[here](https://www.gnu.org/software/parallel/).


```bash
git submodule init
git submodule update
make data # Generate files in data-products/
```

Running `make data` will generate, into `data-products/`, the history of
NYTimes' [county-level confirmed-cases
data](https://github.com/nytimes/covid-19-data), and the history of the Covid
Tracking Project's [state-level
data](https://github.com/covid19Tracking/covid-tracking-data).

An accompanying R script, `R/script.R` provides utilities to analyze the
history of this data. Currently, it is configued for analyzing the NYTimes
data, but future modifications will be made to support a broader array of
data sources.

Note that the column added by the history-processing script, `date_committed`,
is a UNIX timestamp, not a regular date.  In R, UNIX timestamps can be easily
parsed by using the `anytime` package.

