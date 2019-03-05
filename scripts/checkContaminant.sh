#!/usr/bin/env bash

#####
##### Contamination Search
#####

#
# Damien DELAFOY
# CEA-DRF-JACOB-CNRGH
#

#
# Objectifs : 
#     Check for the presence of sample cross-contamiantion
#

# Error monitoring
err_report() {
  echo "Error on ${BASH_SOURCE} line $1" >&2
  exit 1
}

trap 'err_report $LINENO' ERR
#

set -eo pipefail

# Variable initialisation
declare -r NAME=$(basename "$0")
declare -i nbthread=4
# vcf file to compare
declare vcfcompare=""
# possibly contaminated vcf file to process
declare vcfconta=""
# summary file for results
declare summaryfile=""
# output directory
declare outdir="."

################################################################################
# Functions :

module_load() {
      # Used to load programs with module load function
      if [[ -n "${IG_MODULESHOME}" ]]; then
        module load "$@"
      else
        local dep_name=""
        local dep_version=""
        local is_present=false
        for dependency in "$@"; do
          dep_name="${dependency%/*}"
          dep_version="${dependency#*/}"
          is_present=$(command -v "${dep_name}" &> /dev/null && echo true || echo false)
          if ! "${is_present}"; then
            echo "ERROR: Missing tools: ${dep_name}" >&2
            exit 1
          #elif [[ -n "${dep_version}" ]]; then
          #  echo 'TODO'
          fi
        done
      fi
    return 0
}

testArg() {
    # Used for the parsing of Arguments
    # Test if a string start with a "-" or empty
    if [[ $1 =~ ^[-] || -z $1 ]]; then 
        echo "ERROR : Missing Argument for $1" >&2 && display_usage && exit 1
    else
        echo "$1" 
    fi
}

display_usage() {
    echo "
USAGE :
${NAME} [options] 
  -f, --file <vcf_file>
        VCF file version 4.2 to process (Mandatory)
  -c, --vcfconta <vcf_file>
        VCF file with selected variants (Mandatory)
  -s, --summaryfile <text_file>
        text file for result output (Mandatory)
  -o,--outdir <folder>
        folder for storing all output files (optional) 
        [default: current directory]
  -t, --thread <integer>
        number of threads used by bcftools (optional) [default: ${nbthread}]
  -h, --help 
        print help

DESCRIPTION :
${NAME} compare selected variants from a VCF file with an over VCF
VCF should be uncompressed or ziped with bgzip
Output : 
    - Output format : vcfContaName,vcfComparName,nbSNPConta,nbMatch,ratio
    - Write important informations in summary file

EXAMPLE :
${NAME} -f file.vcf -c vcfconta.vcf -s comparisonSummary.csv"

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
        -f|--file)        vcfcompare=$(testArg "$2");  shift;;
        -c|--vcfconta)    vcfconta=$(testArg "$2");    shift;;
        -s|--summaryfile) summaryfile=$(testArg "$2"); shift;;
        -t|--thread)   nbthread=$(testArg "$2");        shift;;
        -h|--help) display_usage && exit 0 ;;
        --) shift; break;; 
        -*) echo "$0: error - unrecognized option $1" >&2 && \
            display_usage && exit 1;;
        *)  break;;
    esac
    shift
done

# for mandatory arg
if [[ -z $vcfcompare || -z $vcfconta || -z $summaryfile ]]; then
    echo '[ERROR] All arguments are mandatory' >&2 && \
    display_usage && exit 1
fi

summarydir=$(dirname "${summaryfile}")
if [[ ! -d $summarydir ]]; then 
    mkdir --parents "${summarydir}"
fi

# create summary file if don't exist
if [[ ! -e "${summaryfile}" ]]; then 
    echo "vcfContaName,vcfComparName,nbSNPConta,nbMatch,ratio" > "${summaryfile}"
fi

module_load 'bcftools'

####
# Comparaison of selected variants with other sample 

vcfconta_name=$(basename "${vcfconta}")
vcfcompare_name=$(basename "${vcfcompare}")

nbvar=$(bcftools view -H -o /dev/stdout -O v --types "snps" \
          --thread "${nbthread}" "${vcfconta}" | wc -l)
nbmatch=$(bcftools view -H -o /dev/stdout -O v --types "snps" \
          --thread "${nbthread}" -T "${vcfconta}" "${vcfcompare}" | wc -l)
ratio=$(echo "scale=3; ${nbmatch}/${nbvar}" | bc)

echo "${vcfconta_name},${vcfcompare_name},${nbvar},${nbmatch},${ratio}" >> "${summaryfile}"