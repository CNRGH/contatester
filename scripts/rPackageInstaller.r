#!/usr/bin/env Rscript

##############################
### Libraries Installation ###
##############################


check.packages <- function (pkg) {
  print("Installing required packages, please wait...")
  new.pkg <- pkg[!(pkg %in% installed.packages()[, "Package"])]
  if (length(new.pkg)) {
    install.packages(new.pkg, dependencies = TRUE)
  }
  # sapply(pkg, library, character.only = TRUE)
}

packages <- c("optparse", "grid", "gridBase", "gridExtra")
check.packages(packages)