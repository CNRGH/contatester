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

library("grid")
library("gridBase")
library("gridExtra")
library("optparse")


### DEBUG
# argv=list()
# argv[["input"]] = "/home/delafoy/C000VP03/C000VP0.hist"
# argv[["output"]] = "/home/delafoy/C000VP04/C000VP0.hist.conta"
# argv[["depth"]] = 30
# #argv[["depth"]] = 60
# argv[["experiment"]] = "WG"
# argv[["report"]] = TRUE
# argv[["reportName"]] = "/home/delafoy/C000VP04/C000VP0.hist.pdf"
# 
# scriptPath = "/home/delafoy/2019_optim_contatester/Rdataset"
# datadir = "/home/delafoy/2019_optim_contatester/Rdataset"


####################
###   Function   ###
####################


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

dataset_depth <- function(depth, experiment){
    # function for choosing which dataset is use with the data
    if (experiment == "WG" && depth <= 45){
        depthtest = 30
    } else if (depth <= 75){
        depthtest = 60
    } else if (depth > 75){
        depthtest = 90
    }
    return(depthtest)
}

replace_na <- function(d){
    return(replace(d, is.na(d), 0))
}

# reg_data = ratio_hetero
ratio_hetero <- function(d, i1min, i1med, i2med, i2max){
    # data informations
    # Sample ratio left hetero / right hetero
    # data for regression
    ratio_het = colSums(d[i1min:i1med, ]) / colSums(d[i2med:i2max, ])
    return(ratio_het)
}

lm_reg <- function(xconta, ratio_hetero, max_conta){
    # linear model
    data_lm      = data.frame(xconta[xconta <= max_conta], ratio_hetero[xconta <= max_conta])
    colnames(data_lm) = c("xconta","ratio_hetero")
    
    model_lin   = lm(formula = xconta ~ ratio_hetero, data = data_lm)
    return(list("model_lin" = model_lin, "data_lm"=data_lm))
}

lm_reg_predict <- function(model_lin, test_value){
    # linear model
    #     data_lm      = data.frame(xconta[xconta <= max_conta], ratio_hetero[xconta <= max_conta])
    #     colnames(data_lm) = c("xconta","ratio_hetero")
    #     
    #     model_lin   = lm(formula = xconta ~ ratio_hetero, data = data_lm)
    lin_predict = predict(model_lin, data.frame(ratio_hetero=test_value))
    return(lin_predict)
}

lin_predict_modif <- function(lin_predict, max_conta){
    if (lin_predict <= max_conta ) {
        lin_predict_mod = paste(round(lin_predict, 2), "%", sep="")
    } else {
        conta = paste(round(lin_predict, 2), "%", sep="")
        lin_predict_mod = paste(max_conta ,"% < x < 50% (", conta, ")", sep="")
    }
    return(lin_predict_mod)
}


poly_reg <- function(xconta, ratio_hetero){
    # polynomial regression
    data_reg = data.frame(xconta, ratio_hetero)
    colnames(data_reg) = c("xconta","ratio_hetero")
    model_2deg = lm(ratio_hetero ~ poly(xconta, 2, raw=TRUE), data = data_reg)
    #     coef_a = model_2deg$coefficients[3]
    #     coef_b = model_2deg$coefficients[2]
    #     coef_c = model_2deg$coefficients[1]
    return(list("model_2deg" = model_2deg, 
                "data_reg" = data_reg))
}

poly_reg_predict <- function(model_2deg, test_value){
    # polynomial regression
    coef_a = model_2deg$coefficients[3]
    coef_b = model_2deg$coefficients[2]
    coef_c = model_2deg$coefficients[1] - test_value
    
    res_poly = as.numeric(round(polyroot(c(coef_c, coef_b, coef_a)), 2))
    
    return(res_poly)
}

poly_reg_predict_modif <- function(res_poly){
    
    res_poly1 = paste(res_poly[1], "%", sep="")
    #     if (res_poly[2] <= 50){
    #         res_poly2 = paste(res_poly[2], "%", sep="")
    #     } else {
    #         res_poly2 = paste("x>50% (", res_poly[2], "%)", sep ="")
    #     }
    #     return(list("res_poly1" = res_poly1, 
    #                 "res_poly2" = res_poly2))
    return(res_poly1)
}

