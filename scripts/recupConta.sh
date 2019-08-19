#!/usr/bin/env bash

#####
##### Check for contamination
#####

#
# Damien DELAFOY
# CEA-DRF-JACOB-CNRGH
#

#
# Usage :
#    SNP Selection in a given allelic balance range
####
#    Variant recovery in allelic range default : [0.00 - 0.11]
#    Exclude complexes regions 
# 

# Error monitoring
err_report() {
  echo "Error on ${BASH_SOURCE[0]} line $1" >&2
  exit 1
}

trap 'err_report $LINENO' ERR
#

set -eo pipefail
# Variables initialisation
declare NAME=""
NAME="$(basename "$0")"
readonly NAME
declare -i nbthread=4
# vcf file to process
declare vcfin=""
declare vcfconta=""
# All-in-one LCR & SEG DUP
declare scriptPath=""
scriptPath="$(dirname "$0")"
readonly scriptPath
declare -r datadir="${scriptPath}"/../share/contatester
declare LCRSEGDUPgnomad="${datadir}"/lcr_seg_dup_gnomad_2.0.2.bed.gz
# AB range
ABstart=0.00
ABend=0.11


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
        VCF file version 4.2 to process (Mandatory)
  -c, --vcfconta <vcf_file>
        name of the output VCF file with selected variants (optional)
        [default: {VCFbasename}_AB_{ABstart}to{ABend}_noLCRnoDUP.vcf]
  -g, --gnomad <bed_file>
        BED file used to exclude regions with Low Complexity Repeats (LCR)
        and Segmental Duplications (seg_dup) (optional)
        [default: ${datadir}/lcr_seg_dup_gnomad_2.0.2.bed.gz]
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
Output a compressed VCF file 

EXAMPLE :
${NAME} -f file.vcf -c vcfconta.vcf.gz
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
        -f|--file)     vcfin=$(testArg "$1" "$2");           shift;;
        -c|--vcfconta) vcfconta=$(testArg "$1" "$2");        shift;;
        -g|--gnomad)   LCRSEGDUPgnomad=$(testArg "$1" "$2"); shift;;
        -s|--ABstart)  ABstart=$(testArg "$1" "$2");         shift;;
        -e|--ABend)    ABend=$(testArg "$1" "$2");           shift;;
        -t|--thread)   nbthread=$(testArg "$1" "$2");        shift;;
        -h|--help)     display_usage && exit 0 ;;
        --) shift; break;; 
        -*) echo "$0: error - unrecognized option $1" >&2 && \
            display_usage && exit 1;;
        *)  break;;  
    esac
    shift
done

filename_no_gz="$(basename "${vcfin}" .gz)"
filename_no_vcf="$(basename "${filename_no_gz}" .vcf)"
filename="$(basename "${filename_no_vcf}" _BOTH.HC.annot)"
fileExtension="AB_${ABstart}to${ABend}"

# for mandatory arg
if [[ -z $vcfin ]]; then
    echo '[ERROR] -f|--file was not supplied (mandatory option)' >&2 && \
    display_usage && exit 1
fi

# processed vcf file name
if [[ -z $vcfconta ]]; then
    vcfconta=${filename}_${fileExtension}_noLCRnoDUP.vcf.gz
fi 

contadir=$(dirname "${vcfconta}" )
if [[ ! -d "${contadir}" ]]; then 
    mkdir --parents "${contadir}"
fi

module_load 'bcftools/1.9'

# Command
# select snp in allele balance range
bcftools view -i "(AD[0:1]/(AD[0:0]+AD[0:1]+AD[0:2]+AD[0:3])>${ABstart} && \
                   AD[0:1]/(AD[0:0]+AD[0:1]+AD[0:2]+AD[0:3])<${ABend}) || \
                  (AD[0:1]/(AD[0:0]+AD[0:1]+AD[0:2])>${ABstart} && \
                   AD[0:1]/(AD[0:0]+AD[0:1]+AD[0:2])<${ABend}) || \
                  (AD[0:1]/(AD[0:0]+AD[0:1])>${ABstart} && \
                   AD[0:1]/(AD[0:0]+AD[0:1])<${ABend})" \
              --output-type z \
              --types snps \
              --thread "${nbthread}" \
              --targets "^${LCRSEGDUPgnomad}" \
              --output-file "${vcfconta}" \
              "${vcfin}"
