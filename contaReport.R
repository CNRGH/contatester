#!/usr/bin/env Rscript

#####
##### CrossHuman Contamination Estimator
#####

#
# Damien DELAFOY
# CEA-DRF-JACOB-CNRGH
#

#
# Usage :
# Estimate the contamination degree of a sample
# Output a csv file with contamination estimation
# optionaly output a report with graph
#


#############
### function
#############

merge_data <- function(fichiers){
    # used to import and merge data
    x_val = data.frame(X_val = as.double(as.character(seq(0,1,0.01))), valeurs = rep(0,101))
    for (proc_file in fichiers) {
        tab = read.table(proc_file, dec=".") 
        tab = data.frame(tab[,1], as.double(as.character(tab[,2])))
        colnames(tab) = c(basename(proc_file), "X_val")
        x_val = merge(x_val, tab, by="X_val", all=T)
    }
    return(x_val)
}

getFilename <- function() {
    # http://r.789695.n4.nabble.com/FILE-object-in-R-td4643884.html
    # return the full path of the runing script
    args <- commandArgs()
    filearg <- grep("^--file=", args, value=TRUE)
    if (length(filearg))
        sub("^--file=", "", filearg)
    else
        invisible(NULL)
}

###############
### Libraries
###############


library("optparse")
library("grid")
library("gridBase")
library("gridExtra")

#############
###   Main
#############

