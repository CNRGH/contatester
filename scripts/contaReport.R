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

###############
### Libraries
###############


library("optparse")
library("grid")
library("gridBase")
library("gridExtra")

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

argv_mod <- function(argv){
    if (is.null(argv$input)){
        print("Input file is missing (--input)")
        #quit(save="no", status=1, runLast=FALSE)
    } else if (!file.exists((argv$input))) {
        print("Input file does not exist")
        #quit(save="no", status=1, runLast=FALSE)
    }
    
    if (argv$output == "<input>.conta") {
        basename_file = gsub(pattern = "\\.hist$", "", (basename(argv$input)))
        argv$output = paste(basename_file, ".conta", sep="")
    }
    
    if (argv$reportName == "<input>.pdf") {
        basename_file = gsub(pattern = "\\.hist$", "", (basename(argv$input)))
        argv$reportName = paste(basename_file, ".pdf", sep="")
    }
    return(argv)
}

reg_data <- function(d, i1min, i1med, i2med, i2max){
    #data informations
    nb_ref   = dim(d)[2]-1
    i_sample = dim(d)[2]
    # Sample ratio left hetero / right hetero
    test_value = sum(d[i1min:i1med, i_sample])/sum(d[i2med:i2max, i_sample])
    # data for regression
    ratio_hetero = colSums(d[i1min:i1med, 1:nb_ref]) / colSums(d[i2med:i2max, 
                                                                 1:nb_ref])
    return(list("ratio_hetero" = ratio_hetero, "test_value" = test_value))
}

lm_reg <- function(xconta, ratio_hetero, test_value, max_conta=15){
    # linear model
    data_lm      = data.frame(xconta[xconta <= max_conta], ratio_hetero[xconta <= max_conta])
    colnames(data_lm) = c("xconta","ratio_hetero")
    
    model_lin   = lm(formula = xconta ~ ratio_hetero, data = data_lm)
    lin_predict = predict(model_lin, data.frame(ratio_hetero=test_value))
    if (lin_predict <= max_conta ) {
        lin_predict_mod = paste(round(lin_predict, 2), "%", sep="")
    } else {
        lin_predict_mod = paste(max_conta ,"% < x < 50%", sep="")
    }
    return(list("lin_predict" = lin_predict, "lin_predict_mod" = lin_predict_mod, 
           "model_lin" = model_lin, "data_lm"=data_lm))
}

poly_reg <- function(xconta, ratio_hetero, test_value){
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
    
    return(list("res_poly" = res_poly, "res_poly1" = res_poly1, 
                "res_poly2" = res_poly2, "model_2deg" = model_2deg, 
                "data_lm2" = data_lm2))
}

# conta_result <- function(name_hit_1tiers, name_hit_3tiers, name_hit_1et3tiers, 
#                          lin_predict, res_poly){
#     #' Conditionnal treatment for the contamination's estimation 
#     
#     if ( as.numeric(name_hit_1tiers) >= 5 && 
#          as.numeric(name_hit_3tiers) >= 5 &&
#          as.numeric(name_hit_1et3tiers) >= 5 &&
#          round(lin_predict) >= 5 && round(res_poly[1]) >= 5) {
#         conta_res = "Possible contamination greater than 5% : TRUE"
#     } else {
#         conta_res = "Possible contamination greater than 5% : FALSE"
#     }
#     return(conta_res)
# }
conta_result <- function(res_poly, conta_seuil){
    #' Conditionnal treatment for the contamination's estimation 
    
    if ( round(res_poly$res_poly[1]) >= conta_seuil) {
        conta_res = paste("Possible contamination greater than ", conta_seuil, 
                          "% : TRUE", sep="")
    } else {
        conta_res = paste("Possible contamination greater than ", conta_seuil, 
                          "% : FALSE", sep="")
    }
    return(conta_res)
}

