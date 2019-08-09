#!/usr/bin/env bash

#####
##### Allelic Balance Calculation
#####

#
# Damien DELAFOY
# CEA-DRF-JACOB-CNRGH
#

#
# Usage :
#    Script for allelic balance calculation
#

# Error monitoring
err_report() {
  echo "Error on ${BASH_SOURCE} line $1" >&2
  exit 1
}

trap 'err_report $LINENO' ERR
#

set -eo pipefail

# Variables initialisation
declare -r NAME=$(basename "$0")
declare vcfin=""
declare histout=""
declare -i nbthread=4

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

testArg(){
    # Used for the parsing of Arguments
    # Test if a string start with a "-" or empty
    if [[ $2 =~ ^[-] || -z $2 ]]; then 
        echo "ERROR : Missing Argument for $1" >&2 && display_usage && exit 1
    else
        echo "$2" 
    fi
}


display_usage() {
  echo "
USAGE :
${NAME} [options]
  -f, --file <vcf_file>
        vcf file version 4.2 to process (Mandatory)
  -o, --outputfile <txt_file>
        result file (optional) [default: <vcf_file>.hist]
  -h, --help
        print help

DESCRIPTION :
${NAME} calcul the Allelic Balance of a sample from a VCF file, check if
a cross human contamination is present and estim the degree of
contamination.
Output to stdout

EXAMPLE :
${NAME} -f file.vcf -o file.hist"

  return 0
}

################################################################################
# Main

# Argument parsing

# if no arguments, display usage
if (( $# == 0 )) ; then
    echo "ERROR : No argument provided" >&2 && display_usage && exit 1
fi

while (( $# > 0 ))
do
    case $1 in
        -f|--file)       vcfin=$(testArg "$1" "$2");    shift;;
        -o|--outputfile) histout=$(testArg "$1" "$2");    shift;;
        -h|--help) display_usage && exit 0 ;;
        --) shift; break;;
        -*) echo "$0: error - unrecognized option $1" >&2 && \
            display_usage && exit 1;;
        *)  break;;
    esac
    shift
done

# for mandatory arg
if [[ -z $vcfin ]]; then
    echo '[ERROR] -f|--file was not supplied (mandatory option)' >&2 && \
    display_usage && exit 1
fi

# histout default value
if [[ -z $histout ]]; then
    histout="$vcfin".hist
fi

module_load 'bcftools/1.9'

# Command
# parsing of AD column of vcf version 4.2
bcftools query --include 'TYPE~"snp"' -f '[%AD]\n' "${vcfin}" | \
awk -F ',' '{ if(($1 + $2 + $3 +$4) != 0) {
      printf "%.2f\n", $2/($1 + $2 + $3 + $4)
    }
}' | \
sort | uniq -c > $histout