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
# Detection de contaminations croisées humain/humain 
#

set -uo pipefail





################################################################################
# FUNCTIONS                                                                    #
################################################################################

# display_usage
# This function displays the usage of this program.
# No parameters
display_usage() {
 # cat - <<EOF
  USAGE :
    ${NAME} [options] -f <vcf_file> -o <out_dir> -r
      -f, --file <vcf_file>
            VCF file version 4.2 to process 
            if -f is used dont use -l (Mandatory)
      -l, --list <text_file>     
            input text file, one vcf by lane 
            if -l is used dont use -f (Mandatory)
      -o, --out <directory>    
            directory where are stored output files
      -r, --report 
            create a pdf report for contamination etimation 
            [default: no report]
      -h, --help 
            print help
            
  DESCRIPTION :
    ${NAME} calcul the Allelic Balance of a sample from a VCF file, check if
    a cross human contamination is present and estim the degree of 
    contamination.

  EXAMPLE :
    ${NAME} -f input.vcf -o outdir/ -r
EOF

  return 0
}


      # -o,--folderout <folder>
            # folder for storing all output files (optional) 
            # [default: current directory]
            
#        -o|--outputfolder) foldout=$(testArg $2); shift;;

################################################################################
# MODULES                                                                      #
################################################################################

# module load r
module load bcftools
module load bedtools
module load bedops
module load useq


################################################################################
# MAIN                                                                         #
################################################################################

# Variables initialisation
vcffile=""
vcflist=""

report=""

# Argument parsing

# if no arguments, display usage
if [[ $# -eq 0 ]] ; then
    echo "ERROR : No argument provided" >&2 && display_usage >&2 && exit 1
fi

while [[ $# -gt 0 ]]
do
    case $1 in
        -f|--file)   vcffile=$(testArg $2); shift;;
        -l|--list)   vcflist=$(testArg $2); shift;;
        -o|--outdir) outdir=$(testArg $2); shift;;
        -r|--report) report="--report";;
        -h|--help) display_usage && exit 0 ;;
        --) shift; break;; 
        -*) echo "$0: error - unrecognized option $1" >&2; exit 1;;
        *)  break;;  
    esac
    shift
done

# for mandatory arg
if [ -z $vcffile && -n $vcflist ]; then
    list_fi=$(cat $vcflist)
elif [ -n $vcffile && -z $vcflist ]; then
    list_fi=$vcffile
elif [ -n $vcffile && -n $vcflist ]; then
    echo "$0: error - provide only a VCF file or a list of VCF file"\
    "in a text file not both at the same time" 1>&2; exit 1;
elif [ -z $vcffile && -z $vcflist ]; then
    echo "$0: error - provide a vcf file or"\
    "a list of vcf file in a text file" 1>&2; exit 1;
fi

#$(wc -l $list_fi)
script_name=contaTester
DAG_FILE=${script_name}.dagfile
DAG_FILE_EDGE=${script_name}.dagfiledge
rm -f $DAG_FILE $DAG_FILE_EDGE

