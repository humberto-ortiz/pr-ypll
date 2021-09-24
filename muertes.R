# muertes.R - examine deaths from COVID-19 in Puerto Rico
# See https://github.com/rafalab/pr-covid
# death plots cribbed from dashboard/wrangle.R
# adapted to examine YPLL by Humberto Ortiz-Zuazaga

library(tidyverse)
library(lubridate)
library(scales)

# moving average ----------------------------------------------------------

ma7 <- function(d, y, k = 7) 
  tibble(date = d, moving_avg = as.numeric(stats::filter(y, rep(1/k, k), side = 1)))

first_day <- make_date(2020, 3, 12)

age_levels <-  c("0 to 9", "10 to 19", "20 to 29", "30 to 39", "40 to 49", "50 to 59", "60 to 69",
"70 to 79", "80 to 89", "90 to 99", "100 to 109", "110 to 119", "120 to 129")

age_starts <- c(0, 10, 15, 20, 30, 40, 65, 75)

age_ends <- c(9, 14, 19, 29, 39, 64, 74, Inf)

url <- "https://bioportal.salud.gov.pr/api/administration/reports/deaths/summary"
##portal_summary <- read_file(url)
deaths <- jsonlite::fromJSON(url) %>%
  mutate(date = as_date(ymd_hms(deathDate, tz = "America/Puerto_Rico"))) %>%
  mutate(date = if_else(date < first_day | date > today(),
    as_date(ymd_hms(reportDate, tz = "America/Puerto_Rico")),
    date)) %>%
  mutate(age_start = as.numeric(str_extract(ageRange, "^\\d+")),
  age_end = as.numeric(str_extract(ageRange, "\\d+$"))) %>%
  mutate(ageRange = age_levels[as.numeric(cut(age_start, c(age_starts, Inf), right = FALSE))]) %>%
  mutate(ageRange = factor(ageRange, levels = age_levels))

# --Mortality and hospitlization
# use old handmade database to fill in the blanks
old_hosp_mort <- read_csv("https://raw.githubusercontent.com/rafalab/pr-covid/master/dashboard/data/DatosMortalidad.csv") %>%
  mutate(date = mdy(Fecha)) %>%
  filter(date >= first_day) %>%
  arrange(date) %>%
  select(date, HospitCOV19, CamasICU_disp, CamasICU)

httr::set_config(httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L))
url <- "https://covid19datos.salud.gov.pr/estadisticas_v2/download/data/sistemas_salud/completo"
hosp_mort <- read.csv(text = rawToChar(httr::content(httr::GET(url)))) %>% 
  mutate(date = as_date(FE_REPORTE)) %>%
  filter(date >= first_day) %>%
  full_join(old_hosp_mort, by = "date") %>%
  arrange(date) %>%
  ## add columns to match old table
  mutate(HospitCOV19 = ifelse(is.na(CAMAS_ADULTOS_COVID), HospitCOV19, CAMAS_ADULTOS_COVID),
         CamasICU = ifelse(is.na(CAMAS_ICU_COVID), CamasICU, CAMAS_ICU_COVID),
         CamasICU_disp = ifelse(is.na(CAMAS_ICU_DISP), CamasICU_disp, CAMAS_ICU_DISP))

## replace the death data with BioPortal data for consistency


hosp_mort <- deaths %>%
  group_by(date) %>%
  summarize(deaths = n(), .groups = "drop") %>%
  full_join(hosp_mort, by = "date") %>%
  arrange(date) %>%
  mutate(deaths = replace_na(deaths,0)) %>%
  mutate(IncMueSalud = deaths,
         mort_week_avg =  ma7(date, deaths)$moving_avg) %>%
  select(-deaths)

ypll <- deaths %>%
  mutate(ypll = 75 - (age_start + (age_end - age_start)/2)) %>%
  mutate(ypll = if_else(ypll < 0, 0, ypll))

ggplot(ypll, aes(x=date, y=cumsum(ypll))) + geom_line()

ggplot(ypll, aes(x=date, y=ypll)) + geom_col()

# Deaths ------------------------------------------------------------------
last_day <- today() - days(7)
last_complete_day <- today() - 1

plot_deaths <- function(hosp_mort,  
                        start_date = first_day, 
                        end_date = last_complete_day, 
                        cumm = FALSE,
                        yscale = FALSE){
  if(cumm){
    ret <- hosp_mort %>%
      replace_na(list(IncMueSalud = 0)) %>%
      mutate(IncMueSalud = cumsum(IncMueSalud)) %>%
      filter(date >= start_date & date <= end_date) %>%
      ggplot(aes(date)) +
      geom_bar(aes(y = IncMueSalud), stat = "identity", width = 0.75, alpha = 0.65) +
      ylab("Muertes acumuladas") +
      xlab("Fecha") +
      ggtitle("Muertes acumuladas") +
      scale_x_date(date_labels = "%b", breaks = breaks_width("1 month"))  +
      theme_bw()
  } else{
    
    hosp_mort$mort_week_avg[hosp_mort$date > last_day] <- NA
    
    ret <- hosp_mort %>%
      filter(date >= start_date & date <= end_date) %>%
      ggplot(aes(date)) +
      ylab("Muertes") +
      xlab("Fecha") +
      ggtitle("Muertes") +
      scale_x_date(date_labels = "%b", breaks = breaks_width("1 month"))  +
      #scale_y_continuous(breaks = seq(0, max(hosp_mort$IncMueSalud, na.rm=TRUE), 1)) +
      theme_bw()
    if(yscale){
      ret <- ret +  
        geom_bar(aes(y = IncMueSalud), stat = "identity", width = 0.75, alpha = 0.65) +
        geom_line(aes(y = mort_week_avg), color="black", size = 1.25)
    } else{
      ret <- ret +  
        geom_point(aes(y = IncMueSalud), width = 0.75, alpha = 0.65) +
        geom_line(aes(y = mort_week_avg), color="black", size = 1.25)
    }
  }
  return(ret)
}

plot_deaths(hosp_mort, yscale = TRUE)