data_obj <- function (sample_test, dataset, cor_param, lin_reg_param, poly_reg_param) {
    # data formating
    d = list("sample_test" = replace_na(sample_test),
             "X_val"       = sample_test$X_val, 
             "sample_name" = colnames(sample_test)[3], 
             
             "dataset"     = replace_na(dataset),
             "xconta"      = as.numeric(gsub(".*[.](.*)pctReal.*", "\\1", 
                                             colnames(dataset), perl=TRUE))/100,
             "cor_param"   = cor_param,
             "lin_reg_param" = lin_reg_param,
             "poly_reg_param" = poly_reg_param
    )
    return(d)
}

regress_calc <- function(d){
    # linear and 2 degree regression calculation  and prediction
    xconta = d$xconta
    ###
    # lineare prediction 
    max_conta = 5
    i1min = d$lin_reg_param$i1min 
    i1med = d$lin_reg_param$i1med
    i2med = d$lin_reg_param$i2med
    i2max = d$lin_reg_param$i2max
    ratio_het = ratio_hetero(d$dataset, i1min, i1med, i2med, i2max)
    test_value = ratio_hetero(d$sample_test, i1min, i1med, i2med, i2max)
    lin_pred = lm_reg(xconta, ratio_het, max_conta)
    model_lin = lin_pred$model_lin
    lin_predict = lm_reg_predict(model_lin, test_value[3])
    lin_predict_mod = lin_predict_modif(lin_predict, max_conta)
    # summary_lm = summary(model_lin)
    # lm_rsquar  = round(summary_lm$r.squared,5)
    
    ###
    # polynomial prediction
    i1min = d$poly_reg_param$i1min 
    i1med = d$poly_reg_param$i1med
    i2med = d$poly_reg_param$i2med
    i2max = d$poly_reg_param$i2max
    ratio_het = ratio_hetero(d$dataset, i1min, i1med, i2med, i2max)
    test_value = ratio_hetero(d$sample_test, i1min, i1med, i2med, i2max)
    res_poly  = poly_reg(xconta, ratio_het)
    model_2deg = res_poly$model_2deg
    res_poly  = poly_reg_predict(model_2deg, test_value[3])
    res_poly1 = poly_reg_predict_modif(res_poly)
    # summary_2deg = summary(model_2deg)
    # model_2deg_rsquar = round(summary_2deg$r.squared, 5)
    
    ### results
    d[["model_lin"]] = model_lin
    d[["lin_predict"]] = lin_predict
    d[["lin_predict_mod"]] = lin_predict_mod
    #
    d[["model_2deg"]] = model_2deg
    d[["res_poly"]] = res_poly
    d[["res_poly1"]] = res_poly1
    
    return(d)
}

make_tab_hetero <- function(lin_predict_mod, res_poly1, i1min, i1med,
                            i2med, i2max){
    # regression result table formating
    
    tab_hetero = cbind(lin_predict_mod, res_poly1) 
    
    col_tab_hetero_plot = c("Percent Conta\nLinear Regression\n(Max. precision 5%) ", 
                            "Percent Conta\nPolynomial Regression")
    col_tab_hetero_csv = c("Percent Conta Linear Regression (Max. precision 5%) ", 
                           "Percent Conta Polynomial Regression")
    #row_tab_hetero = c("AB [0.34-0.49 ; 0.51-0.65]") 
    row_tab_hetero = c(paste("AB [",(i1min-1)/100,"-", (i1med-1)/100,
                             " ; ", (i2med-1)/100,"-", (i2max-1)/100,"]", sep="")) 
    rownames(tab_hetero) = row_tab_hetero
    colnames(tab_hetero) = col_tab_hetero_csv
    return(list("tab_hetero" = tab_hetero, 
                "col_tab_hetero_plot" = col_tab_hetero_plot))
}

