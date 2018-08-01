#!/usr/bin/env bash

#####
##### Contamination tester with Allelic Balance Distribution
#####

#
# Damien DELAFOY
# CEA-DRF-JACOB-CNRGH
#

#
# Utilisation :
# Detection de contaminations croisées humain/humain 
#

#set -uo pipefail

################################################################################
# FUNCTIONS                                                                    #
################################################################################

testArg() {
    # Used for the parsing of Arguments
    # Test if a string start with a "-" or empty
    if [[ $1 =~ ^[-] || -z $1 ]]; then 
        echo "ERROR : Missing Argument for $1" >&2; exit 1
    else
        echo $1 
    fi
}

# display_usage
# This function displays the usage of this program.
# No parameters
display_usage() {
  cat - <<EOF
  USAGE :
    ${NAME} [options] -f <vcf_file> -o <out_dir> -r
      -f, --file <vcf_file>
            VCF file version 4.2 to process 
            if -f is used dont use -l (Mandatory)
      -l, --list <text_file>     
            input text file, one vcf by lane 
            if -l is used dont use -f (Mandatory)
      -o,--outdir <folder>
            folder for storing all output files (optional) 
            [default: current directory]
      -r, --report 
            create a pdf report for contamination etimation 
            [default: no report]
      -c, --check
            enable contaminant check for the list of VCF provided if a VCF is
            marked as contaminated
      -m, --mail <email_adress>
            send an email at the end of the job 
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


################################################################################
# MODULES                                                                      #
################################################################################

# module load r
# module load bcftools
# module load bedtools
# module load bedops
# module load useq

################################################################################
# MAIN                                                                         #
################################################################################

# Variables initialisation
NAME=$(basename $0)
vcffile=""
vcflist=""

report=""
outdir="."

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
        -c|--check)  check=TRUE;;
        -m|--mail)   mail=$(testArg $2); shift;;
        -h|--help) display_usage && exit 0 ;;
        --) shift; break;; 
        -*) echo "$0: error - unrecognized option $1" >&2; exit 1;;
        *)  break;;  
    esac
    shift
done

# for mandatory arg
if [[ -z $vcffile && -n $vcflist ]]; then
    list_fi=$(cat $vcflist)
elif [[ -n $vcffile && -z $vcflist ]]; then
    list_fi=$vcffile
elif [[ -n $vcffile && -n $vcflist ]]; then
    echo "$NAME: error - provide only a VCF file or a list of VCF file"\
    "in a text file not both at the same time" 1>&2; exit 1;
elif [[ -z $vcffile && -z $vcflist ]]; then
    echo "$NAME: error - provide a vcf file or"\
    "a list of vcf file in a text file" 1>&2; exit 1;
fi

if [[ ! -d $outdir ]]; then 
    mkdir --parents $outdir
fi

script_name=contaTester
DAG_FILE=$outdir/${script_name}.dagfile
DAG_FILE_EDGE=$outdir/${script_name}.dagfiledge
rm -f $DAG_FILE $DAG_FILE_EDGE