for vcfin in $list_fi; do
    basename_vcf=$(basename $(basename $vcfin .gz) .vcf)
    vcfhist=${basename_vcf}.hist
    contafile=${basename_vcf}.conta
    # calcul allelic balance
    task_id1="ABCalc_${vcfin}"
    task_conf="TASK $task_id1 -c 4 bash -c"
    task_cmd="calculAllelicBalance $vcfin 4 > $vcfhist"
    echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
    # test and report contamination
    task_id2="Report_${vcfin}"
    task_conf="TASK $task_id2 bash -c"
    task_cmd="contaReport.R --input $vcfhist --output $contafile ${report}"
    echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
    task_conf="EDGE $task_id1 $task_id2"
    echo "$task_conf" >> ${DAG_FILE_EDGE}
    # proceed to comparison
    if [ -n $vcflist ]; then 
        filename=$(basename $(basename $(basename $vcfin .gz) .vcf) _BOTH.HC.annot )
        ABstart=0
        ABstop=0.2
        fileExtension=AB_${ABstart}to${ABstop}
        vcfconta=${filename}_${fileExtension}_noLCRnoDUP.vcf
        bedfile=${filename}_${fileExtension}_noLCRnoDUP.bed
        # select potentialy contaminant variants
        task_id3="RecupConta_${vcfin}"
        task_conf="TASK $task_id3 bash -c"
        task_cmd="if [ \$(awk 'END{printf \$NF}' $contafile) ]; then; \
        recupConta.sh $vcfin $vcfconta $bedfile; fi"
        echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
        task_conf="EDGE $task_id2 $task_id3"
        echo "$task_conf" >> ${DAG_FILE_EDGE}
        # summary file for comparisons
        summaryFile=${basename_vcf}_comparisonSummary.txt
        echo "comparison" "QUALThreshold" "NumMatchTest" "NumNonMatchTest"\
             "FDR=nonMatchTest/(matchTest+nonMatchTest)" "decreasingFDR"\
             "TPR=matchTest/totalKey" "FPR=nonMatchTest/totalKey"\
             "PPV=matchTest/(matchTest+nonMatchTest)" > $summaryFile
        # comparisons with other vcf
        for vcfcompare in $list_fi; do
            if [ $vcfcompare != $vcfin ]; then
                task_id4="Compare_${$vcfin}_${vcfcompare}"
                task_conf="TASK $task_id4 bash -c"
                task_cmd="if [ \$(awk 'END{printf $NF}' \$contafile) ]; then; \
                checkContaminant.sh $vcfcompare $vcfconta $bedfile \
                >> $summaryFile; fi"
                echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
                task_conf="EDGE $task_id3 $task_id4"
                echo "$task_conf" >> ${DAG_FILE_EDGE}
            fi
        done
    fi
done
echo "" >> ${DAG_FILE}
cat ${DAG_FILE} ${DAG_FILE_EDGE} > ${DAG_FILE}

### Ecriture du fichier msub
FILE_MSUB1=${script_name}.msub

if [ -n $vcflist ]; then; ntask=24; else ntask=1; fi

echo '#!/bin/bash' > ${FILE_MSUB1}
# Parametres MSUB
echo "#MSUB -r ${script_name}" >> ${FILE_MSUB1}       # nom du job
echo "#MSUB -A fg0062" >> ${FILE_MSUB1}               # projet ou compte pour le decompte de ressource
#echo "#MSUB -N 1" >> ${FILE_MSUB1}                   # Un seul noeud minimum et maximum
#echo "#MSUB -n ${ntask}" >> ${FILE_MSUB1}             # nombre de taches en parallele
echo "#MSUB -c 4" >> ${FILE_MSUB1}                    # nombre de coeurs par tache
echo "#MSUB -q broadwell" >> ${FILE_MSUB1}            # nom de la partition
#echo "#MSUB -E '--qos long'" >> ${FILE_MSUB1}        # qos 3J
echo "#MSUB -T 86400" >> ${FILE_MSUB1}                # temps de l'allocation des ressources en secondes
echo "#MSUB -o ${script_name}%j.out" >> ${FILE_MSUB1} # redirection de la sortie standard.
echo "#MSUB -e ${script_name}%j.err" >> ${FILE_MSUB1} # redirection de la sortie erreur.
echo "#MSUB -@ delafoy@cng.fr:end" >> ${FILE_MSUB1}   # envoie de mail a la fin

# MODULES LOAD
echo "module load extenv/ig"  >> ${FILE_MSUB1}
echo "module load pegasus/4.8.0.a"  >> ${FILE_MSUB1}
echo "module load r"  >> ${FILE_MSUB1}
echo "module load bcftools"  >> ${FILE_MSUB1}
echo "module load bedtools"  >> ${FILE_MSUB1}
echo "module load bedops"  >> ${FILE_MSUB1}
echo "module load useq"  >> ${FILE_MSUB1}

echo "mpirun -oversubscribe -n ${ntask} pegasus-mpi-cluster $DAG_FILE"  >> ${FILE_MSUB1}

# Lancement du script
rm -f ${DAG_FILE}.res*
ccc_msub $FILE_MSUB1
