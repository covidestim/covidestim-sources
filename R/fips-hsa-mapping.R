#!/usr/bin/env Rscript
suppressPackageStartupMessages( library(tidyverse) )
library(docopt, warn.conflicts = FALSE)
library(cli,    warn.conflicts = FALSE)
library(sf,     warn.conflicts = FALSE)

# Turn off spherical coordinate subsystem, avoids some geometry errors. See:
# https://stackoverflow.com/questions/68478179/how-to-resolve-spherical-geometry-failures-when-joining-spatial-data
sf::sf_use_s2(FALSE)
                    
'HSA splittter: splits HSAs into counties according to CBG-level pop estimates.

Usage:
  cleanHHS.R -o <path> --hsapolygons <path> --cbgpolygons <path> --cbgpop <path>
  cleanHHS.R (-h | --help)
  cleanHHS.R --version

Options:
  -o <path>             Path to output cleaned data to.
  --hsapolygons <path>  A shapefile with polygons for all of the HSAs
  --cbgpolygons <path>  A shapefile with polygons for all Census Block Groups
  --cbgpop <path>       A csv [GEOID,pop] with population estimates for all CBGs
  -h --help             Show this screen.
  --version             Show version.

' -> doc

ps <- cli_process_start
pd <- cli_process_done

args <- docopt(doc, version = 'fips-hsa-mapping.R 0.1')

# Fake args for debugging/development
# args <- list(
#   hsapolygons = "../data-sources/hsa-shapefile/HsaBdry_AK_HI_unmodified.shp", 
#   cbgpolygons = "../data-sources/cb_2019_us_bg_500k/cb_2019_us_bg_500k.shp", 
#   cbgpop = "../data-sources/population_by_cbg.csv",
# )

output_path <-  args$o

cols(
  GEOID = col_character(),
  population = col_double()
) -> cbgpopSpec

ps("Reading HSA polygons shapefile {.file {args$hsapolygons}}")
hsapolygons <- read_sf(args$hsapolygons)
pd()

ps("Reading CBG polygons shapefile {.file {args$cbgpolygons}}")
cbgpolygons <- read_sf(args$cbgpolygons)
pd()

ps("Reading CBG populations file {.file {args$cbgpop}}")
cbgpop <- read_csv(args$cbgpop, col_types = cbgpopSpec)
pd()

# Join the CBG population data to the CBG polygons. This results in a loss of
# ~285 CBGs (out of 217k). Some CBGs have 0 population.
#
# The GEOIDs used in the two datasets have slightly different formats, so
# one of them is chopped to match the other.
#
# Then, the centroids of each CBG are calculated. This is done so that each
# CBG is within at most one HSA - since otherwise it would be possible for the
# polygonal shape of a CBG to intersect two HSAs.
#
# Note: `st_centroid()` will give a warning about lat/long and planar geometry.
#   It's true that using lat/long will introduce some error in the centroid
#   calculations. However, my judgement is that this is safe to ignore for
#   calculating the centroids of CBGs because they are mostly very small in
#   size. For more information on this, see:
#
#   https://r-spatial.github.io/sf/articles/sf6.html
ps("Joining population data to CBG polygons and calculating CBG centroids")
cbgpopCentroids <- mutate(cbgpop, GEOID = str_sub(GEOID, 8, 19)) %>%
  inner_join(cbgpolygons, by = 'GEOID') %>%
  transmute(
    GEOID,
    fips = paste0(STATEFP, COUNTYFP),
    population,
    geometry
  ) %>%
  st_as_sf() %>%
  mutate(geometry = st_centroid(geometry))
pd()

# Question: How much population does the above operation ^ lose?

ps("Reprojecting HSA polygons and CBG centroids to prepare for spatial join")
hsapolygons     <- mutate(hsapolygons,     geometry = st_transform(geometry, 4326))
cbgpopCentroids <- mutate(cbgpopCentroids, geometry = st_transform(geometry, 4326))
pd()

ps("Joining CBG centroids to HSA polygons using {.code st_nearest_feature} operator")
# `st_nearest_feature()` will complain about lat/long geometry, just like 
# `st_centroid()`. The same rationale is used to ignore the warning.
cbgsWithHSA <- st_join(cbgpopCentroids, hsapolygons, join = st_nearest_feature) %>%
  select(GEOID, fips, population, hsa = HSA93) %>%
  as_tibble
pd()

# Q: Which and how many CBGs are left unallocated to an HSA at this point?
# A: None

ps("Computing per-HSA and per-county population sizes using CBG data")
cbgsWithHSAAndPop <- group_by(cbgsWithHSA, hsa) %>%
  mutate(popHSA = sum(population, na.rm = T)) %>%
  group_by(fips) %>%
  mutate(popFIPS = sum(population, na.rm = T)) %>%
  ungroup
pd()

ps("Computing proportions of HSA population which lie in each county")
fipsMapping <- cbgsWithHSAAndPop %>%
  group_by(fips, hsa) %>%
  # We use first() here because every row has the HSA population, and we don't
  # want to pass a vector as an argument to the summary function.
  summarize(proportion = sum(population, na.rm = T) / first(popHSA)) %>% ungroup
pd()

# Validation:
#
# 1. All of the HSAs for a given FIPS have proportions that sum to 1 (or very
#    close to 1, due to floating-point error)
#
# 2. If you join in the HSA population sizes, you can compute the population of
#    the county. When you compare this to the population of the county, as
#    computed by adding CBG populations together, these two different methods
#    of computing the population size produce, nearly always, the same number.
#    When they don't, they're within 1 person of each other.

out <- fipsMapping

ps("Writing output data to {.file {output_path}}")
write_csv(out, output_path)
pd()