cor_calc <- function(d, d_range){
    nb_ref   = dim(d)[2]-1
    i_sample = dim(d)[2]
    d_cor    = d[d_range,] 
    mcor     = cor(d_cor)
    ref_mcor = mcor[1:nb_ref, i_sample][1:4]
    hit_mcor = sort(mcor[1:nb_ref, i_sample])[nb_ref:(nb_ref - 2)]
    min_ref  = sort(ref_mcor)[1]
    max_ref  = sort(ref_mcor)[4]
    name_hit = gsub(".*_(.*)pctReal_.*", "\\1", 
                    names(hit_mcor[1]), perl=TRUE)
    return(list("hit_mcor" = hit_mcor, "min_ref" = min_ref,
                "max_ref"  = max_ref, "name_hit" = name_hit, "mcor" = mcor))
}

make_tab_cor <- function(hit_mcor_1tiers, min_ref_1tiers, max_ref_1tiers, name_hit_1tiers, 
                         hit_mcor_3tiers, min_ref_3tiers, max_ref_3tiers, name_hit_3tiers,
                         hit_mcor_1et3tiers, min_ref_1et3tiers, max_ref_1et3tiers, name_hit_1et3tiers,
                         cor_range1, cor_range2, cor_range3){
    #' Correlation result formating
    # correlation result table 
    
    tab_cor = cbind(c(round(min_ref_1tiers,3), 
                      round(min_ref_3tiers, 3),
                      round( min_ref_1et3tiers, 3)),
                    c(round(max_ref_1tiers, 3), 
                      round(max_ref_3tiers, 3), 
                      round(max_ref_1et3tiers, 3)),
                    c(round(hit_mcor_1tiers[1], 3), 
                      round(hit_mcor_3tiers[1], 3), 
                      round(hit_mcor_1et3tiers[1],3)),
                    c(name_hit_1tiers, 
                      name_hit_3tiers, 
                      name_hit_1et3tiers))
    
    col_tab_cor_plot = c("Min. Cor.\nwith Ref.", "Max. Cor.\nwith Ref.", 
                         "Max. Cor.\nwith dataset", "Percent Conta.\nhit")
    col_tab_cor_csv = c("Min. Cor. with Ref.", "Max. Cor. with Ref.", 
                        "Max. Cor. with dataset", "Percent Conta. hit")

    row_tab_cor = c(cor_range1, cor_range2, cor_range3)
    
    rownames(tab_cor) = row_tab_cor
    colnames(tab_cor) = col_tab_cor_csv
    
    return(list("tab_cor" = tab_cor, "col_tab_cor_plot" = col_tab_cor_plot))
}

tab_cor_oneLane <- function(hit_mcor_1tiers, min_ref_1tiers, max_ref_1tiers, name_hit_1tiers, 
                            hit_mcor_3tiers, min_ref_3tiers, max_ref_3tiers, name_hit_3tiers,
                            hit_mcor_1et3tiers, min_ref_1et3tiers, max_ref_1et3tiers, name_hit_1et3tiers,
                            cor_range1, cor_range2, cor_range3, lin_predict, res_poly){
    #' result formating
    #' return result in one lane
    
    tab_res = c(paste("Min. Cor. with Ref.", cor_range1), round(as.double(min_ref_1tiers),3),                 
                paste("Max. Cor. with Ref.", cor_range1), round(as.double(max_ref_1tiers), 3),                 
                paste("Max. Cor. with dataset", cor_range1), round(as.double(hit_mcor_1tiers[1]), 3),                
                paste("Percent Conta. hit", cor_range1), name_hit_1tiers,                
                paste("Min. Cor. with Ref.", cor_range2), round(as.double(min_ref_3tiers), 3),                 
                paste("Max. Cor. with Ref.", cor_range2), round(as.double(max_ref_3tiers), 3),                 
                paste("Max. Cor. with dataset", cor_range2), round(as.double(max_ref_3tiers), 3),                 
                paste("Percent Conta. hit", cor_range2), name_hit_3tiers,                
                paste("Min. Cor. with Ref.", cor_range3), as.double(round( min_ref_1et3tiers), 3),                 
                paste("Max. Cor. with Ref.", cor_range3), as.double(round(hit_mcor_1et3tiers[1]), 3),                 
                paste("Max. Cor. with dataset", cor_range3), as.double(round(hit_mcor_1et3tiers[1]),3),                 
                paste("Percent Conta. hit", cor_range3), as.double(name_hit_1et3tiers),                
                paste("Percent Conta Linear Regression (Max. precision 15%) "), lin_predict,                 
                paste("Percent Conta Polynomial Regr. (1st Possibility)"), res_poly$res_poly[1], 
                paste("Percent Conta Polynomial Regr. (2nd Possibility)"), res_poly$res_poly[2]
                )
    
    return(tab_res)
}

