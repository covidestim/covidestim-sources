library(tidyverse)
library(anytime)
library(glue)
library(geofacet)

file_name.nyt           <- "data-products/nytimes-counties.csv"
file_name.covidtracking <- "data-products/covidtracking-states.csv"
file_name.nyc           <- "data-products/nychealth-chd.csv"

load_nyt <- function(file_name = file_name.nyt) {
  cols(
    date        = col_date(format = '%Y-%m-%d'), # YYYY-MM-DD format
    county      = col_character(),
    state       = col_character(),
    fips        = col_number(),
    cases       = col_number(),
    deaths      = col_number(),
    date_commit = col_number() # unix timestamp
  ) -> col_types.nyt

  f <- read_csv(file_name, col_types = col_types.nyt)

  # Transform the UNIX timestamp into a normal Date object
  mutate(f, date_commit = anytime(date_commit))
}

load_covidtracking <- function(file_name = file_name.covidtracking,
                               n_max = Inf) {
  cols(
    date                     = col_date(format = '%Y%m%d'),
    state                    = col_character(),
    positive                 = col_number(),
    negative                 = col_number(),
    pending                  = col_number(),
    hospitalizedCurrently    = col_number(),
    hospitalizedCumulative   = col_number(),
    inIcuCurrently           = col_number(),
    inIcuCumulative          = col_number(),
    onVentilatorCurrently    = col_number(),
    onVentilatorCumulative   = col_number(),
    recovered                = col_number(),
    dataQualityGrade         = col_character(),
    lastUpdateEt             = col_datetime(format = '%m/%d/%Y %H:%M'),
    hash                     = col_character(),
    death                    = col_number(),
    hospitalized             = col_number(),
    total                    = col_number(),
    totalTestResults         = col_number(),
    posNeg                   = col_number(),
    fips                     = col_number(),
    deathIncrease            = col_number(),
    hospitalizedIncrease     = col_number(),
    negativeIncrease         = col_number(),
    positiveIncrease         = col_number(),
    totalTestResultsIncrease = col_number(),
    date_commit              = col_number()
  ) -> col_types.covidtracking

  f <- read_csv(file_name, col_types = col_types.covidtracking, n_max = n_max)

  # Transform the UNIX timestamp into a normal Date object
  mutate(f, date_commit = anytime(date_commit))
}

load_nyc <- function(file_name = file_name.nyc,
                     n_max = Inf) {
  cols(
    DATE_OF_INTEREST   = col_date(format = '%m/%d/%y'),
    CASE_COUNT         = col_number(),
    HOSPITALIZED_COUNT = col_number(),
    DEATH_COUNT        = col_number(),
    date_commit        = col_number()
  ) -> col_types.nyc

  d <- read_csv(file_name, col_types = col_types.nyc, n_max = n_max)

  # Transform the UNIX timestamp into a normal Date object and rename a few of
  # the variables
  transmute(
    d,
    date             = DATE_OF_INTEREST,
    cases            = CASE_COUNT,
    hospitalizations = HOSPITALIZED_COUNT,
    deaths           = DEATH_COUNT,
    date_commit      = anytime(date_commit)
  )
}

{
  d <- load_covidtracking(n_max = 67019)

  pending <- group_by_at(d, c("state", "date", "date_commit")) %>%
    count(pending_available = is.na(pending))

  doPositivesChange <- d %>%
    select(state, date, date_commit, positive, negative, pending,
           totalTestResults, ends_with("Increase")) %>%
    group_by(state, date) %>%
    summarize_at(vars(-date_commit), ~length(unique(.)))

  doPositivesChange %>%
    gather(-state, -date, key="column", value="n_vals") %>%
    ggplot(aes(date, column, fill=factor(n_vals))) +
      geom_tile() +
      scale_x_date(date_breaks = '1 month',
                   date_labels = "%b",
                   minor_breaks = NULL) +
      facet_geo(vars(state)) +
      theme_linedraw()
}

# Create "case notification data" by subtracting from the previous day
transform_incidence <- function(d) {
  group_by(d, date_commit, county, state) %>%
    arrange(date) %>%
    mutate(cases  = cases  - lag(cases,  default = 0),
           deaths = deaths - lag(deaths, default = 0)) %>%
    ungroup
}

