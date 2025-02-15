
## Make raster from predictions

library(dplyr)
library(raster)
library(sf)

library(terra)

utm10N <- 32610

gis <- here::here("03_format_data","gis")
gis_in <- here::here('03_format_data','gis','raw_gis_data')
gis_out <- here::here('03_format_data','gis','processed_gis_data')
dir(gis_in)

minocc = 6; period = "S1"
varsName = 'vars11'
date.model.run = '2023'
abund = "pa"

resFolder = here::here('04_Output', "sjsdm_general_outputs", glue::glue('{varsName}_{date.model.run}'))
predFolder = here::here('04_Output', "sjsdm_prediction_outputs", glue::glue('{varsName}_{date.model.run}'))
plotFolder = here::here('04_Output', "prediction_map")
dir(resFolder)


## load species AUC results for filtering
load(file.path(predFolder, 'rdata', "sp_test_results.rdata")) # # sp.res.test, sp.res.train

# load clamp predictions (file too large for github)
# load(file.path(plotFolder, "rdata", paste0("sjSDM_predictions_", "M1S1_", "min", minocc, "_", varsName, "_", abund, "_clamp", ".rdata")))

## alt location (in top level repo folder)
alt_loc <- file.path(getwd(), "../")
load(file.path(alt_loc, paste0("sjSDM_predictions_", "M1S1_", "min", minocc, "_", varsName, "_", abund, "_clamp", ".rdata")))


# pred.mn.cl, pred.sd.cl


## Mean AUC per species (and other eval metrics)
str(sp.res.test, max.level = 1)
head(sp.res.test$auc)

sum(is.na(sp.res.test$auc))

## Filter species by auc
auc.filt <- 0.70
sum(sp.res.test$auc > auc.filt, na.rm = T) # 76

## load model data for species names, incidence
load(file.path("./03_format_data/otu/modelData_pa.rdata"))
rm(device,env.vars,env.vars.test,iter,k,minocc,noSteps,otu.qp.csv,otu.qp.csv.test,otuenv,sampling,select.percent,spChoose,test.Names,train.Names,vars,varsName)


test.incidence <- data.frame(species = colnames(otu.pa.csv.test), test.noSites = colSums(otu.pa.csv.test), 
                              test.incid = colSums(otu.pa.csv.test)/nrow(otu.pa.csv.test), row.names = NULL)

# incidence 
incidence <- colSums(otu.pa.csv)/nrow(otu.pa.csv)


spp <- data.frame(species = colnames(get(paste0("otu.", abund, ".csv")))) %>%
  tidyr::separate(col = species, into = c("OTU", "empty", "class", "order", "family",
                                          "genus", "epithet", "BOLD", "BOLDID",
                                          "size"),
                  remove = FALSE, sep = "_", convert = TRUE) %>%  ## creates real NAs with convert = T
  mutate(best.name = case_when(is.na(epithet) & is.na(genus) & is.na(family) & is.na(order) ~ class,
                               is.na(epithet) & is.na(genus) & is.na(family) ~ order,
                               is.na(epithet) & is.na(genus) ~ family,
                               is.na(epithet) ~ genus,
                               TRUE ~ paste(genus, epithet, sep = "_")
                               )) %>%
  dplyr::select(-empty)%>%
  mutate(auc = sp.res.test$auc,
         tjur = sp.res.test$tjur,
         incidence = incidence,
         best.name = paste(best.name, BOLDID, sep = "_"))%>%
  left_join(y = test.incidence, by = "species")

head(spp)


## dO plots

dim(pred.mn.cl)

# load raster templates - reduced areas
load(file.path(gis, "templateRaster.rdata")) ## r.msk, indNA aoi.pred.sf, r.aoi.pred - reduced area for plotting
# plot(r.msk)
# plot(aoi.pred.sf)

### bring in manually edited prediction area outline to replace above
aoi.pred.sf_edit <- st_read(file.path(gis_out, "s_utm/aoi_pred_sf_edit.shp"))
aoi.pred.sf_edit <- st_make_valid(aoi.pred.sf_edit)

# clamp predictions filtered by species
pred.in.cl <- pred.mn.cl[,sp.res.test$auc >= auc.filt & !is.na(sp.res.test$auc)]

