#---------------------------------------------------------------------------------------------
# Name: SGCNcollector_gbif.R
# Purpose: 
# Author: Christopher Tracey
# Created: 2017-07-10
# Updated: 
#
# Updates:
# insert date and info
# * 2016-08-17 - got the code to remove NULL values from the keys to work; 
#                added the complete list of SGCN to load from a text file;
#                figured out how to remove records where no occurences we found;
#                make a shapefile of the results  
#
# To Do List/Future Ideas:
# * check projection
# * wkt integration
# * filter the occ_search results on potential data flags -- looks like its pulling 
#   the coordinates from iNat that are obscured.  
# * might be a good idea to create seperate reports with obscured records
#-------

setwd("C:/Users/ctracey/Dropbox (PNHP @ WPC)/coa/COA/SGCN_DataCollection")

library('rgbif')
library('plyr')
library('data.table')
library('rgdal')  # for vector work; sp package should always load with rgdal. 
library('raster')   # for metadata/attributes- vectors or rasters

year_begin <- 1950 #set this to whatever year you want the observations to begin
year_end <- format(Sys.Date(), format="%Y") # get the current year
recordlimit <- 1000 # modify if needed, fewer will make testing go faster
time_period <- paste(year_begin,year_end,sep=",")
CoordinateUncertainty <- 300 # in meters
aoi_wkt <- 'POLYGON ((-80.577111647999971 42.018959019000079, -80.583025511999949 39.690462536000041, -77.681987232999973 39.68735201800007, -75.761816590999956 39.690666106000037, -75.678308913999956 39.790810226000076, -75.53064649099997 39.815101786000071, -75.411566911999955 39.776679135000052, -75.101245089999964 39.880029385000057, -75.09383042199994 39.944216030000064, -74.690932882999959 40.133570156000076, -74.690425973999936 40.17528313400004, -74.893196517999968 40.350896889000069, -74.914505704999954 40.415842984000051, -75.012247039999977 40.448477402000037, -75.004556583999943 40.522413349000033, -75.134560399999941 40.623471625000036, -75.136516799999981 40.723392383000032, -75.002409694999983 40.867515299000047, -75.082051382999964 40.971575944000051, -74.830463730999952 41.152763058000062, -74.768212647999974 41.271891205000031, -74.640518995999969 41.358839422000074, -74.709416559999966 41.454495330000043, -74.826329023999961 41.475865789000068, -74.936988959999951 41.521739840000066, -75.018029425999941 41.617276498000081, -75.012709979999954 41.733926517000043, -75.061642930999938 41.85481505100006, -75.218658916999971 41.904656042000056, -75.336705265999967 42.017618624000079, -77.511689405999959 42.017704281000078, -79.721693517999938 42.024739989000068, -79.715980736999938 42.353623043000027, -80.577111647999971 42.018959019000079))' # simplified boundard of Pennsylvania.

# read in the SGCn lookup
lu_sgcn <- read.csv("lu_sgcn.csv")
# add a field for ELSEASON
lu_sgcn$ELSEASON <- paste(lu_sgcn$ELCODE,lu_sgcn$SeasonCode,sep="-")

# subset to the species group one wants to query
sgcn_query <- lu_sgcn[which(lu_sgcn$TaxaGroup!="AB"),]
splist <- factor(sgcn_query$SNAME) # generate a species list to query gbif

# gets the  keys for each species name, based on GBIF
keys <- sapply(splist, function(x) name_backbone(name=x)$speciesKey, USE.NAMES=FALSE)
keys2 <- as.numeric(as.character(keys))
sgcn_spKey <- data.frame(splist,keys2)
sgcn_NotInGBIF <- droplevels(sgcn_spKey[is.na(sgcn_spKey$keys2),c(1)])

