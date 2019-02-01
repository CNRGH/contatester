#!/usr/bin/env bash

#####
##### Controle de contamination
#####

#
# Damien DELAFOY
# CEA-DRF-JACOB-CNRGH
#

#
# Utilisation :
# Selection de SNP dans un range d'allele balance
####
# Recuperation des variants dans un range d'allele balance
# selection des variants avec Allele Balance  [0.00:0.20]
# transformation du vcf en bed
# et soustraction des regions complexes
# 

set -uo pipefail

# Variables initialisation
declare -r NAME=$(basename $0)
declare -i nbthread=4
# vcf file to process
declare vcfin=""
declare vcfconta=""
declare bedfile=""
# All-in-one LCR & SEG DUP
declare -r scriptPath=$(dirname $0)
declare -r datadir="${scriptPath}"/../share/contatester
declare LCRSEGDUPgnomad="${datadir}"/lcr_seg_dup_gnomad_2.0.2.bed.gz
# AB range
ABstart=0.01
ABend=0.12

# Use an output folder
# foldout="./"


################################################################################
# Functions :

module_load() {
    # Used to load programs with module load function
    module unload python/3.6
    module load python/2.7
    module load bcftools
    module load bedops
    return 0
}

testArg() {
    # Used for the parsing of Arguments
    # Test if a string start with a "-" or empty
    if [[ $1 =~ ^[-] || -z $1 ]]; then 
        echo "ERROR : Missing Argument for $1" >&2 && display_usage && exit 1
    else
        echo $1 
    fi
}

display_usage() {
    echo "
USAGE :
${NAME} [options] 
  -f, --file <vcf_file>
        VCF file version 4.2 to process (Mandatory)
  -c, --vcfconta <vcf_file>
        name of the output VCF file with selected variants (optional)
        [default: {VCFbasename}_AB_{ABstart}to{ABend}_noLCRnoDUP.vcf]
  -b, --bedfile <bed_file>
        name of the output BED file for selected variants (optional)
        [default: {VCFbasename}_AB_{ABstart}to{ABend}_noLCRnoDUP.bed]
  -g, --gnomad <bed_file>
        BED file used to exclude regions with Low Complexity Repeats (LCR)
        and Segmental Duplications (seg_dup) (optional)
        [default: ${datadir}/contatester/lcr_seg_dup_gnomad_2.0.2.bed.gz]
  -s, --ABstart <float>
        Allele balance starting value for variant selection (optional)
        [default: ${ABstart}]
  -e, --ABend <float>
        Allele balance ending value for variant selection (optional)
        [default: ${ABend}] 
  -t, --thread <integer>
        number of threads used by bcftools (optional) [default: ${nbthread}]
  -h, --help                 
        print help

DESCRIPTION :
${NAME} select variants from a VCF file in a range of Allelic Balance and 
exclude position given by the gnomad befile
Output a VCF file and a BED file 

EXAMPLE :
${NAME} -f file.vcf -c vcfconta.vcf -b file.bed \
        -g lcr_seg_dup_gnomad_2.0.2.bed -s 0.01 -e 0.12 -t 4"

  return 0
}


################################################################################
# Main

# Argument parsing

# if no arguments, display usage
if (( $# == 0 )) ; then
    echo "ERROR : No argument provided" >&2 && display_usage >&2 && exit 1
fi

while (( $# > 0 ))
do
    case $1 in
        -f|--file)     vcfin=$(testArg "$2");           shift;;
        -c|--vcfconta) vcfconta=$(testArg "$2");        shift;;
        -b|--bedfile)  bedfile=$(testArg "$2");         shift;;
        -g|--gnomad)   LCRSEGDUPgnomad=$(testArg "$2"); shift;;
        -s|--ABstart)  ABstart=$(testArg "$2");         shift;;
        -e|--ABend)    ABend=$(testArg "$2");           shift;;
        -t|--thread)   nbthread=$(testArg "$2");        shift;;
        -h|--help)     display_usage && exit 0 ;;
        --) shift; break;; 
        -*) echo "$0: error - unrecognized option $1" >&2 && \
            display_usage && exit 1;;
        *)  break;;  
    esac
    shift
done

filename=$(basename $(basename $(basename $vcfin .gz) .vcf) _BOTH.HC.annot )
fileExtension=AB_${ABstart}to${ABend}

# for mandatory arg
if [[ -z $vcfin ]]; then
    echo '[ERROR] -f|--file was not supplied (mandatory option)' >&2 && \
    display_usage && exit 1
fi

# processed vcf file name
if [[ -z $vcfconta ]]; then
    vcfconta=${filename}_${fileExtension}_noLCRnoDUP.vcf
fi 

contadir=$(dirname $vcfconta )
if [[ ! -d $contadir ]]; then 
    mkdir --parents $contadir
fi

# processed bed file name
if [[ -z $bedfile ]]; then
    bedfile=${filename}_${fileExtension}_noLCRnoDUP.bed
fi 

beddir=$(dirname $bedfile )
if [[ ! -d $beddir ]]; then 
    mkdir --parents $beddir
fi

module_load

# Command
bcftools view $vcfin --output-type v --types snps \
--thread $nbthread --targets ^$LCRSEGDUPgnomad | \
# parsing du vcf version 4.2 parsing de la colone AD 
awk -F '\t' '{if($1 !~ /^#/ ) {split($10, a, ":") ; split(a[2], b, ","); \
if((b[2]+b[1]+b[3]) != 0 && b[2]/(b[2]+b[1]+b[3]) >= ABstart && \
b[2]/(b[2]+b[1]+b[3]) <= ABend ) {print}} else {print}}' \
ABstart="$ABstart" ABend="$ABend"| tee $vcfconta | vcf2bed > $bedfile