make_tab_hetero <- function(lin_predict_mod, res_poly1, res_poly2, i1min, i1med,
                            i2med, i2max){
    #' regression result table formating
    
    tab_hetero = cbind(lin_predict_mod, res_poly1, res_poly2) 
    
    col_tab_hetero_plot = c("Percent Conta\nLinear Regression\n(Max. precision 15%) ", 
                            "Percent Conta\nPolynomial Regr.\n(1st Possibility)", 
                            "Percent Conta\nPolynomial Regr.\n(2nd Possibility)")
    col_tab_hetero_csv = c("Percent Conta Linear Regression (Max. precision 15%) ", 
                           "Percent Conta Polynomial Regr. (1st Possibility)", 
                           "Percent Conta Polynomial Regr. (2nd Possibility)")
    #row_tab_hetero = c("AB [0.34-0.49 ; 0.51-0.65]") 
    row_tab_hetero = c(paste("AB [",(i1min-1)/100,"-", (i1med-1)/100,
                             " ; ", (i2med-1)/100,"-", (i2max-1)/100,"]", sep="")) 
    rownames(tab_hetero) = row_tab_hetero
    colnames(tab_hetero) = col_tab_hetero_csv
    return(list("tab_hetero" = tab_hetero, 
                "col_tab_hetero_plot" = col_tab_hetero_plot))
}

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
                help=paste("Create a pdf with Allele Balance Distribution",
                           "and Sample correlation with Dataset",
                           "[default %default]"))
)

parser <- OptionParser(usage = 
                       paste("Estimate the contamination degree of a sample\n",
                             "Output a csv file with contamination estimation\n",
                             "optionaly output a report with graph\n\n",
                             "usage: %prog [options]"), 
                       option_list = option_list,
                       add_help_option = TRUE, prog = NULL, description = "", 
                       epilogue = ""
)

# Arguments recuperation
argv = parse_args(parser)
argv = argv_mod(argv)

filin = argv$input
filout = argv$output
pdfout = argv$reportName

scriptPath = dirname(getFilename())
datadir = paste(scriptPath, "/../share/contatester")

# load dataset
load(paste(datadir, "contaIntraProjet.rda", sep="/"))

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

#range index for Correlation calculation
i1min_cor = 2
i1med_cor = 31
i2med_cor = 71
i2max_cor = 100

# range index for regression calculation
i1min = 19
i1med = 50
i2med = 52
i2max = 83

# Conta estimation with linear and polynomiale regression
# in range AB [0.34-0.49 ; 0.51-0.65]

reg_d = reg_data(d, i1min, i1med, i2med, i2max)

ratio_hetero = reg_d$ratio_hetero
test_value   = reg_d$test_value

# lineare prediction 
lin_pred = lm_reg(xconta, ratio_hetero, test_value)
lin_predict_mod = lin_pred$lin_predict_mod
lin_predict = lin_pred$lin_predict
model_lin = lin_pred$model_lin


# polynomial prediction
res_poly  = poly_reg(xconta, ratio_hetero, test_value)
res_poly1 = res_poly$res_poly1
res_poly2 = res_poly$res_poly2
model_2deg = res_poly$model_2deg


# make a table for resultats
res_hetero = make_tab_hetero(lin_predict_mod, res_poly1, res_poly2, i1min, i1med,
                                         i2med, i2max)