## get species names too
spp.in <- spp[sp.res.test$auc >= auc.filt & !is.na(sp.res.test$auc), ]
head(spp.in)


## make rasters per species
rList <- lapply(data.frame(pred.in.cl), function(x) {
  
  tmp <- r.msk
  tmp[indNA] <- x
  tmp
  
})

# plot(tmp)
rStack.cl <- stack(rList)
names(rStack.cl) <- spp.in$best.name
rStack.cl

## add auc incidence names to stack
names(rStack.cl) <- paste0(spp.in$best.name, "_", "auc=", round(spp.in$auc, 2), "_",  "prev=", round(spp.in$incidence,2))

sppFolder <- file.path(gis_out, "r_utm", "spp_tifs_cl")
if(!dir.exists(sppFolder)) dir.create(sppFolder)
# writeRaster(rStack.cl, bylayer = T, filename = file.path(sppFolder, "spp_cl.tif"), suffix = "names", datatype = "FLT4S")
filenames <- file.path(sppFolder, paste0(names(rStack.cl), "_spp_cl.tif"))
terra::writeRaster(rast(rStack.cl), filename = filenames, datatype = "FLT4S")



# threshold for binary maps for species richness
tr <- 0.5
rStack.bin.cl <- raster::reclassify(rStack.cl, rcl = c(0, tr, 0, tr, 1, 1))
rStack.sum.cl <- sum(rStack.cl)
names(rStack.sum.cl) <- "sp sum"
spRich.cl <- sum(rStack.bin.cl)
names(spRich.cl) <- "sp richness"

plot(spRich.cl)
plot(rStack.sum.cl)

## Do maps of richness by groups.

## load extra layers for plotting
## Load sample site points
load(file.path(gis_out, "sample_sites.rdata"))
xy.utm

## bring in HJA boundary
# https://data-osugisci.opendata.arcgis.com/datasets/74312b6130cb4e9b8c454ae1195f6482_9/data
hja <- st_read(file.path(gis_in, "shape/HJA_Boundary.shp"))
hja_bound <- subset(hja, FP_NAME == "H.J. Andrew Experimental Forest")
hja.utm <- st_transform(hja_bound, crs = utm10N)

st_area(hja.utm) / 1000000 ## in km^2

## Make species richness stack
rStack.bin.cl
spRich_order.cl <- stackApply(rStack.bin.cl, spp.in$order, fun = sum)
names(spRich_order.cl)
names(spRich_order.cl) <- sub("index_", "", names(spRich_order.cl))


writeRaster(rStack.sum.cl, filename = file.path(gis_out, "r_utm", "spSum_cl.tif"), datatype = "FLT4S", overwrite = T)
writeRaster(spRich.cl, filename = file.path(gis_out, "r_utm", "spRich_all_cl.tif"), datatype = "FLT4S", overwrite = T)


## save clamped prediction species raster stack
save(rStack.cl, file = file.path(gis_out, "r_utm", "rasterStacks_cl.rdata"))

# convert HJA to raster and save
hja.r <- rStack.cl

hja.utm
plot(r.aoi.pred, colNA = "black")
hja.r <- rasterize(hja.utm, r.aoi.pred)

plot(hja.r, colNA = "black")

# convert to 1 and 0 for inside/outside HJA

hja.r[is.na(hja.r)] <- 0
hja.r <- mask(hja.r, r.aoi.pred)
plot(hja.r, colNA = "black")

save(hja.r, file = file.path(gis_out, "hja_raster.rdata"))

## write single pdf with all spp
source(file.path("01_HJA_scripts/09_predict_map/source", "plotStack.r"))

# function to add to each plot
addAll <- function(){

  plot(st_geometry(hja.utm), add = T, col = NA, border = "black")
  #plot(st_geometry(aoi.pred.sf), add = T, col = NA, border = "black")
  plot(st_geometry(xy.utm), add = T, col = "grey40", pch = 3, cex = 0.2)

}


## write single pdf with all spp
pdf(file.path("04_Output/figures", "all_spp.pdf"), width = 7, height = 7)
# this is Fig. S-individual SDMs in the supplement
plotStack(rStack.cl, addfun = addAll, cex.main = 0.7)
dev.off()

