library(tidyverse)
library(usmap)     # County population-size data
library(geofacet)  # Custom faceting
library(albersusa) # Polygons for counties
library(glue)
library(ggrepel)   # Better map labeling
library(sf)

d         <- read_csv("../data-products/hhs-hospitalizations-by-county.csv")
pfd       <- read_csv("../data-products/hhs-hospitalizations-by-facility.csv")
crosswalk <- read_csv("../data-sources/ZipHsaHrr18.csv")
mapping   <- read_csv("../data-sources/fips-hsa-mapping.csv")
hhs       <- read_csv("../data-sources/hhs-hospitalizations-by-week.csv")

###############################
# IMPORTANT: MUST BE MODIFIED!
###############################
# County-level estimates from the April 28 covidestim run. Can be downloaded
# from https://covidestim.org. Path here is to a local copy on my computer.
estimates <- read_csv("~/s3/covidestim/2021-04-28/estimates.csv")

# Join in *modeled* death data from the modeel results
joined <- left_join(d, select(estimates, fips, date, deaths), by = c("date", "fips"))

# Default lag is 10 days, but can be configued otherwise
makeRatios <- function(admissions, deaths, lag = 10)
  deaths / lag(admissions, n = lag)

# Calculate ratios at the county-level
d1 <- group_by(joined, fips) %>%
  arrange(date) %>%
  mutate(
    ratioAll       = makeRatios(admissionsAdultsConfirmed + admissionsAdultsSuspected, deaths),
    ratioSuspected = makeRatios(admissionsAdultsSuspected, deaths), 
    ratioConfirmed = makeRatios(admissionsAdultsConfirmed, deaths)
  ) %>% ungroup

# Calculate ratios at the state-level
d1_state <- left_join(countypop, joined, by = "fips") %>%
  group_by(abbr, date) %>% # `abbr` is state abbreviation (Connecticut = "CT")
  summarize(
    across(starts_with("admissions"), ~sum(., na.rm = TRUE)),
    deaths = sum(deaths, na.rm=T),
    .groups = "drop"
  ) %>%
  group_by(abbr) %>%
  arrange(date) %>%
  mutate(
    ratioAll       = makeRatios(admissionsAdultsConfirmed + admissionsAdultsSuspected, deaths),
    ratioSuspected = makeRatios(admissionsAdultsSuspected, deaths), 
    ratioConfirmed = makeRatios(admissionsAdultsConfirmed, deaths)
  ) %>% ungroup

allRatios <- d1 %>%
  pivot_longer(
    cols = starts_with("ratio"),
    names_to = "ratioType",
    values_to = "ratio"
  )

allRatios_state <- d1_state %>%
  pivot_longer(
    cols = starts_with("ratio"),
    names_to = "ratioType",
    values_to = "ratio"
  )

# Ratios, for the top 10 most populous counties
countypop %>% arrange(desc(pop_2015)) %>% top_n(10) %>%
  left_join(allRatios, by = "fips") %>%
  filter(ratioType != "ratioSuspected") %>%
  ggplot(aes(date, ratio, group=ratioType, color=ratioType, linetype = ratioType)) +
    geom_hline(yintercept = 0.148, color = "red") +
    geom_line(size=2) +
    scale_color_manual(
      "Ratio denominator",
      values = c("ratioAll" = "black", "ratioConfirmed" = "grey"),
      labels = c("ratioAll" = "Confirmed + Suspected", "ratioConfirmed" = "Confirmed")
    ) +
    scale_linetype_manual(values = c("ratioAll" = "solid", "ratioConfirmed" = "twodash")) +
    scale_x_date("Date", date_breaks = "1 month", date_labels = "%b", minor_breaks=NULL) +
    scale_y_continuous("Deaths/hospitalizations", breaks = (0:5)/10, minor_breaks=NULL, labels = scales::percent) +
    coord_cartesian(ylim = c(0,1)) +
    annotate("text", x = as.Date('2021-03-01'), y = 0.12, label='"E[P(die | sev)]"[prior]', parse = TRUE) +
    guides(linetype = "none") +
    facet_wrap(
      vars(
        glue::glue("{county}, {abbr} (pop {format(pop_2015, big.mark=',')})")
      )
    ) +
    theme_linedraw() +
    theme(
      legend.position = "top",
      legend.justification = c(0,0)
    ) +
    labs(
      title = "Deaths/Hospitalizations for 10 largest US counties",
      subtitle = "Hospitalizations have 10-day lag",
      caption = "Hospitalizations data current as of 2021-04-28\nModeled deaths data sourced from 2021-04-28 Covidestim run"
    )

