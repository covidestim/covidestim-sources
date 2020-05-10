library(tidyverse)
library(anytime)
library(glue)

file_name <- "us-counties-aggregated.csv"

c(
  'date', 'county', 'state', 'fips',
  'cases', 'deaths', 'date_commit'
) -> col_names

cols(
  date        = col_date(format = '%Y-%m-%d'), # YYYY-MM-DD format
  county      = col_character(),
  state       = col_character(),
  fips        = col_number(),
  cases       = col_number(),
  deaths      = col_number(),
  date_commit = col_number() # unix timestamp
) -> col_types

transform_incidence <- function(d) {
  group_by(d, date_commit, county, state) %>%
    arrange(date) %>%
    mutate(cases  = cases  - lag(cases,  default = 0),
           deaths = deaths - lag(deaths, default = 0)) %>%
    ungroup
}

p <- read_csv(file_name, col_names = col_names, col_types = col_types)

prevalence <- mutate(p, date_commit = anytime(date_commit))
incidence  <- transform_incidence(prevalence)

group_by(incidence, date, county, state) %>%
  arrange(date_commit) %>%
  mutate(cases  = cases  - lag(cases),
         deaths = deaths - lag(deaths)) %>%
  ungroup() %>%
  arrange(date, date_commit) -> deltas_incidence

group_by(prevalence, date, county, state) %>%
  arrange(date_commit) %>%
  mutate(cases  = cases  - lag(cases),
         deaths = deaths - lag(deaths)) %>%
  ungroup() %>%
  arrange(date, date_commit) -> deltas_prevalence

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

plot_discrepancy <- function(d,
                             county_ = NULL,
                             state_  = NULL) {

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

  ggplot(summed_data, aes(x = date, group = date_commit)) +
    geom_line(
      color = 'grey',
      aes(y = deaths)
    ) +
    geom_point(
      data = ~group_by(., date_commit) %>% top_n(1, date),
      aes(y = deaths, color = date_commit)
    ) +
    geom_line(
      color = 'grey',
      aes(y = cases)
    ) +
    geom_point(
      data = ~group_by(., date_commit) %>% top_n(1, date),
      aes(y = cases, color = date_commit)
    ) +
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
    scale_y_continuous(
      trans = scales::pseudo_log_trans(base = 10),
      labels = scales::label_number_si(),
      breaks = function(limits)
        c(0, scales::breaks_log(n=8)(c(1, limits[2])))
    ) +
    scale_x_date(date_breaks = '1 week',
                 date_labels = "%b %d",
                 minor_breaks = NULL) +
    annotation_logticks() +
    theme_linedraw() +
    labs(
      x = "Date referenced",
      y = "Quantity",
      color = "Date committed"
    ) +
    theme(
      legend.justification = c(1,0),
      legend.position = c(1,0),
      legend.box = 'horizontal'
    )
}
