#---------------------------------------------------------------------------------------------
# Name: SGCNcollector_eBird.r
# Purpose: https://www.butterfliesandmoths.org/
# Author: Christopher Tracey
# Created: 2017-07-10
# Updated: 2019-02-20
#
# Updates:
# insert date and info
# * 2018-09-21 -  
# * 2019-02-20 - rewrite and update
#
# To Do List/Future Ideas:
# * 
#---------------------------------------------------------------------------------------------

# Instructions: 
# 1) Before running cleanup code, download and save eBird data in your working directory  
# 2) cygwin (gawk) must be installed

# load packages
if (!requireNamespace("arcgisbinding", quietly = TRUE)) install.packages("arcgisbinding")
require(arcgisbinding)
if (!requireNamespace("auk", quietly = TRUE)) install.packages("auk")
require(auk)
if (!requireNamespace("lubridate", quietly = TRUE)) install.packages("lubridate")
require(lubridate)
if (!requireNamespace("here", quietly = TRUE)) install.packages("here")
require(here)
if (!requireNamespace("sf", quietly = TRUE)) install.packages("sf")
require(sf)

arc.check_product() # load the arcgis license

# read in SGCN data
sgcn <- arc.open(here("COA_Update.gdb","lu_sgcn")) # need to figure out how to reference a server
sgcn <- arc.select(sgcn, c("ELCODE", "SNAME", "SCOMNAME", "TaxaGroup","ELSeason" ), where_clause="ELCODE LIKE 'AB%'")

sgcn_clean <- unique(sgcn$SNAME)
sgcn_clean <- sgcn_clean[!sgcn_clean %in% "Anas discors"] # species not in the ebird dataset

auk_set_ebd_path(here("_data","input","SGCN_data","eBird"), overwrite=TRUE)

# 2016 eBird data ##############################################
#get a list of what's in the directory
fileList <- dir(path=here("_data","input","SGCN_data","eBird"), pattern = ".txt$")
fileList
#look at the output and choose which shapefile you want to run. enter its location in the list (first = 1, second = 2, etc)
n <- 1

# read in the file using auk
f_in <- here("_data","input","SGCN_data","eBird",fileList[[n]]) #"C:/Users/dyeany/Documents/R/eBird/ebd.txt"
f_out <- "ebd_filtered_SGCN.txt"
ebd <- auk_ebd(f_in)
ebd_filters <- auk_species(ebd, species=sgcn_clean, taxonomy_version=2016)
ebd_filtered <- auk_filter(ebd_filters, file=f_out, overwrite=TRUE)
ebd_df2016 <- read_ebd(ebd_filtered)
ebd_df2016_backup <- ebd_df2016

# 2018 eBird data ##############################################
#get a list of what's in the directory
fileList <- dir(path=here("_data","input","SGCN_data","eBird"), pattern = ".txt$")
fileList
#look at the output and choose which shapefile you want to run. enter its location in the list (first = 1, second = 2, etc)
n <- 2

# read in the file using auk
f_in <- here("_data","input","SGCN_data","eBird",fileList[[n]]) #"C:/Users/dyeany/Documents/R/eBird/ebd.txt"
f_out <- "ebd_filtered_SGCN.txt"
ebd <- auk_ebd(f_in)
ebd_filters <- auk_species(ebd, species=sgcn_clean, taxonomy_version=2017)
ebd_filtered <- auk_filter(ebd_filters, file=f_out, overwrite=TRUE)
ebd_df2018 <- read_ebd(ebd_filtered)
ebd_df2018_backup <- ebd_df2018
# Combine 2016 and 2018 data ##################################
setdiff(names(ebd_df2016), names(ebd_df2018))

names(ebd_df2018)[names(ebd_df2018)=='state'] <- 'state_province'
names(ebd_df2018)[names(ebd_df2018)=='state_code'] <- 'subnational1_code'
names(ebd_df2018)[names(ebd_df2018)=='county_code'] <- 'subnational2_code'
names(ebd_df2018)[names(ebd_df2018)=='state'] <- 'state_province'
ebd_df2016$first_name <- NULL
ebd_df2016$last_name <- NULL
ebd_df2018$last_edited_date <- NULL
ebd_df2018$breeding_bird_atlas_category <- NULL
ebd_df2018$usfws_code <- NULL
ebd_df2018$protocol_code <- NULL
ebd_df2018$has_media <- NULL
sortorder <- names(ebd_df2016)
ebd_df2018 <- ebd_df2018[sortorder]
# merge the multiple years together
ebd_df <- rbind(ebd_df2016,ebd_df2018)