if (length(sgcn_NotInGBIF)>0) {
  cat("The following SGCN were not found in GBIF:", paste("\t","- ",as.vector(sgcn_NotInGBIF)),sep="\n")
  # gets rid of any null values generated by name_backbone in the case of unmatchable species names
  keys=keys[-(which(sapply(keys,is.null),arr.ind=TRUE))] #note: seems to break if there is only one item in the list... use for multiple species!
} else {
  cat("All the SGCN were found in GBIF. ","\n",sep="")
}

#searches for occurrences
dat <- occ_search(
  taxonKey=keys, 
  limit=recordlimit,
  return='data', 
  hasCoordinate=TRUE,
  geometry=aoi_wkt, 
  year=time_period,
  fields=c('name','scientificName','datasetKey','recordedBy','key','decimalLatitude','decimalLongitude','country','basisOfRecord','coordinateAccuracy','year','month','day','coordinateUncertaintyInMeters')
)

dat <-dat[dat!="no data found, try a different search"] # deletes the items from the list where no occurences were found. doesn't work for one species
datdf <- ldply(dat) # turns the list to a data frame

# subsets records to under a specified coordinate uncertainty (eg. 300m)
datdf <- datdf[which(datdf$coordinateUncertaintyInMeters<CoordinateUncertainty | is.na(datdf$coordinateUncertaintyInMeters)),]


#generetates list of GBIF names and keys for joining up the proper SWAP sames names later in the script
myvars <- c(".id","name")
gbif_spKey <-  unique(datdf[myvars])
setnames(gbif_spKey, ".id", "keys")
sgcn_spKey <- sgcn_spKey[!is.na(sgcn_spKey$keys2),] #data.frame(splist,keys)
setnames(sgcn_spKey, "keys2", "keys")
gbif_spKey <-  join(gbif_spKey,sgcn_spKey,by=c('keys'))
sgcn_spKey <- NULL

gbifdata <- datdf # just changing the name so it backs up

#this will eventually pull up the dataset name so we can put it int tohe notes
#datasetkeys <- unique(datdf$datasetKey)
#datasetnames <- datasets(uuid="c4a2c617-91a7-4d4f-90dd-a78b899f8545")

gbifdata$Notes <- paste("Basis of Record=",datdf$basisOfRecord,sep="")
gbifdata$DataSource <- "GBIF"
setnames(gbifdata, "name", "SNAME")
setnames(gbifdata, "key", "DataID")
setnames(gbifdata, "decimalLongitude", "Longitude")
setnames(gbifdata, "decimalLatitude", "Latitude")

# build the last observed field
gbifdata$LASTOBS <- paste(gbifdata$year,sprintf("%02d",gbifdata$month),sprintf("%02d",gbifdata$day),sep="-")
# replace the snames in the gbif dataset with our SGCN snames
gbifdata$SNAME <- gbif_spKey$splist[match(unlist(gbifdata$SNAME), gbif_spKey$name)]
gbif_spKey <- NULL

# delete the colums we don't need from the gbif dataset
keeps <- c("SNAME","DataID","DataSource","Longitude","Latitude","LASTOBS","Notes")
gbifdata <- gbifdata[keeps]

# delete the columns from the lu_sgcn layer and 
keeps <- c("SNAME","SCOMNAME","ELCODE","TaxaGroup","Environment")
sgcn_query <- sgcn_query[keeps]

# join the data to the sgcn lookup info
gbifdata <-  join(gbifdata,sgcn_query,by=c('SNAME'))

# create a shapefile
# based on http://neondataskills.org/R/csv-to-shapefile-R/
# note that the easting and northing columns are in columns 5 and 6
SGCNgbif <- SpatialPointsDataFrame(gbifdata[,4:5],gbifdata,,proj4string <- CRS("+init=epsg:4326"))   # assign a CRS, proj4string = utm18nCR  #https://www.nceas.ucsb.edu/~frazier/RSpatialGuides/OverviewCoordinateReferenceSystems.pdf; the two commas in a row are important due to the slots feature
plot(SGCNgbif,main="Map of SGCN Locations")
# write a shapefile
writeOGR(SGCNgbif, getwd(),"SGCN_FromGBIF", driver="ESRI Shapefile")
