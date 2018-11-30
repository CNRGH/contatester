#####
##### Controle de contamination
#####

#
# Damien DELAFOY
# CEA-DRF-JACOB-CNRGH
#

#
# Objectifs : 
# 
# Verrifier qu'il n'y a pas de contamination croisées entre différentes sequences
#

set -uo pipefail

################################################################################
# Functions :

testArg() {
    # Used for the parsing of Arguments
    # Test if a string start with a "-" or empty
    if [[ $1 =~ ^[-] || -z $1 ]]; then 
        echo "ERROR : Missing Argument for $1" >&2; exit 1
    else
        echo $1 
    fi
}

display_usage() {
  cat - <<EOF
  USAGE :
    ${NAME} [options] 
      -f, --file <vcf_file>
            VCF file version 4.2 to process (Mandatory)
      -c, --vcfconta <vcf_file>
            VCF file with selected variants (Mandatory)
      -b, --bedfile <bed_file>
            BED file for selected variants (Mandatory)
      -s, --summaryfile <text_file>
            text file for result output (Mandatory)
      -o,--outdir <folder>
            folder for storing all output files (optional) 
            [default: current directory]
      -h, --help 
            print help

  DESCRIPTION :
    ${NAME} compare selected variants from a VCF file with an over VCF 
    Output : 
        - Standard VCFComparator output 
        - Write important informations in summary file

  EXAMPLE :
    ${NAME} -f file.vcf -c vcfconta.vcf -b file.bed
EOF

  return 0
}

################################################################################
# Load Modules

# module unload varscope
module load useq


################################################################################
# Main


# Variables initialisation
NAME=$(basename $0)
# vcf file to compare
vcfcompare=""
# possibly contaminated vcf file to process
vcfconta=""
# bed file name for comparison
bedfile=""
# summary file for results
summaryfile=""
# output directory
outdir="."

# Use an output folder
# foldout=$2

# Argument parsing

# if no arguments, display usage
if [[ $# -eq 0 ]] ; then
    echo "ERROR : No argument provided" >&2 && display_usage >&2 && exit 1
fi

while [[ $# -gt 0 ]]
do
    case $1 in
        -f|--file)        vcfcompare=$(testArg $2);    shift;;
        -c|--vcfconta)    vcfconta=$(testArg $2); shift;;
        -b|--bedfile)     bedfile=$(testArg $2);  shift;;
        -s|--summaryfile) summaryfile=$(testArg $2); shift;;
        -o|--outdir)      outdir=$(testArg $2); shift;;
        -h|--help) display_usage && exit 0 ;;
        --) shift; break;; 
        -*) echo "$0: error - unrecognized option $1" >&2; exit 1;;
        *)  break;;  
    esac
    shift
done

# for mandatory arg
if [[ -z $vcfcompare || -z $vcfconta || -z $bedfile || -z $summaryfile ]]; then
    echo '[ERROR] All arguments are mandatory' >&2 && exit 1
fi

summarydir=$(dirname $summaryfile)
if [[ ! -d $summarydir ]]; then 
    mkdir --parents $summarydir
fi

if [[ ! -d $outdir ]]; then 
    mkdir --parents $outdir
fi

####
# comparaison des variants avec un echantillon 
fileA=$vcfcompare
fileA_name=$(basename $(basename $fileA .gz) .vcf)
fileB=$vcfconta
fileB_name=$(basename $(basename $fileB .gz) .vcf)
filout=${outdir}/${fileA_name}_${fileB_name}


VCFComparator -a $fileA -b $bedfile -c $fileB -d $bedfile -s -p $filout
res=$(grep none ${filout}/comparison_SNP_${fileA_name}_${fileB_name}.xls)
echo ${fileA_name}_${fileB_name} $res >> $summaryfile