cor_calc <- function(d, d_range){
    # Correlation Calcul
    d_samp   = d$sample_test[d_range,][3]
    d_dataset= d$dataset[d_range,] 
    ref_col  = grep("[.]0000pctReal", colnames(d$dataset))
    nb_ref   = length(ref_col) # number of not contaminated samples in dataset
    nb_data  = dim(d_dataset)[2]
    i_sample = nb_data + 1
    d_cor    = cbind(d_dataset, d_samp)
    mcor     = cor(d_cor)
    ref_mcor = mcor[1:nb_data, i_sample][ref_col]
    hit_mcor = sort(mcor[1:nb_data, i_sample])[nb_data:(nb_data - 2)]
    max_ref  = sort(ref_mcor)[nb_ref]
    name_hit = as.numeric(gsub(".*[.](.*)pctReal.*", "\\1", 
                               names(hit_mcor[1]), perl=TRUE))/100
    return(list("hit_mcor" = hit_mcor, "max_ref"  = max_ref, 
                "name_hit" = name_hit, "mcor" = mcor))
}

data_corelation <- function(d){
    # correlation treatment
    
#     # AB [0.01-0.3]
#     mcor = cor_calc(d, c(d$cor_param$i1min:d$cor_param$i1med))
#     d[["cor_range1"]]      = paste("AB [", (d$cor_param$i1min-1)/100, "-", 
#                                    (d$cor_param$i1med-1)/100, "]", sep="")
#     d[["mcor_1tiers"]]     = mcor$mcor
#     d[["hit_mcor_1tiers"]] = mcor$hit_mcor
#     d[["max_ref_1tiers"]]  = mcor$max_ref
#     d[["name_hit_1tiers"]] = mcor$name_hit
#     
#     # AB [0.7-0.99]
#     mcor = cor_calc(d, c(d$cor_param$i2med:d$cor_param$i2max))
#     d[["cor_range2"]]      = paste("AB [", (d$cor_param$i2med-1)/100, "-", 
#                                    (d$cor_param$i2max-1)/100, "]", sep="") 
#     d[["mcor_3tiers"]]     = mcor$mcor
#     d[["hit_mcor_3tiers"]] = mcor$hit_mcor
#     d[["max_ref_3tiers"]]  = mcor$max_ref
#     d[["name_hit_3tiers"]] = mcor$name_hit
    
    # AB [0.01-0.3 ; 0.7-0.99]
    mcor = cor_calc(d, c(d$cor_param$i1min:d$cor_param$i1med, 
                         d$cor_param$i2med:d$cor_param$i2max))
    d[["cor_range3"]]         = paste("AB [", (d$cor_param$i1min-1)/100, "-",
                                      (d$cor_param$i1med-1)/100 ," ; ", 
                                      (d$cor_param$i2med-1)/100, "-", 
                                      (d$cor_param$i2max-1)/100, "]", sep="")
    d[["mcor_1et3tiers"]]     = mcor$mcor
    d[["hit_mcor_1et3tiers"]] = mcor$hit_mcor
    d[["max_ref_1et3tiers"]]  = mcor$max_ref
    d[["name_hit_1et3tiers"]] = mcor$name_hit
    return(d)
}

make_tab_cor <- function(hit_mcor_1et3tiers, max_ref_1et3tiers, name_hit_1et3tiers,
                         cor_range3){
    
    # Correlation results table  formating
    
    tab_cor = cbind(c(round(max_ref_1et3tiers, 3)),
                    c(round(hit_mcor_1et3tiers[1],3)),
                    c(name_hit_1et3tiers))
    
    col_tab_cor_plot = c("Max. Correlation\nwith Reference", 
                         "Max. Correlation\nwith dataset", 
                         "Percent Contamination\nhit")
    col_tab_cor_csv = c("Max. Cor. with Ref.", 
                        "Max. Cor. with dataset", 
                        "Percent Conta. hit")
    
    row_tab_cor = c(cor_range3)
    rownames(tab_cor) = row_tab_cor
    colnames(tab_cor) = col_tab_cor_csv
    
    return(list("tab_cor" = tab_cor, "col_tab_cor_plot" = col_tab_cor_plot))
}