# Ratios, for all states
allRatios_state %>% filter(ratioType != "ratioSuspected") %>%
  ggplot(aes(date, ratio, group=ratioType, color=ratioType, linetype = ratioType)) +
    geom_hline(yintercept = 0.148, color = "red") +
    geom_line(size=2) +
    scale_color_manual(
      "Ratio denominator",
      values = c("ratioAll" = "black", "ratioConfirmed" = "grey"),
      labels = c("ratioAll" = "Confirmed + Suspected", "ratioConfirmed" = "Confirmed")
    ) +
    scale_linetype_manual(values = c("ratioAll" = "solid", "ratioConfirmed" = "twodash")) +
    scale_x_date("Date", date_breaks = "2 months", date_labels = "%b", minor_breaks=NULL) +
    scale_y_continuous("Deaths/hospitalizations", breaks = (0:5)/10, minor_breaks=NULL, labels = scales::percent) +
    coord_cartesian(ylim = c(0, 0.5)) +
    guides(linetype = "none") +
    facet_geo(~abbr) +
    theme_linedraw() +
    theme(
      legend.position = "top",
      legend.justification = c(0,0)
    ) +
    labs(
      title = "Deaths/Hospitalizations for all US states",
      subtitle = "Hospitalizations have 10-day lag",
      caption = "Hospitalizations data current as of 2021-04-28\nModeled deaths data sourced from 2021-04-28 Covidestim run"
    )

###########################
# END of lag-related graphs
###########################

left_join(
  counties_sf('laea'),
  group_by(d, fips) %>%
    summarize(n = n(), minDate = min(date), maxDate = max(date)) %>%
    mutate(maxN = max(n))
) %>%
  ggplot(aes(fill = 1 - n/maxN, color = is.na(n))) +
    geom_sf() +
    geom_sf(data = usa_sf('laea'), fill = NA , color="white") +
    scale_color_manual(values = c("grey80", "black")) +
    scale_fill_gradient("~Percent missing", labels = scales::percent, low = "grey", high = "navyblue", na.value = "red", limits = c(0, 1)) +
    geom_text_repel(
      data = ~filter(., is.na(n)),
      aes(
        label = glue("{name}, {iso_3166_2}"),
        x = st_coordinates(st_centroid(geometry))[,"X"],
        y = st_coordinates(st_centroid(geometry))[,"Y"]
      ),
      fontface = "bold",
    ) +
    guides(color = "none") +
    labs(
      title = "Counties with missing or poor-extent hospitalization data",
      subtitle = "Red/labeled counties have no data. Blue counties have missing weeks at the beginning/end of the HHS dataset period",
      caption = "Hospitalizations data current as of 2021-04-28"
    ) +
    theme_void() +
    theme(
          legend.position = "top",
          legend.justification = c(0,0)
    )

transmute(
  hhs,
  hospital_pk,
  collection_week,
  state,
  na = (
    is.na(previous_day_admission_adult_covid_confirmed_7_day_sum) |
    is.na(previous_day_admission_adult_covid_suspected_7_day_sum) |
    is.na(previous_day_admission_pediatric_covid_confirmed_7_day_sum) |
    is.na(previous_day_admission_pediatric_covid_suspected_7_day_sum)
  )
) %>% arrange(collection_week) %>% complete(nesting(hospital_pk, state), collection_week) -> facilityLevelMissingness

# Which facilities are missing data?
ggplot(facilityLevelMissingness, aes(collection_week, hospital_pk, fill = na)) +
  geom_tile() +
  facet_geo(~state, scales="free_y") +
  scale_fill_manual(
    "Missing?",
    values = c("cadetblue4", "orangered"),
    labels = c("No", "Explicitly", "Implicitly"),
    na.value = "grey25"
  ) +
  scale_y_discrete(labels = NULL, breaks = NULL) +
  coord_cartesian(expand = FALSE) +
  labs(
    x = "Collection week",
    y = "Facility",
    title = "Explicit missingness in weekly facility-level data",
    caption = "Hospitalizations data current as of 2021-04-28"
  ) +
  theme(
    legend.position = "top",
    legend.justification = c(0,0)
  )

right_join(
  group_by(d, fips) %>% summarize(present = TRUE),
  counties_sf('laea')
) %>% filter(is.na(present)) %>% select(fips) -> missingFIPS

facilitiesPerHSA <- group_by(pfd, hsanum) %>%
  summarize(nFacilities = unique(hospital_pk) %>% length)

missingFIPS %>% left_join(mapping) %>% left_join(facilitiesPerHSA, by = c("hsa" = "hsanum"))