tab_hetero = res_hetero$tab_hetero 
col_tab_hetero_plot = res_hetero$col_tab_hetero_plot

# Correlation Calcul

# AB [0.01-0.3]
mcor = cor_calc(d, c(i1min_cor:i1med_cor))
mcor_1tiers = mcor$mcor
hit_mcor_1tiers = mcor$hit_mcor
min_ref_1tiers  = mcor$min_ref
max_ref_1tiers  = mcor$max_ref
name_hit_1tiers = mcor$name_hit

# AB [0.7-0.99]
mcor = cor_calc(d, c(i2med_cor:i2max_cor))
mcor_3tiers = mcor$mcor
hit_mcor_3tiers = mcor$hit_mcor
min_ref_3tiers  = mcor$min_ref
max_ref_3tiers  = mcor$max_ref
name_hit_3tiers = mcor$name_hit

# AB [0.01-0.3 ; 0.7-0.99]
mcor = cor_calc(d, c(i2med_cor:i2max_cor, i2med_cor:i2max_cor))
mcor_1et3tiers = mcor$mcor
hit_mcor_1et3tiers = mcor$hit_mcor
min_ref_1et3tiers  = mcor$min_ref
max_ref_1et3tiers  = mcor$max_ref
name_hit_1et3tiers = mcor$name_hit

cor_range1 = paste("AB [", (i1min_cor-1)/100, "-", (i1med_cor-1)/100, "]", sep="") 
cor_range2 = paste("AB [", (i2med_cor-1)/100, "-", (i2max_cor-1)/100, "]", sep="") 
cor_range3 = paste("AB [", (i1min_cor-1)/100, "-",(i1med_cor-1)/100 ," ; ", 
                   (i2med_cor-1)/100, "-", (i2max_cor-1)/100, "]", sep="")

res_cor = make_tab_cor(hit_mcor_1tiers, min_ref_1tiers, max_ref_1tiers, name_hit_1tiers, 
                        hit_mcor_3tiers, min_ref_3tiers, max_ref_3tiers, name_hit_3tiers,
                        hit_mcor_1et3tiers, min_ref_1et3tiers, max_ref_1et3tiers, name_hit_1et3tiers,
                        cor_range1, cor_range2, cor_range3)
tab_cor = res_cor$tab_cor
col_tab_cor_plot = res_cor$col_tab_cor_plot

# Test if more than 5% conta 
# conta_res = conta_result(name_hit_1tiers, name_hit_3tiers, name_hit_1et3tiers, 
#                          lin_predict, res_poly[1])

# Test if more than 4% conta 
conta_res = conta_result(res_poly[1], 4)


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
    ref_col = grep("_0pctReal", colnames(d))
    ### Plot Allele Balance Distribution
        plot(X_val, d[,dim(d)[2]], 
         type = "l", 
         ylim = c(0,175000), 
         col  = "blue",
         main = "Allele Balance Distribution",
         xlab = "Allele Balance", ylab="Observation Number",)
    # add uncontaminated reference to graphique
    for ( ref in ref_col ) {
        lines(X_val, d[,ref], col="darkgreen")
    }
    
    abline(v=c(1/8, 1/6, 1/4, 1/3, 1/2, 2/3, 3/4, 5/6, 7/8), col= "red", lty=3)
    legend("topleft", legend=c("Sample", "References\n(700M 2x150pb reads)"), 
           col=c("blue", "darkgreen"),
           lty=1, cex=1, bty="n", horiz = FALSE, ncol=1, border=NULL)
    
    # Add main title to report
    mtext(basename(filin), outer=TRUE,  cex=1.25, line=-1.5)
    
    ### Plot correlation 
    #legende_info  = c(cor_range1, cor_range2, cor_range3)
    legende_info  = rownames(tab_cor)
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
    axis(side=1,at=c(1,2.5,5,7.5,15,25,35,45), 
         labels=c(1,2.5,5,7.5,15,25,35,45))
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