conta_result <- function(res_poly, conta_threshold){
    # Conditionnal treatment for the contamination's estimation 
    
    if ( res_poly >= conta_threshold) {
        conta_res = paste("Possible contamination greater than ", conta_threshold, 
                          "% : TRUE", sep="")
    } else {
        conta_res = paste("Possible contamination greater than ", conta_threshold, 
                          "% : FALSE", sep="")
    }
    return(conta_res)
}

write_text_report <- function(d, filout){
    tab_cor = d$res_cor$tab_cor
    write.table(tab_cor, file = filout, eol = "\n", quote = TRUE,col.names=TRUE, 
                row.names = TRUE, sep = ",")
    oldw <- getOption("warn")
    #stop warnings
    options(warn = -1)
    tab_hetero = d$res_hetero$tab_hetero 
    write.table(tab_hetero, file = filout, eol = "\n", quote = TRUE, 
                row.names = TRUE, sep = ",",  append = TRUE)
    # Warning message:
    # In write.table(tab_hetero, file = filout, eol = "\n", quote = TRUE,  :
    # appending column names to file
    # restore warnings
    options(warn = oldw)
    cat(d$conta_res, file = filout, eol = "\n", append = TRUE)
}



write_pdf_report <- function(d, filin, pdfout){
    ### Debut enregistrement PDF
    pdf(pdfout,
        height = 11.7,
        width  = 8.3 ,
        paper="a4",)
    
    par(mfrow = c(3,1))
    
    # plot AB distribution
    ref_col = grep("[.]0000pctReal", colnames(d$dataset))
    ### Plot Allele Balance Distribution
    
    #exclude peak AB = 1 for ylim
    ylim_max = round(max(d$dataset[0:100,])/1000)*1000
    ylim_max = ylim_max*1.1
    
    plot(d$X_val, d$sample_test[,3], 
         type = "l", 
         ylim = c(0, ylim_max), 
         col  = "blue",
         main = "Allele Balance Distribution",
         xlab = "Allele Balance", ylab="Observation Number",)
    # add uncontaminated reference to graphique
    for ( ref in ref_col ) {
        lines(d$X_val, d$dataset[,ref], col="darkgreen")
    }
    abline(v=seq(0.1, 0.9 , 0.1), col= "red", lty=3)
    legend("topleft", legend=c("Sample", 
                               paste("References\n", d$depthtest, "x (2x150pb reads)", sep="")), 
           col=c("blue", "darkgreen"),
           lty=1, cex=1, bty="n", horiz = FALSE, ncol=1, border=NULL)
    
    # Add main title to report
    mtext(paste(basename(filin), "; Estimated depth : ", d$depth,"x", sep=""), 
          outer=TRUE,  cex=1.25, line=-1.5)
    
    ### Plot correlation 
    legende_info  = rownames(d$res_cor$tab_cor)
    legende_color = c("blue")
    #legende_color = c("blue", "purple", "darkgreen" )
    #nb_ref   = length(ref_col) # number of not contaminated samples in dataset
    nb_data  = dim(d$dataset)[2]
    i_sample = nb_data + 1
#     # AB [0.7:0.99]
#     plot(d$xconta, d$mcor_3tiers[1:nb_data, i_sample], 
#          pch=4,
#          ylim=c(-1,1), xlim=c(0,50),
#          col=legende_color[1],
#          xlab="Percent contamination", ylab="Correlation", 
#          main = "Sample Correlation to Simulated CrossHuman Contamination Dataset" )
#     # AB [01:0.3]
#     points(d$xconta, d$mcor_1tiers[1:nb_data, i_sample], 
#            pch=4, col = legende_color[2])
#     # AB [0.01:0.3 ; 0.7:0.99]
#     points(d$xconta, d$mcor_1et3tiers[1:nb_data, i_sample],
#            pch=4, col = legende_color[3])
    
    plot(d$xconta, d$mcor_1et3tiers[1:nb_data, i_sample], 
         pch=4,
         ylim=c(-1,1), xlim=c(0,50),
         col=legende_color[1],
         xlab="Percent contamination", ylab="Correlation", 
         main = "Sample Correlation to Simulated CrossHuman Contamination Dataset" )
    
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
    tgrob1 = tableGrob(d$res_cor$tab_cor, rows = rownames(d$res_cor$tab_cor), 
                       cols = d$res_cor$col_tab_cor_plot,
                       theme = ttheme_default(), vp = NULL)
    tgrob2 = tableGrob(d$res_hetero$tab_hetero, 
                       rows = rownames(d$res_hetero$tab_hetero), 
                       cols = d$res_hetero$col_tab_hetero_plot,
                       theme = ttheme_default(), vp = NULL)
    grid.arrange(tgrob1, tgrob2, nrow = 2, newpage = F, 
                 vp=baseViewports()$figure)
    
    ### Fin enregistrement PDF
    dev.off()
}

