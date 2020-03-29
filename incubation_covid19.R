library("coarseDataTools")
library("lubridate")

# this code can be improved - mainly stylistically - using tidyverse 
# load the Nature Scientific Dataset
latest <- read.csv("https://raw.githubusercontent.com/beoutbreakprepared/nCoV2019/master/latest_data/latestdata.csv")

# pre-process dates as strings 
latest$date_admission_hospital = as.character(latest$date_admission_hospital)
latest$date_confirmation = as.character(latest$date_confirmation)
latest$date_onset_symptoms = as.character(latest$date_onset_symptoms)
latest$travel_history_dates = as.character(latest$travel_history_dates)

# identify data points with reported dates for onset symptoms and travel history (to/from Wuhan) dates
ind <- which(latest$date_onset_symptoms != "" & latest$travel_history_dates != "" & latest$wuhan.0._not_wuhan.1. == 1)
covidlatest = latest[ind,]

ncov_inc = data.frame(EL_date = as.character(rep("-",dim(covidlatest)[1])))
# keep only people that do not live in Wuhan. This will trim the dataset quiet considerably but we can have better knowledge of their exposure dates
ind <- which(as.character(covidlatest$lives_in_Wuhan) == "no")

#the earliest (left) date of exposure is set to their earliest travel date to Wuhan if known, otherwise it is set to 01/12/2019, which is the first date 
EL_date = c()

for (i in 1:dim(covidlatest)[1]){
  if (i %in% ind){
    EL_date = append(EL_date, strsplit(covidlatest[i,]$travel_history_dates,", | - |- | -")[[1]][1])
  }else{
    EL_date = append(EL_date,"01.12.2019")
  }
}

ncov_inc$EL_date = EL_date
ncov_inc[which(ncov_inc$EL_date == ""),] = "01.12.2019"

#the latest (right) exposure date is set to the latest day of travel if known. Otherwise is set to the day of symptoms onset

ncov_inc$ER_date = covidlatest$date_onset_symptoms

for (i in 1:length(ind)){
  ncov_inc[ind[i],]$ER_date = strsplit(covidlatest[ind[i],]$travel_history_dates,", | - |- | -")[[1]][length(strsplit(covidlatest[ind[i],]$travel_history_dates,", | - |- | -")[[1]])]
}

#all cases have a single day of onset symptoms reported 
ncov_inc$SL_date = covidlatest$date_onset_symptoms
ncov_inc$SR_date = covidlatest$date_onset_symptoms

#this entry has a formating incosistency (so it is "manually" fixed)
ncov_inc[51,]$ER_date = "25.02.2020"
ncov_inc[51,]$SL_date = "25.02.2020"
ncov_inc[51,]$SR_date = "25.02.2020"

#conforming with the format of the data in the original study by Lauer et al. 
ncov_inc$EL = as.numeric(difftime(as.Date(ncov_inc$EL_date,"%d.%m.%Y"),ymd_hms("2019-12-01 00:00:00"), units="days"))
ncov_inc$ER = as.numeric(difftime(as.Date(ncov_inc$ER_date,"%d.%m.%Y"),ymd_hms("2019-12-01 00:00:00"), units="days"))
ncov_inc$SL = as.numeric(difftime(as.Date(ncov_inc$SL_date,"%d.%m.%Y"),ymd_hms("2019-12-01 00:00:00"), units="days"))
ncov_inc$SR = as.numeric(difftime(as.Date(ncov_inc$SR_date,"%d.%m.%Y"),ymd_hms("2019-12-01 00:00:00"), units="days"))
ncov_inc$E_int=ncov_inc$ER-ncov_inc$EL
ncov_inc$S_int=ncov_inc$SR-ncov_inc$SL
ncov_inc$type=as.numeric(ncov_inc$S_int==0) + as.numeric(ncov_inc$E_int==0)
ncov_inc$Wuhan = covidlatest$lives_in_Wuhan
ncov_inc_Xu = ncov_inc
#load data from Lauer study - ncov_inc_dat data frame from https://github.com/HopkinsIDD/ncov_incubation/blob/master/manuscript/nCoV_Incubation.Rmd
ncov_inc_Lauer = read.csv("ncov_inc_dat_Lauer.csv")



#merge the two datasets
EL = c(ncov_inc_Xu$EL, ncov_inc_Lauer$EL)
ER = c(ncov_inc_Xu$ER, ncov_inc_Lauer$ER)
SL = c(ncov_inc_Xu$SL, ncov_inc_Lauer$SL)
SR = c(ncov_inc_Xu$SR, ncov_inc_Lauer$SR)
type = c(ncov_inc_Xu$type, ncov_inc_Lauer$type)
all = data.frame(EL=EL, ER=ER, SL=SL, SR=SR, type= type)
#remove incosistent data - possibly due to reporting errors
all = all[-which(all$EL > all$SL),]
all = all[-which(all$type == 2 & all$EL == all$SL),]

inc_lognormal_boot <- dic.fit(all,dist="L", n.boots=1000,ptiles = c(0.025, 0.25, 0.5, 0.75, 0.975))

#plots (code replicated from Lauer et al.) 

ci.col <- rgb(230/255,85/255,13/255,1)
plot(inc_lognormal_boot, ylab="Proportion symptomatic cases with symptoms",
     xlab="Days after infection", main="", xlim=c(0,20))
points(y=rep(0.025,2), x=c(inc_lognormal_boot@ests['p2.5','CIlow'], inc_lognormal_boot@ests['p2.5','CIhigh']), type='l', col=ci.col, lwd=2.5)
points(y=rep(0.5,2), x=c(inc_lognormal_boot@ests['p50','CIlow'], inc_lognormal_boot@ests['p50','CIhigh']), type='l', col=ci.col, lwd=2.5)
points(y=rep(0.975,2), x=c(inc_lognormal_boot@ests['p97.5','CIlow'], inc_lognormal_boot@ests['p97.5','CIhigh']), type='l', col=ci.col, lwd=2.5)

knitr::kable(inc_lognormal_boot@ests[,-4])
exp_val <- exp(inc_lognormal_boot@ests["meanlog", "est"]+0.5*(inc_lognormal_boot@ests["sdlog", "est"])^2)
print(paste("The estimated mean is", exp_val))
