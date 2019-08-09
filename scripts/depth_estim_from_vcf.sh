#!/usr/bin/env bash

# Error monitoring
err_report() {
  echo "Error on ${BASH_SOURCE} line $1" >&2
  exit 1
}

trap 'err_report $LINENO' ERR
#

set -eo pipefail
declare -r NAME=$(basename "$0")
declare vcfin=""
declare filout=""
declare -i nbthread=4

################################################################################
# Functions :
testArg(){
    # Used for the parsing of Arguments
    # Test if a string start with a "-" or empty
    if [[ $2 =~ ^[-] || -z $2 ]]; then 
        echo "ERROR : Missing Argument for $1" >&2 && display_usage && exit 1
    else
        echo "$2" 
    fi
}

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

display_usage() {
    echo "
USAGE :
${NAME} [options]
  -f, --file <vcf_file>
        vcf file version 4.2 to process (Mandatory)
  -o, --outputfile <integer>
        output file (optional) [default: <file>.meandepth]
  -t, --thread <integer>
        number of threads used by bcftools (optional) [default:${nbthread}]
  -h, --help
        print help

DESCRIPTION :
${NAME}
  Used to estimate depth from a vcf
  Only use SNP positions
  Return mean of depth
  Require bcftools 

EXAMPLE :
${NAME} -f file.vcf"

    return 0
}

################################################################################
# Main :

# Argument parsing

# if no arguments, display usage
if (( $# == 0 )) ; then
    echo "ERROR : No argument provided" >&2 && display_usage && exit 1
fi

while (( $# > 0 ))
do
    case $1 in
        -f|--file) vcfin=$(testArg "$1" "$2"); shift;;
        -o|--outputfile) filout=$(testArg "$1" "$2"); shift;;
        -t|--thread) nbthread=$(testArg "$1" "$2"); shift;;
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

# filout default value
if [[ -z $filout ]]; then
    filout="$vcfin".meandepth
fi

############################
module_load 'bcftools'

bcftools query --include 'TYPE~"snp"' -f '[%DP]\n' "${vcfin}" | \
awk -F '\t' 'BEGIN { m=0 } {m+=$1} END { print m/NR }' > $filout

# bcftools view --no-header --output-type v --types snps --thread $nbthread $vcfin | \
# awk -F '\t' 'BEGIN { m=0 } { if($1 !~ /^#/ ){ split($10, tab_INFO, ":"); m+=tab_INFO[3] } } END { print m/NR }' > $filout

## mean and  mediane :
# bcftools view --no-header --output-type v --types snps --thread $nbthread $vcfin | \
# awk -F '\t' 'BEGIN { m=0 ; y=0 } { if($1 !~ /^#/ ){ split($10, tab_INFO, ":"); m+=tab_INFO[3] ; a[i++]=tab_INFO[3]} } END {x=int((i+1)/2); if (x < (i+1)/2) y=(a[x-1]+a[x])/2; else y=a[x-1] ; print m/NR, y}'






