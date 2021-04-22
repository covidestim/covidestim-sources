# covidestim-sources

This repository provides a way to easily clean various input data used for 
the `covidestim` model, including cases, deaths, and testing volume data.

Some data sources are tracked as git submodules, and other sources, being 
accessed through APIs, are not tracked, but rather fetched over HTTP.

The included `makefile` provides a common interface for directing the fetching
and cleaning of data sources.

The following sources are currently supported

- [CSSEGISandData/COVID-19](https://github.com/CSSEGISandData/COVID-19)  
  JHU CSSE's state- and county-level COVID data
  - [x] county level case/deaths
  - [x] state level case/deaths/fraction positive
  - [x] backfilling of early-epidemic state case/death data using archived [Covid Tracking Project](https://covidtracking.com/) data

- [nytimes/covid-19-data](https://github.com/nytimes/covid-19-data)
  NYTimes' covid data repository
  - [x] county level case/deaths

## Targets

- `make data-products/jhu-counties.csv`: Clean JHU county-level case/death
  data. Also writes a file `jhu-counties-rejects.csv` for counties which were
  eliminated during the cleaning process

- `make data-products/jhu-states.csv`: Clean JHU state-level data, splicing in
  archived Covid Tracking Project data. For details on this, see the
  `makefile`. Also writes `jhu-states-rejects.csv`

- `make data-products/nyt-counties.csv`: Clean NYT county-level case/death
  data. Writes `nyt-counties-rejects.csv`.

There are a few other targets, which are generally not used as final outputs
of the cleaning process.

## Usage

Initialize the Git submodules:

```bash
git clone https://github.com/covidestim/covidestim-sources && cd covidestim-sources
git submodule init
git submodule update
make [targets...]
```

## Staying current

You will need to periodically run

```bash
git submodule update
```

in order to keep your submodules up-to-date. Otherwise, data sources which are
git submodules will never change!

We recommend using `make -B` to force targets to be remade, like so:

```bash
make -B data-products/jhu-counties.csv
```

This is especially useful for targets which depend on the results of HTTP
requests.