# Create "case notification data"
incidence.nyt  <- transform_incidence(prevalence)

# Generate the deltas for the "cumulative" data
group_by(prevalence.nyt, date, county, state) %>%
  arrange(date_commit) %>%
  mutate(cases  = cases  - lag(cases),
         deaths = deaths - lag(deaths)) %>%
  ungroup() %>%
  arrange(date, date_commit) -> deltas_prevalence.nyt

# Makes a plot of which days have been retroactively revised. By default,
# create a graph for the entire US. However, specifying `state_` or `county_`
# and `state_` makes it easy to generate this graph for any county or state
# in the US.
plot_deltas <- function(d, state_ = NULL, county_ = NULL) {

  predicates <- quos()

  if (!is.null(state_))
    predicates <- quos(state == state_)

  if (!is.null(county_) && !is.null(state_))
    predicates <- quos(county == county_)
  
  if (!is.null(county_) && is.null(state_))
    stop("You specified a county, but not a state")

  filtered_data <- filter(d, !!! predicates)

  summed_data <- group_by(filtered_data, date, date_commit) %>%
    summarize_at(vars(cases, deaths), sum) %>%
    ungroup

  ggplot(
    summed_data,
    aes(date, date_commit, fill = factor(sign(cases)))
  ) +
  geom_tile(height = 6*60^2) +
  scale_fill_manual(
    values = c("red", "grey", "green")
  ) +
  theme_minimal()
}

# Plots a branching history of case data. Identical geographic selection scheme
# to the above function. `d` is likely to be `deltas_incidence` or
# `deltas_prevalence`.
plot_discrepancy <- function(d,
                             county_ = NULL,
                             state_  = NULL) {


  # Holds the list of geographic filters that will be applied to `d`
  predicates <- quos()

  if (!is.null(state_))
    predicates <- quos(state == state_)

  if (!is.null(county_) && !is.null(state_))
    predicates <- quos(county == county_, state == state_)
  
  if (!is.null(county_) && is.null(state_))
    stop("You specified a county, but not a state")

  # Filter the data down to the geographic region of interest
  filtered_data <- filter(d, !!! predicates)

  # Sum the cases and deaths, in order to coalesce the various geographic
  # regions' worth of data, if there is >1 region present
  summed_data <- group_by(filtered_data, date, date_commit) %>%
    summarize_at(vars(cases, deaths), sum) %>%
    ungroup

  ggplot(summed_data, aes(x = date, group = date_commit)) +

    geom_line(color = 'grey', aes(y = deaths)) +
    # For each commit's worth of death data, just plot the last point, with
    # respect to time.
    geom_point(
      data = ~group_by(., date_commit) %>% top_n(1, date),
      aes(y = deaths, color = date_commit)
    ) +

    # The next two geoms are the same thing, but for cases data
    geom_line(color = 'grey', aes(y = cases)) +
    geom_point(
      data = ~group_by(., date_commit) %>% top_n(1, date),
      aes(y = cases, color = date_commit)
    ) +

    # Two cute labels to make it obvious which data is which
    geom_text(
      data = ~top_n(., 1, date),
      aes(y = cases),
      hjust = 1, nudge_x = -0.10, nudge_y = -0.10, angle = 45,
      label = "Cases"
    ) +
    geom_text(
      data = ~top_n(., 1, date),
      aes(y = deaths),
      hjust = 1, nudge_x = -0.10, nudge_y = -0.10, angle = 45,
      label = "Deaths"
    ) +

    # Fancy log scale with custom breaks etc
    scale_y_continuous(
      trans = scales::pseudo_log_trans(base = 10),
      labels = scales::label_number_si(),
      breaks = function(limits)
        c(0, scales::breaks_log(n=8)(c(1, limits[2]))),
      minor_breaks = 'null'
    ) +

    # Label every week, no minor breaks
    scale_x_date(date_breaks = '1 week',
                 date_labels = "%b %d",
                 minor_breaks = NULL) +
    annotation_logticks() +
    theme_linedraw() +
    labs(
      x     = "Date referenced",
      y     = "Quantity",
      color = "Date committed"
    ) +

    # Put the legend inside the negative space of the plot
    theme(
      legend.justification = c(1,0),
      legend.position      = c(1,0),
      legend.box           = 'horizontal'
    )
}