for vcfin in $list_fi; do
    basename_vcf=$(basename $(basename $vcfin .gz) .vcf)
    vcfhist=${outdir}/${basename_vcf}.hist
    contafile=${outdir}/${basename_vcf}.conta
    reportName=${outdir}/${basename_vcf}.pdf
    # calcul allelic balance
    task_id1="ABCalc_${basename_vcf}"
    task_conf="TASK $task_id1 -c 4 bash -c"
    task_cmd="calculAllelicBalance.sh -f $vcfin > $vcfhist"
    echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
    # test and report contamination
    task_id2="Report_${basename_vcf}"
    task_conf="TASK $task_id2 bash -c"
    task_cmd="contaReport.R --input $vcfhist --output $contafile ${report} \
    --reportName $reportName"
    echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
    task_conf="EDGE $task_id1 $task_id2"
    echo "$task_conf" >> ${DAG_FILE_EDGE}
    # proceed to comparison
    if [[ -n $vcflist && $check = TRUE ]]; then 
        filename=$(basename $(basename $(basename $vcfin .gz) .vcf) _BOTH.HC.annot )
        ABstart=0
        ABstop=0.2
        fileExtension=AB_${ABstart}to${ABstop}
        vcfconta=${outdir}/${filename}_${fileExtension}_noLCRnoDUP.vcf
        bedfile=${outdir}/${filename}_${fileExtension}_noLCRnoDUP.bed
        # select potentialy contaminant variants
        task_id3="RecupConta_${basename_vcf}"
        task_conf="TASK $task_id3 -c 4 bash -c"
        task_cmd="if [[ \$( awk \'END{printf \$NF}\' $contafile ) = TRUE ]]; then \
        recupConta.sh -f $vcfin -c $vcfconta -b $bedfile; fi "
        echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
        task_conf="EDGE $task_id2 $task_id3"
        echo "$task_conf" >> ${DAG_FILE_EDGE}
        # summary file for comparisons
        summaryFile=${outdir}/${basename_vcf}_comparisonSummary.txt
        task_id3b="SummaryFile_${basename_vcf}"
        task_conf="TASK $task_id3b bash -c"
        task_cmd=" if [[ \$( awk \'END{printf \$NF}\' $contafile ) = TRUE ]];\
        then echo \'comparison\' \'QUALThreshold\' \'NumMatchTest\'\
             \'NumNonMatchTest\' \'FDR=nonMatchTest/(matchTest+nonMatchTest)\'\
             \'decreasingFDR\' \'TPR=matchTest/totalKey\' \'FPR=nonMatchTest/totalKey\'\
             \'PPV=matchTest/(matchTest+nonMatchTest)\' > $summaryFile ; fi"
        echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
        task_conf="EDGE $task_id3 $task_id3b"
        echo "$task_conf" >> ${DAG_FILE_EDGE}
        # comparisons with other vcf
        for vcfcompare in $list_fi; do
            if [[ $vcfcompare != $vcfin ]]; then
                vcfcompareBasename=$(basename $(basename $(basename \
                                        $vcfcompare .gz) .vcf) _BOTH.HC.annot )
                task_id4="Compare_${basename_vcf}_${vcfcompareBasename}"
                task_conf="TASK $task_id4 -c 7 bash -c"
                task_cmd="if [[ \$( awk \'END{printf \$NF}\' $contafile ) = TRUE ]];\
                then checkContaminant.sh -f $vcfcompare -b $bedfile -c $vcfconta \
                -s $summaryFile -o $outdir ; fi"
                echo "$task_conf \" $task_cmd \"" >> ${DAG_FILE}
                task_conf="EDGE $task_id3b $task_id4"
                echo "$task_conf" >> ${DAG_FILE_EDGE}
            fi
        done
    fi
done
echo "" >> ${DAG_FILE}
cat ${DAG_FILE_EDGE} >> ${DAG_FILE}
rm -f ${DAG_FILE_EDGE}
### Ecriture du fichier msub
FILE_MSUB=$outdir/${script_name}.msub

ntask=2
if [[ -n $vcflist ]]; then 
    nbVCF=$(wc -l < $vcflist)
    if [[ $nbVCF -ge 24 ]]; then ntask=24
    else ntask=$(($nbVCF+1))
    fi
fi

echo '#!/bin/bash' > ${FILE_MSUB}
# Parametres MSUB
echo "#MSUB -r ${script_name}" >> ${FILE_MSUB}       # nom du job
echo "#MSUB -n $((${ntask}-1))" >> ${FILE_MSUB}      # nombre de taches en parallele
echo "#MSUB -c 7" >> ${FILE_MSUB}                    # nombre de coeurs par tache
echo "#MSUB -T 28800" >> ${FILE_MSUB}                # temps de l'allocation des ressources en secondes
echo "#MSUB -o $outdir/${script_name}%j.out" >> ${FILE_MSUB} # redirection de la sortie standard.
echo "#MSUB -e $outdir/${script_name}%j.err" >> ${FILE_MSUB} # redirection de la sortie erreur.

if [[ -n $mail ]]; then
    echo "#MSUB -@ ${mail}:end" >> ${FILE_MSUB}      # envoie de mail a la fin
fi

# Parametres cluster
HOSTNAME=$(dnsdomainname)
if [[ $HOSTNAME =~ cng.fr$ || $HOSTNAME =~ cnrgh.fr$ ]]; then
    #lirac
    echo "#MSUB -q normal" >> ${FILE_MSUB}            # nom de la partition
elif [[ $HOSTNAME =~ .ccrt.ccc.cea.fr$ ]]; then
    #cobalt
    echo "#MSUB -A fg0062" >> ${FILE_MSUB}            # projet ou compte pour le decompte de ressource
    echo "#MSUB -q broadwell" >> ${FILE_MSUB}         # nom de la partition"
fi


# MODULES LOAD
echo "module load extenv/ig"  >> ${FILE_MSUB}
echo "module load pegasus"  >> ${FILE_MSUB}
#echo "module load r"  >> ${FILE_MSUB}
echo "module load bcftools"  >> ${FILE_MSUB}
echo "module load bedtools"  >> ${FILE_MSUB}
echo "module load bedops"  >> ${FILE_MSUB}
echo "module load useq"  >> ${FILE_MSUB}

echo "mpirun -oversubscribe -n ${ntask} pegasus-mpi-cluster $DAG_FILE"  >> ${FILE_MSUB}

# Lancement du script
rm -f ${DAG_FILE}.res*
ccc_msub $FILE_MSUB
