## calculate TSS (true skill statistic) by reviewer's request


```{r setup}
rm(list=ls())
#setwd('~/Music/HJA_analyses_Kelpie_clean/01_HJA_scripts/08_sjsdm')
	
pacman::p_load('tidyverse','here','conflicted','reticulate','sjSDM','glue','pROC', 'gridExtra','ggeffects','cowplot','graphics', 'MuMIn', 'ggpmisc') 	
	
conflict_prefer("filter", "dplyr")
conflict_prefer("select", "dplyr")
conflict_prefer('colSums', 'base')
	
here()
packageVersion('sjSDM')
# [1] ‘1.0.1’ 2022.04.19
	
source(here("source",'scale-train-test.r'))
	

```

```{r set-names}
period = "S1"
date.model.run = '20210722'
abund = 'pa'
varsName = 'vars11'
minocc = 6
k = 5 		# 5-folds
cv = '5CV'; nstep=1000
	
# ....... folder structure .......
predpath = here('..','..', '04_Output', 'sjsdm_prediction_outputs', glue('{varsName}_{date.model.run}'))
modpath = here('..','..', '04_Output', "sjsdm_general_outputs", glue('{varsName}_{date.model.run}'))
sppdatapath = here('..','..','03_format_data','otu')
	
sjsdmV = '0.1.6'
	

```


```{r load-data}
# data for tuning from rdata 
load(here(sppdatapath, glue('fortuning_data_{period}_random_min{minocc}_{date.model.run}_{varsName}.rdata')))
	
# ... OTU data need to be matrix form for sjSDM
if (abund=='pa') {
	m.otu.train = as.matrix(otu.pa.train) %>% unname
	m.otu.test = as.matrix(otu.pa.test) %>% unname
}
	
str(m.otu.train)
	

```

```{r add TSS all}

if(abund == "pa") {
	family = stats::binomial('probit')
	sampling = 5000L; device = 'gpu'
#	sampling = 50L; device = 'cpu'
#	iter = 17L
	iter = 170L; otu.train = m.otu.train} else stop("check abund")
	
# read-in filled 'tune.results'
tune.results = read.table(file.path(modpath,'tuning', paste0("manual_tuning_sjsdm_",sjsdmV, "_", varsName, "_", k, 'CV_', period, "_", abund, "_min", minocc, "_nSteps", nstep, ".csv")), header = T, sep = ',')
	
# add TSS column
tune.results = tune.results %>% add_column(tss.valid = NA, .after = 'cor.valid') %>% add_column(tss.train = NA, .before = 'k')
	
# ..... add TSS .....
for (i in seq_len(k)) {
	## select training (4 folds) and validation (1 fold) & scale 
	t.env.train = env.train[fold.id != i, ]
	t.env.valid = env.train[fold.id == i, ]
	
	t.otu.train = otu.train[fold.id != i,]
	t.otu.valid = otu.train[fold.id == i,]
	
	t.XY.train = XY.train[fold.id != i, ]
	t.XY.valid = XY.train[fold.id == i, ]
	## ... scale with source code
	a = scale.dd(t.env.train, t.env.valid)
	t.env.train = a[[1]]; t.env.valid = a[[2]]
	
	a = scale.dd(t.XY.train, t.XY.valid)
	t.XY.train = a[[1]]; t.XY.valid = a[[2]]
	rm(a)
	
	for(j in seq_len(nstep)) {
		print(c(i, j))
		## read-in each model
		readRDS(file.path(modpath,'tuning',
				paste0("s-jSDM_tuning_model_", varsName, "_", k, "CV_", i, "_tr_", j, "_", abund, ".rds")))		# model.train
		
		for (pred in c('train','valid')) {
			if (pred == 'valid') {
				newdd = t.env.valid; newsp = t.XY.valid; otudd = t.otu.valid }
			if (pred == 'train') {
				newdd = NULL; newsp = NULL; otudd = t.otu.train }
			# predict for all species = sites X columns
			pred.dd = apply(abind::abind(lapply(1:3, function(i) {
							predict(model.train, newdata = newdd, SP = newsp) }
					  ),along = -1L), 2:3, mean) %>% unname
			
			# convert observed to pa (if qp)
			otudd.pa = (otudd>0)*1
			# Extra evaluation metrics
			# add TSS (true skill statistic) for spp 
			rsq = data.frame(tss = rep(NA, length.out = ncol(pred.dd)) )
			
			for (m in 1:ncol(pred.dd)) { 
				p = pred.dd[ ,m]; y = otudd.pa[ ,m]
				tppp = sum(p*y)				# true presence
				fppp = sum(p*(1-y))			# false presence
				fapp = sum((1-p)*y)			# false absence 
				tapp = sum((1-p)*(1-y))		# true absence
				rsq$tss[m] = (tppp+tapp)/(tppp+fppp+tapp+fapp) 
			}
			
			if (pred == 'train') {
				tune.results$tss.train[tune.results$k == i][j] = mean(rsq$tss, na.rm = T)
			}
			  
			if (pred == 'valid') {
				tune.results$tss.valid[tune.results$k == i][j] = mean(rsq$tss, na.rm = T)
			}
		}
		rm(model.train)
	}
} # end of model loop
	
head(tune.results)
		

```

```{r add TSS best}

for (i in seq_len(k)) {
	## select training (4 folds) and validation (1 fold) & scale 
	t.env.train = env.train[fold.id != i, ]
	t.env.valid = env.train[fold.id == i, ]
	
	t.otu.train = otu.train[fold.id != i,]
	t.otu.valid = otu.train[fold.id == i,]
	
	t.XY.train = XY.train[fold.id != i, ]
	t.XY.valid = XY.train[fold.id == i, ]
	## ... scale with source code
	a = scale.dd(t.env.train, t.env.valid)
	t.env.train = a[[1]]; t.env.valid = a[[2]]
	
	a = scale.dd(t.XY.train, t.XY.valid)
	t.XY.train = a[[1]]; t.XY.valid = a[[2]]
	rm(a)
	

	
