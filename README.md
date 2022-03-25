# covidestim-sources

This repository provides a way to easily clean various input data used for 
the `covidestim` model to produce the following easy-to-use outcomes:

- **Cases**
- **Deaths**
- **Vaccination-related risk ratio**
- **Hospitalizations** (experimental)

These data are offered at the following geographies:

| Outcome              | County-level | State-level |
|----------------------|--------------|-------------|
| **Cases**            | [x]          | [x]         |
| **Deaths**           | [x]          | [x]         |
| **Risk-ratio**       | [x]          | [x]         |
| **Hospitalizations** | [x]          | [ ] *Soon*  |

## Usage

Initialize the Git submodules:

```bash
git clone https://github.com/covidestim/covidestim-sources && cd covidestim-sources
git submodule init
git submodule update --remote # This will take 5-30 minutes

# Make all primary outcomes
make -Bj data-products/{case-death-rr.csv,case-death-rr-state.csv,hospitalizations-by-county.csv}
```

## Staying current

Data sources will **not** automatically update, and thus, `make` will not
normally do anything if you attempt to remake a target. This is undesirable if
you believe there may be newer versions of data sources available. To pull new
data from sources backed by submodules, run:

```bash
git submodule update --remote
```

And, use `make -B` to force targets to be remade, like so:

```bash
make -B data-products/case-death-rr.csv
```

## Data sources

All data sources for the cleaned data are either:

- Committed to the repository
- Committed to the repository, but backed by [Git LFS][lfs]
- Accessed through HTTP requests in the `makefile` or in R scripts
- Committed to the repository as Git submodules

| Data                                      | Used for                                                                                      | Accessed through                                                                        | Frequency of update |
|-------------------------------------------|-----------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------|---------------------|
| Johns Hopkins CSSE                        | Cases, Deaths                                                                                 | Submodule `data-sources/jhu-data`                                                       | **>Daily**          |
| Covid Tracking Project                    | Cases, Deaths (2021-02 - 2021-06)                                                             | HTTP, `api.covidtracking.com`                                                           | No longer updated   |
| NYTimes covid data                        | *Nothing, but a future merge will use it to supplement counties missing from the JHU dataset* | Submodule, `data-sources/nyt-data`                                                      | **>Daily**          |
| USCB county, state population estimates   | Everything                                                                                    | `data-sources/{fips,state}pop.csv`, reformatted from [.xls][xlspop]                     | *1/yr?*             |
| DHHS facility-level hospitalizations data | Hospitalizations                                                                              | HTTP, `healthdata.gov/api`                                                              | **1/wk**            |
| Dartmouth Atlas Zip-HSA-HRR crosswalk     | Hospitalizations (agg/disagg)                                                                 | `data-sources/ZipHsaHrr18.csv`, downloaded from [dartmouthatlas.org][da]                | *1/yr?*             |
| Dartmouth Atlas HSA polygons              | Hospitalizations (agg/disagg)                                                                 | `data-sources/hsa-polygons/` ([Git LFS][lfs]), downloaded from [dartmouthatlas.org][da] | *1/yr?*             |
| Census Block Group polygons               | Hospitalizations (agg/disagg)                                                                 | `data-sources/cbg-polygons/` ([Git LFS][lfs]),  downloaded from [TIGER][tiger]          | *1/yr?*             |
| Census Block Group popsize                | Hospitalizations (agg/disagg)                                                                 | `data-sources/population_by_cbg.csv/`, extracted from [TIGER][tiger]                    | *1/yr?*             |

[xlspop]: https://www.census.gov/geographies/reference-files/2020/demo/popest/2020-fips.html
[da]: https://data.dartmouthatlas.org/supplemental/
[lfs]: https://git-lfs.github.com/
[tiger]: https://www.census.gov/cgi-bin/geo/shapefiles/index.php?year=2021&layergroup=Census+Tracts

Some data sources are tracked as git submodules, and other sources, being 
accessed through APIs, are fetched over HTTP. Large static files are stored
through [Git LFS][lfs].

The included `makefile` provides a common interface for directing the fetching
and cleaning of all data sources.

## Targets

- **`make data-products/case-death-rr.csv`**  
  Clean JHU county-level case/death data. Also writes a file
  `jhu-counties-rejects.csv` for counties which were eliminated during the
  cleaning process. Any metadata for counties included in the cleaned data will
  be stored in `case-death-rr-metadata.json`.

- **`make data-products/case-death-rr-state.csv`**  
  Clean JHU state-level data, splicing in archived Covid Tracking Project data.
  For details on this, see the `makefile`. Also writes
  `jhu-states-rejects.csv`. Any metadata for counties included in the cleaned
  data will be stored in `case-death-rr-metadata.json`. 

- **`make data-products/nyt-counties.csv`**  
  Clean NYT county-level case/death data. Writes `nyt-counties-rejects.csv`.

- **`make data-products/hhs-hospitalizations-by-county.csv`**  
  County-level aggregation of facility level hospitalization data. See the next
  section for details on how this is done.

- **`make data-products/hhs-hospitalizations-by-facility.csv`**  
  Cleans facility-level data from DHHS's API and annotates each faility with an
  HSA id. Also, computes .min and .max columns to compensate for censoring done
  when there are 1-3 hospitalizations in a given week.

## Hospitalizations data pipeline

*In progress...*