option_list <- list(
    make_option(c("-i", "--input"), action="store", type="character",
    default=NULL,
    help="Input file obtained with script CalculAllelicBalance.sh"),
    
    make_option(c("-o", "--output"), action="store", type="character", 
    default="<input>.conta",
    help="output file [default %default]"),
    
    make_option(c("-n", "--reportName"), action="store", type="character",
    default = "<input>.pdf",
    help="report name [default %default]"),
    
    make_option(c("-r", "--report"), action="store_true", type="logical", 
    default=FALSE,
    help="Create a pdf with Allele Balance Distribution and Sample correlation 
    with Dataset [default %default]")
)

parser <- OptionParser(usage = "Estimate the contamination degree of a sample\n
Output a csv file with contamination estimation\n
optionaly output a report with graph\n\n
usage: %prog [options]", option_list = option_list,
add_help_option = TRUE, prog = NULL, description = "", epilogue = "")

# Arguments recuperation
argv = parse_args(parser)


if (is.null(argv$input)){
    print("Input file is missing (--input)")
    quit(save="no", status=1, runLast=FALSE)
} else if (!file.exists((argv$input))) {
    print("Input file does not exist")
    quit(save="no", status=1, runLast=FALSE)
} else {
    filin = argv$input
}

if (argv$output == "<input>.conta") {
    basename_file = gsub(pattern = "\\.hist$", "", (basename(filin)))
    filout = paste(basename_file, ".conta", sep="")
} else {
    filout = argv$output
}

if (argv$reportName == "<input>.pdf") {
    basename_file = gsub(pattern = "\\.hist$", "", (basename(filin)))
    pdfout = paste(basename_file, ".pdf", sep="")
} else {
    pdfout = argv$report_name
}

scriptPath = dirname(getFilename())

# load dataset
load(paste(scriptPath, "contaIntraProjet.rda", sep="/"))

# Data Treatment 
sample_test = merge_data(filin)

d = cbind(contaIntraProjet[,-1], sample_test[,3])
colnames(d) = c(colnames(contaIntraProjet)[-1], colnames(sample_test)[3])

# Turn NA into 0
d <- replace(d, is.na(d), 0)

#data informations
nb_ref   = dim(d)[2]-1
i_sample = dim(d)[2]

# Conta degree 
pct_conta_num = as.numeric(gsub(".*_(.*)pctReal_.*", "\\1", 
                                colnames(d)[1:nb_ref], perl=TRUE))
xconta = pct_conta_num[order(pct_conta_num)]
X_val = contaIntraProjet[,1]

# Conta estimation with linear and polynomiale regression
# in range AB [0.34-0.49 ; 0.51-0.65]

# range index
i1min = 35
i1med = 50
i2med = 52
i2max = 66

# Sample ratio left hetero / right hetero
test_value = sum(d[i1min:i1med, i_sample])/sum(d[i2med:i2max, i_sample])

# linear model
ratio_hetero = colSums(d[i1min:i1med, 1:nb_ref]) / colSums(d[i2med:i2max, 1:nb_ref])
data_lm      = data.frame(xconta[xconta < 15], ratio_hetero[xconta < 15])
colnames(data_lm) = c("xconta","ratio_hetero")

model_lin   = lm(formula = xconta ~ ratio_hetero, data = data_lm)
lin_predict = predict(model_lin, data.frame(ratio_hetero=test_value))
if (lin_predict <= 15 ) {
    lin_predict_mod = paste(round(lin_predict, 2), "%", sep="")
} else {
    lin_predict_mod = "15% < x < 50%"
}

# polynomial regression
data_lm2 = data.frame(xconta, ratio_hetero)
colnames(data_lm2) = c("xconta","ratio_hetero")
model_2deg = lm(ratio_hetero ~ poly(xconta, 2, raw=TRUE), data = data_lm2)

coef_a = model_2deg$coefficients[3]
coef_b = model_2deg$coefficients[2]
coef_c = model_2deg$coefficients[1] - test_value

res_poly = as.numeric(round(polyroot(c(coef_c, coef_b, coef_a)), 2))
res_poly1 = paste(res_poly[1], "%", sep="")
if (res_poly[2] <= 50){
    res_poly2 = paste(res_poly[2], "%", sep="")
} else {
    res_poly2 = paste("x>50% (", res_poly[2], "%)", sep ="")
}

# make a table 
tab_hetero = cbind(lin_predict_mod, res_poly1, res_poly2) 

col_tab_hetero_plot = c("Percent Conta\nLinear Regression\n(Max. precision 15%) ", 
                        "Percent Conta\nPolynomial Regr.\n(1st Possibility)", 
                        "Percent Conta\nPolynomial Regr.\n(2nd Possibility)")
col_tab_hetero_csv = c("Percent Conta Linear Regression (Max. precision 15%) ", 
                       "Percent Conta Polynomial Regr. (1st Possibility)", 
                       "Percent Conta Polynomial Regr. (2nd Possibility)")
row_tab_hetero = c("AB [0.34-0.49 ; 0.51-0.65]") 

rownames(tab_hetero) = row_tab_hetero
colnames(tab_hetero) = col_tab_hetero_csv

# Correlation Calcul
# AB [0.01-0.3]
d_cor = d[2:31,] 
mcor_1tiers     = cor(d_cor)
ref_mcor_1tiers = mcor_1tiers[1:nb_ref, i_sample][1:4]
hit_mcor_1tiers = sort(mcor_1tiers[1:nb_ref, i_sample])[nb_ref:(nb_ref - 2)]

min_ref_1tiers  = sort(ref_mcor_1tiers)[1]
max_ref_1tiers  = sort(ref_mcor_1tiers)[4]
name_hit_1tiers = gsub(".*_(.*)pctReal_.*", "\\1", 
                       names(hit_mcor_1tiers[1]), perl=TRUE)

# AB [0.7-0.99]
d_cor = d[71:100,]
mcor_3tiers     = cor(d_cor)
ref_mcor_3tiers = mcor_3tiers[1:nb_ref, i_sample][1:4]
hit_mcor_3tiers = sort(mcor_3tiers[1:nb_ref, i_sample])[nb_ref:(nb_ref - 2)]

min_ref_3tiers  = sort(ref_mcor_3tiers)[1]
max_ref_3tiers  = sort(ref_mcor_3tiers)[4]
name_hit_3tiers = gsub(".*_(.*)pctReal_.*", "\\1", 
                       names(hit_mcor_3tiers[1]), perl=TRUE)

# AB [0.01-0.3 ; 0.7-0.99]
d_cor = d[c(2:31,71:100),]
mcor_1et3tiers     = cor(d_cor)
ref_mcor_1et3tiers = mcor_1et3tiers[1:nb_ref, i_sample][1:4]
hit_mcor_1et3tiers = sort(mcor_1et3tiers[1:nb_ref, i_sample])[nb_ref:(nb_ref - 2)]

min_ref_1et3tiers  = sort(ref_mcor_1et3tiers)[1]
max_ref_1et3tiers  = sort(ref_mcor_1et3tiers)[4]
name_hit_1et3tiers = gsub(".*_(.*)pctReal_.*", "\\1", 
                          names(hit_mcor_1et3tiers[1]), perl=TRUE)

tab_cor = cbind(c(round(min_ref_1tiers,3), round(min_ref_3tiers, 3),
                   round( min_ref_1et3tiers, 3)),
                 c(round(max_ref_1tiers, 3), round(max_ref_3tiers, 3), 
                   round(max_ref_1et3tiers, 3)),
                 c(round(hit_mcor_1tiers[1], 3), round(hit_mcor_3tiers[1], 3), 
                   round(hit_mcor_1et3tiers[1],3)),
                 c(name_hit_1tiers, name_hit_3tiers, name_hit_1et3tiers))

col_tab_cor_plot = c("Min. Cor.\nwith Ref.", "Max. Cor.\nwith Ref.", 
                     "Max. Cor.\nwith dataset", "Percent Conta.\nhit")
col_tab_cor_csv = c("Min. Cor. with Ref.", "Max. Cor. with Ref.", 
                 "Max. Cor. with dataset", "Percent Conta. hit")
row_tab_cor = c("AB [0.01-0.3]", "AB [0.7-0.99]", "AB [0.01-0.3 ; 0.7-0.99]") 

rownames(tab_cor) = row_tab_cor
colnames(tab_cor) = col_tab_cor_csv

### tab_res = results in one lane
# col_tab_res_csv = c(
# "Min. Cor. with Ref. AB [0.01-0.3]", "Max. Cor. with Ref. AB [0.01-0.3]", 
# "Max. Cor. with dataset AB [0.01-0.3]", "Percent Conta. hit AB [0.01-0.3]",
# "Min. Cor. with Ref. AB [0.7-0.99]", "Max. Cor. with Ref. AB [0.7-0.99]", 
# "Max. Cor. with dataset AB [0.7-0.99]", "Percent Conta. hit AB [0.7-0.99]",
# "Min. Cor. with Ref. AB [0.01-0.3 ; 0.7-0.99]", 
# "Max. Cor. with Ref. AB [0.01-0.3 ; 0.7-0.99]", 
# "Max. Cor. with dataset AB [0.01-0.3 ; 0.7-0.99]", 
# "Percent Conta. hit AB [0.01-0.3 ; 0.7-0.99]",
# "Percent Conta Linear Regression (Max. precision 15%) ", 
# "Percent Conta Polynomial Regr. (1st Possibility)", 
# "Percent Conta Polynomial Regr. (2nd Possibility)"
# )

# tab_res = c(round(min_ref_1tiers,3), round(max_ref_1tiers, 3), 
            # round(hit_mcor_1tiers[1], 3), name_hit_1tiers,
            # round(min_ref_3tiers, 3), round(max_ref_3tiers, 3), 
            # round(max_ref_3tiers, 3), name_hit_3tiers,
            # round( min_ref_1et3tiers, 3), round(hit_mcor_1et3tiers[1], 3), 
            # round(hit_mcor_1et3tiers[1],3), name_hit_1et3tiers,
            # lin_predict, res_poly[1], res_poly[2])
            
# colnames(tab_res) = col_tab_res_csv

if ( as.numeric(name_hit_1tiers) >= 5 && 
     as.numeric(name_hit_3tiers) >= 5 &&
     as.numeric(name_hit_1et3tiers) >= 5 &&
     round(lin_predict) >= 5 && round(res_poly[1]) >= 5) {
    conta_res = "Possible contamination greater than 5% : TRUE"
} else {
    conta_res = "Possible contamination greater than 5% : FALSE"
}

# save informations

write.table(tab_cor, file = filout, eol = "\n", quote = TRUE,col.names=TRUE, 
            row.names = TRUE, sep = ",")
oldw <- getOption("warn")
#stop warnings
options(warn = -1)
write.table(tab_hetero, file = filout, eol = "\n", quote = TRUE, 
          row.names = TRUE, sep = ",",  append = TRUE)
          # Warning message:
          # In write.table(tab_hetero, file = filout, eol = "\n", quote = TRUE,  :
          # appending column names to file
#restore warnings
options(warn = oldw)
cat(conta_res, file = filout, eol = "\n", append = TRUE)



# write.table(tab_res, file = paste(filout, ".raw", sep=""), eol = "\n", 
            # quote = TRUE,col.names=TRUE, row.names = TRUE, sep = ",")



# Plot if flag report is True

if (argv$report) {
    ### Debut enregistrement PDF
    pdf(pdfout,
        height = 11.7,
        width  = 8.3 ,
        paper="a4",)
    
    par(mfrow = c(3,1))
    # information for plotting
    pct_conta_num = as.numeric(gsub(".*_(.*)pctReal_.*", "\\1", 
                                    colnames(d)[1:nb_ref], 
                                    perl=TRUE))
    xconta = pct_conta_num[order(pct_conta_num)]
    ref_col = grep("_0pctReal", colnames(d))
    ### Plot Allele Balance Distribution
        plot(X_val, d[,dim(d)[2]], 
         type = "l", 
         ylim = c(0,175000), 
         col = "blue",
         main = "Allele Balance Distribution",
         xlab = "Allele Balance", ylab="Observation Number",)
    # add uncontaminated reference to graphique
    for ( ref in ref_col ) {
        lines(X_val, d[,ref], col="darkgreen",)
    }
    
    abline(v=c(1/8, 1/6, 1/4, 1/3, 1/2, 2/3, 3/4, 5/6, 7/8), col= "red", lty=3)
    legend("topleft", legend=c("Sample", "References\n(700M 2x150pb reads)"), 
           col=c("blue", "darkgreen"),
           lty=1, cex=1, bty="n", horiz = FALSE, ncol=1, border=NULL)
    
    # Add main title to report
    mtext(basename(filin), outer=TRUE,  cex=1.25, line=-1.5)
    
    ### Plot correlation 
    legende_info  = c("AB [0.7:0.99]", "AB [0.01:0.3]", "AB [0.01:0.3 ; 0.7:0.99]")
    legende_color = c("blue", "purple", "darkgreen" )
    # AB [0.7:0.99]
    plot(xconta, mcor_3tiers[1:nb_ref, i_sample], 
         pch=4,
         ylim=c(-1,1), xlim=c(0,50),
         col=legende_color[1],
         xlab="Percent contamination", ylab="Correlation", 
         main = "Sample Correlation to Simulated CrossHuman Contamination Dataset" )
    # AB [01:0.3]
    points(xconta, mcor_1tiers[1:nb_ref, i_sample], 
           pch=4, col = legende_color[2])
    # AB [0.01:0.3 ; 0.7:0.99]
    points(xconta, mcor_1et3tiers[1:nb_ref, i_sample],
           pch=4, col = legende_color[3])
    
    #add axis and lines
    axis(side=1,at=c(1,2.5,5,7.5,15,25,35,45), labels=c(1,2.5,5,7.5,15,25,35,45))
    abline(v=c(0,1, 2.5, 5, 7.5, 10, 15, 20, 25, 30, 35, 40, 45), 
           col= "gray", lty=3)
    axis(side=2,at=c(0.9, 0.95), labels=c(0.9,0.95), las=2)
    abline(h=c(0.9, 0.95, 1, 0), col= "red", lty=3)
    
    legend("bottomleft", legend=legende_info, 
           col=legende_color,
           pch=4, cex=1, bty="n", horiz = FALSE, border=NULL)
    
    # Table results 
    plot.new()
    tgrob1 = tableGrob(tab_cor, rows = rownames(tab_cor), 
                       cols = col_tab_cor_plot,
                       theme = ttheme_default(), vp = NULL)
    tgrob2 = tableGrob(tab_hetero, rows = rownames(tab_hetero), 
                       cols = col_tab_hetero_plot,
                       theme = ttheme_default(), vp = NULL)
    grid.arrange(tgrob1, tgrob2, nrow = 2, newpage = F, 
                 vp=baseViewports()$figure)
    
    ### Fin enregistrement PDF
    dev.off()
}
