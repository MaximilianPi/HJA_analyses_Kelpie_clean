#### TSNE analysis

# ..... setup

# HJA_analyses_Kelpie_clean # is the root folder and must have a .Rproj file in it for here::here() to work.
# setwd() # set here to HJA_analyses_Kelpie_clean or use here::here()

	
pacman::p_load('dplyr', 'rgdal', 'raster','here','glue','raster','Rtsne')


# ..... set-names
abund = "pa"
date.model.run = '2023'
varsName = 'vars11'
minocc = 6; period = "S1"

gis_in <- here::here('03_format_data','gis','raw_gis_data')
	
outputpath = here('04_Output')
	
datapath = here('01_HJA_scripts','08_sjsdm')
gis_out = here('03_format_data','gis')
	
modFolder = file.path(outputpath, "sjsdm_general_outputs", glue('{varsName}_{date.model.run}'))
resFolder = file.path(outputpath, "sjsdm_prediction_outputs", glue('{varsName}_{date.model.run}'))
plotFolder = file.path(outputpath, "prediction_map")


# ..... load-data
# load model data - for species classification
load(file.path(resFolder, paste0("modelData_",abund,".rdata")))
rm(device,env.vars,env.vars.test,iter,k,minocc,noSteps,otu.qp.csv,otu.qp.csv.test,otuenv,sampling,select.percent,spChoose,test.Names,train.Names,vars,varsName)
# otu.pa.csv, otu.qp.csv
	
## load species AUC resutls for filtering
load(file.path(resFolder, 'rdata', "sp_test_results.rdata")) # # sp.res.test, sp.res.train

	
## Mean AUC per species (and other eval metrics)
str(sp.res.test, max.level = 1)
head(sp.res.test$auc)
	
## Filter species by auc
auc.filt = 0.70
# threshold for presence absence data
# tr <- 0.5
	
# how many species after AUC filter?
sum(sp.res.test$auc > auc.filt, na.rm = T)
	
# incidence 
incidence = colSums(otu.pa.csv)/nrow(otu.pa.csv)
	
# clamp predictions
load(file.path(plotFolder, 'rdata', paste0("sjSDM_predictions_", "M1S1_", "min", minocc, "_", varsName, "_", abund, "_clamp", ".rdata")))
# pred.mn.cl, pred.sd.cl
	

dim(pred.mn.cl)

## filter for species performance
pred.in.cl = pred.mn.cl[,sp.res.test$auc > auc.filt & !is.na(sp.res.test$auc)]
	
## load raster templates
load(file.path(gis_out, "templateRaster.rdata")) ## r, indNA aoi.pred.sf, r.aoi.pred - reduced area for plotting
	

## clamp version
rList <- lapply(data.frame(pred.in.cl), function(x) {
  
  tmp <- r.msk
  tmp[indNA] <- x
  tmp
  
})
# plot(tmp)
rStack.cl = stack(rList)
rStack.cl
	
# ..... TSNE
## Full data set
Xmat <- pred.in.cl
r <- raster(rStack.cl)
NAs <- indNA
	
# pa version
# Xmat <- (pred.mod[indNA2, ] >= tr)*1
dim(Xmat)
Xmat[1:10, 1:10]
perplexity = 50			#
	
# Max
(nrow(Xmat) - 1)/3
tsne = Rtsne::Rtsne(Xmat, dims = 2, perplexity = perplexity, theta = 0.5, pca = FALSE, num_threads = 0) # can set parallel options if using openMP
	
# plot(tsne$Y, asp = 1, pch = ".")
# str(tsne, max.level =1)
# plot(tsne$Y, asp = 1)


## put site scores into raster
makeR <- function(r, siteScores, NAs) {
  
  rSites <- raster(r)
  rSites[] <- NA
  rSites[NAs] <- siteScores
  rSites
  
}
	
rSites1 <- makeR(r, tsne$Y[,1], NAs)
rSites2 <- makeR(r, tsne$Y[,2], NAs)

names(rSites1) <- "TSNE1"
names(rSites2) <- "TSNE2"

plot(stack(rSites1, rSites2))
# 

save(tsne, r, rSites1, rSites2, NAs, file = file.path(resFolder, "ord_tsne_res_cl_p50.rdata")) # with perp = 50

writeRaster(rSites1, filename = file.path(plotFolder, 'rdata', "tsne1_nopca_cl_p50.tif"), 
            datatype = "FLT4S", overwrite = T)
writeRaster(rSites2, filename = file.path(plotFolder, 'rdata', "tsne2_nopca_cl_p50.tif"), 
            datatype = "FLT4S", overwrite = T)
# 
	
# pdf(file.path(plotFolder, 'plot', "tsne_scatter_cl_p50.pdf"))
#plot(tsne$Y, pch = ".")
#dev.off()
	
