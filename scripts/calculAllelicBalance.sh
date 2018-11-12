#!/usr/bin/env bash

#####
##### Allelic Balance Calculation
#####

#
# Damien DELAFOY
# CEA-DRF-JACOB-CNRGH
#

#
# Utilisation :
# Calcul de la balance allelique
#

set -uo pipefail

################################################################################

module load bcftools # actually 1.6

################################################################################
# Functions :

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
        vcf file version 4.2 to process (Mandatory)
  -t, --thread <integer>
        number of threads used by bcftools (optional) [default:${nbthread}]
  -h, --help
        print help

DESCRIPTION :
${NAME} calcul the Allelic Balance of a sample from a VCF file, check if
a cross human contamination is present and estim the degree of
contamination.
Output to stdout

EXAMPLE :
${NAME} -f file.vcf"

  return 0
}

################################################################################
# Main

# initialisation des variables
declare -r NAME=$(basename $0)
declare vcfin=""
declare -i nbthread=4

# Argument parsing

# if no arguments, display usage
if (( $# == 0 )) ; then
    echo "ERROR : No argument provided" >&2 && display_usage && exit 1
fi

while (( $# > 0 ))
do
    case $1 in
        -f|--file)   vcfin=$(testArg "$2");    shift;;
        -t|--thread) nbthread=$(testArg "$2"); shift;;
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

# Command
bcftools view $vcfin --no-header --output-type v --types snps --thread $nbthread | \
# parsing du vcf version 4.2 parsing de la colone AD 
awk -F '\t' '{if($1 !~ /^#/ ) {split($10, a, ":") ; split(a[2], b, ","); \
if((b[2]+b[1]+b[3]) != 0) {printf "%.2f\n", b[2]/(b[2]+b[1]+b[3])}}}' | \
sort | uniq -c