################
###   Main   ###
################

### argument management
option_list <- list(
    make_option(c("-i", "--input"), action="store", type="character",
                default=NULL,
                help="Input file obtained with script CalculAllelicBalance.sh"),
    
    make_option(c("-o", "--output"), action="store", type="character", 
                default="<input>.conta",
                help="output file [default %default]"),
    
    make_option(c("-d", "--depth"), action="store", type="integer", 
                default=30,
                help="Estimated depth [default %default]"),
                
    make_option(c("-t", "--threshold"), action="store", type="integer", 
                default=4,
                help="Threshold for contamination status [default %default]"),
    
    make_option(c("-n", "--reportName"), action="store", type="character",
                default = "<input>.pdf",
                help="report name [default %default]"),
    
    make_option(c("-e", "--experiment"), action="store", type="character",
                default = "WG",
                help="Experiment type, could be WG for Whole Genome or EX for Exome [default %default]"),
    
    make_option(c("-r", "--report"), action="store_true", type="logical", 
                default=FALSE,
                help=paste("Create a pdf with Allele Balance Distribution",
                           "and Sample correlation with Dataset",
                           "[default %default]"))
)

### argument parsing
parser <- OptionParser(usage = 
                       paste("Estimate the contamination degree of a sample\n",
                             "Output a csv file with contamination estimation\n",
                             "optionaly output a report with graph\n\n",
                             "usage: %prog [options]"), 
                       option_list = option_list,
                       add_help_option = TRUE, prog = NULL, description = "", 
                       epilogue = ""
)


### Arguments recuperation

#DEBUG
argv = parse_args(parser)
argv = argv_mod(argv)

filin      = argv$input
filout     = argv$output
pdfout     = argv$reportName
depth      = argv$depth
experiment = argv$experiment
conta_threshold = argv$threshold

#DEBUG
scriptPath = dirname(getFilename())
datadir = paste(scriptPath, "../share/contatester", sep="/")

### Data Treatment 
sample_test = merge_data(filin)

### load dataset

# Old Dataset
#load(paste(datadir, "contaIntraProjet.rda", sep="/"))

depthtest = dataset_depth(depth, experiment)

cor_param      = list("i1min" = 2, "i1med" = 31, "i2med" = 71, "i2max" = 100)