# gets rid of the bad data lines
ebd_df$latitude <- as.numeric(as.character(ebd_df$latitude))
ebd_df$longitude <- as.numeric(as.character(ebd_df$longitude))
ebd_df <- ebd_df[!is.na(as.numeric(as.character(ebd_df$latitude))),]
ebd_df <- ebd_df[!is.na(as.numeric(as.character(ebd_df$longitude))),]

### Filter out unsuitable protocols (e.g. Traveling, etc.) and keep only suitable protocols (e.g. Stationary, etc.)
ebd_df <- ebd_df[which(ebd_df$locality_type=="P"|ebd_df$locality_type=="H"),]
ebd_df <- ebd_df[which(ebd_df$protocol_type=="Banding"|
           ebd_df$protocol_type=="Stationary"|
           ebd_df$protocol_type=="eBird - Stationary Count"|
           ebd_df$protocol_type=="Incidental"|
           ebd_df$protocol_type=="eBird - Casual Observation"|
           ebd_df$protocol_type=="eBird--Rusty Blackbird Blitz"|
           ebd_df$protocol_type=="Rusty Blackbird Spring Migration Blitz"|
           ebd_df$protocol_type=="International Shorebird Survey (ISS)"|
           ebd_df$protocol_type=="eBird--Heron Stationary Count"|
           ebd_df$protocol_type=="Random"|
           ebd_df$protocol_type=="eBird Random Location Count"|
          ebd_df$protocol_type=="Historical"),]
### Next filter out records by Focal Season for each SGCN using day-of-year
# library(lubridate)
ebd_df$dayofyear <- yday(ebd_df$observation_date) ## Add day of year to eBird dataset based on the observation date.
birdseason <- read.csv(here("scripts","SGCN_DataCollection","SGCNcollector_eBird_birdseason.csv"), colClasses = c("character","character","integer","integer"),stringsAsFactors=FALSE)

### assign a migration date to each ebird observation.
ebd_df$season <- NA
for(i in 1:nrow(birdseason)){
  comname<-birdseason[i,1]
  season<-birdseason[i,2]
  startdate<-birdseason[i,3]
  enddate<-birdseason[i,4]
  ebd_df$season[ebd_df$common_name==comname & ebd_df$dayofyear>startdate & ebd_df$dayofyear<enddate] <- as.character(season)
}

# drops any species that has an NA due to be outsite the season dates
ebd_df <- ebd_df[!is.na(ebd_df$season),]

# add additonal fields 
ebd_df$DataSource <- "eBird"
ebd_df$OccProb <- "k"
names(ebd_df)[names(ebd_df)=='scientific_name'] <- 'SNAME'
names(ebd_df)[names(ebd_df)=='common_name'] <- 'SCOMNAME'
names(ebd_df)[names(ebd_df)=='global_unique_identifier'] <- 'DataID'
names(ebd_df)[names(ebd_df)=='lon'] <- 'Longitude'
names(ebd_df)[names(ebd_df)=='lat'] <- 'Latitude'
names(ebd_df)[names(ebd_df)=='observation_date'] <- 'LastObs'



ebd_df$year <- year(parse_date_time(ebd_df$LastObs,"ymd"))
ebd_df <- ebd_df[which(!is.na(ebd_df$year)),] # deletes one without a year

ebd_df$useCOA <- NA
cutoffYear <- year(Sys.Date())-25
ebd_df$useCOA <- with(ebd_df, ifelse(ebd_df$year >= cutoffYear, "y", "n"))



# drops the unneeded columns. 
ebd_df <- ebd_df[c("SNAME","DataID","longitude","latitude","LastObs","year","useCOA","DataSource","OccProb","season")]

#add in the SGCN fields
ebd_df <- merge(ebd_df, sgcn, by="SNAME", all.x=TRUE)


ebd_df$ELSeason <- paste(ebd_df$ELCODE,substr(ebd_df$season,1,1),sep="_")

sgcnfinal <- sgcn$ELSeason

ebd_df1 <- ebd_df[which(ebd_df$ELSeason %in% sgcnfinal),]
# pull out the most recent date for each speces, long, and lat combo and only keep the most recent
##ebd_df2 <- aggregate(year ~ ELSeason + longitude + latitude, data = ebd_df1, FUN = max)

#ebd_final <- merge(ebd_df2, )

# create a spatial layer
ebird_sf <- st_as_sf(ebd_df1, coords=c("longitude","latitude"), crs="+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")

# delete unneeded stuff
rm(birdseason, sgcn, ebd, ebd_df_backup, ebd_filtered, ebd_filters)