if (experiment == "WG"){
    if (depthtest == 30) {
        
        # 30x
        load(paste(datadir, "contaIntraProjetWG30x.rda", sep="/"))
        contaIntraProjetWG30x = replace_na(contaIntraProjetWG30x)
        #noconta30x = contaIntraProjetWG30x[,1:4]
        #d_30x 
        lin_reg_param  = list("i1min" = 27, "i1med" = 39, "i2med" = 63, "i2max" = 75)
        poly_reg_param = list("i1min" = 19, "i1med" = 50, "i2med" = 52, "i2max" = 83)
        # stockage dans un objet
        d_30x = data_obj(sample_test, contaIntraProjetWG30x, cor_param, lin_reg_param, poly_reg_param)
        # calcul lineaire reg
        # d_30x = regress_calc(d_30x)
        d = d_30x
    } else if (depthtest == 60) {
        # 60x
        load(paste(datadir, "contaIntraProjetWG60x.rda", sep="/"))
        contaIntraProjetWG60x = replace_na(contaIntraProjetWG60x)
        #noconta60x = contaIntraProjetWG60x[,1:4]
        #d_60x = 
        lin_reg_param  = list("i1min" = 28, "i1med" = 40, "i2med" = 62, "i2max" = 74)
        poly_reg_param = list("i1min" = 13, "i1med" = 50, "i2med" = 52, "i2max" = 89)
        d_60x = data_obj(sample_test, contaIntraProjetWG60x, cor_param, lin_reg_param, poly_reg_param)
        # calcul lineaire reg
        # d_60x = regress_calc(d_60x)
        d = d_60x
        
    } else if (depthtest == 90) {
        # 90x
        load(paste(datadir, "contaIntraProjetWG90x.rda", sep="/"))
        contaIntraProjetWG90x = replace_na(contaIntraProjetWG90x)
        #noconta90x = contaIntraProjetWG90x[,1:4]
        #d_90x =
        lin_reg_param  = list("i1min" = 28, "i1med" = 41, "i2med" = 61, "i2max" = 74)
        poly_reg_param = list("i1min" = 12, "i1med" = 50, "i2med" = 52, "i2max" = 90)
        d_90x = data_obj(sample_test, contaIntraProjetWG90x, cor_param, lin_reg_param, poly_reg_param)
        # calcul lineaire reg
        # d_90x = regress_calc(d_90x)
        d = d_90x
    }
    
} else if (experiment == "EX"){
    if (depthtest == 60) {
        # 60x
        load(paste(datadir, "contaIntraProjetEX60x.rda", sep="/"))
        contaIntraProjetEX60x = replace_na(contaIntraProjetEX60x)
        #noconta60x = contaIntraProjetEX60x[,1:4]
        #d_60x = 
        lin_reg_param  = list("i1min" = 16, "i1med" = 38, "i2med" = 64, "i2max" = 96)
        poly_reg_param = list("i1min" = 12, "i1med" = 50, "i2med" = 52, "i2max" = 90)
        d_60x = data_obj(sample_test, contaIntraProjetEX60x, cor_param, lin_reg_param, poly_reg_param)
        # calcul lineaire reg
        # d_60x = regress_calc(d_60x)
        d = d_60x
    } else if (depthtest == 90) {
        # 90x
        load(paste(datadir, "contaIntraProjetEX90x.rda", sep="/"))
        contaIntraProjetEX90x = replace_na(contaIntraProjetEX90x)
        #noconta90x = contaIntraProjetEX90x[,1:4]
        #d_90x = 
        lin_reg_param  = list("i1min" = 6, "i1med" = 38, "i2med" = 64, "i2max" = 96)
        poly_reg_param = list("i1min" = 9, "i1med" = 50, "i2med" = 52, "i2max" = 93)
        d_90x = data_obj(sample_test, contaIntraProjetEX90x, cor_param, 
                         lin_reg_param, poly_reg_param)
        # calcul lineaire reg
        #d_90x = regress_calc(d_90x)
        d = d_90x
    }
}

# calcul lineaire reg
d[["depth"]]     = depth
d[["depthtest"]] = depthtest
d = regress_calc(d)

# make a table for resultats
d[["res_hetero"]] = make_tab_hetero(d$lin_predict_mod, d$res_poly1, 
                                    d$lin_reg_param$i1min, d$lin_reg_param$i1med,
                                    d$lin_reg_param$i2med, d$lin_reg_param$i2max)

# Correlation Calcul
d = data_corelation(d)
d[["res_cor"]] = make_tab_cor(d$hit_mcor_1et3tiers, d$max_ref_1et3tiers, d$name_hit_1et3tiers,
                              d$cor_range3)

# Test if more than 4% conta 
d[["conta_res"]] = conta_result(d$res_poly[1], conta_threshold)

# save informations in text file
write_text_report(d, filout)

# Plot if flag report is True
if (argv$report) {
    write_pdf_report(d, filin, pdfout)
}




