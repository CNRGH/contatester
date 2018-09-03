# Import necessary libraries:
import argparse
import os
import io
import subprocess
import sys


# Functions


def arguments():
    '''
    Recuperation and manipulation of argparse arguments
    '''
    parser = argparse.ArgumentParser(prog="__main__.py",
                                     usage="%(prog)s [options]",
                                     description=("Wrapper for the detection"
                                                  " and determination of "
                                                  "the presence of cross "
                                                  "contaminant"))
    group = parser.add_mutually_exclusive_group(required=True)

    group.add_argument("-f", "--file", type=str,
                       help=("VCF file version 4.2 to process. "
                             "If -f is used don't use -l (Mandatory)"))

    group.add_argument("-l", "--list", type=str,
                       help=("input text file, one vcf by lane. "
                             "If -l is used don't use -f (Mandatory)"))

    parser.add_argument("-o", "--outdir", default="./", type=str,
                        help=("folder for storing all output files "
                              "(optional) [default: current directory]"))

    parser.add_argument("-r", "--report",
                        help=("create a pdf report for contamination "
                              "estimation [default: no report]"),
                        action="store_true")

    parser.add_argument("-c", "--check",
                        help=("enable contaminant check for the list of VCF "
                              "provided if a VCF is marked as contaminated"),
                        action="store_true")

    parser.add_argument("-m", "--mail", default="", type=str,
                        help="send an email at the end of the job")

    # keep arguments
    args = parser.parse_args()

    vcf_file = [args.file]
    vcf_list = args.list
    out_dir = args.outdir
    check = args.check
    mail = args.mail

    if vcf_list is not None:
        with open(vcf_list, 'r') as filin:
            vcfs = filin.read().splitlines()
    else:
        vcfs = vcf_file

    if args.report:
        report = "--report"
    else:
        report = ""

    if out_dir != "./":
        if out_dir[-1] != "/":
            out_dir = out_dir + "/"
        if not os.path.exists(out_dir):
            os.mkdir(out_dir)

    return vcfs, out_dir, report, check, mail


# Main
def main():
    vcfs, out_dir, report, check, mail = arguments()

    script_name = "contaTester"
    dag_file = out_dir + script_name + ".dagfile"
    msub_file = out_dir + script_name + ".msub"
    if os.path.isfile(dag_file):
        os.remove(dag_file)
    task_fmt = "TASK {id} -c {core} bash -c "

    page_size = io.DEFAULT_BUFFER_SIZE
    with open(dag_file, "wb", buffering=10 * page_size) as dag_f:
        for vcf_in in vcfs:
            basename_tmp = os.path.basename(vcf_in)
            basename_vcf = basename_tmp.split(".vcf")[0]
            vcf_hist = out_dir + basename_vcf + ".hist"
            conta_file = out_dir + basename_vcf + ".conta"
            report_name = out_dir + basename_vcf + ".pdf"

            # calcul allelic balance
            task_id1 = "ABCalc_" + basename_vcf
            task_conf = task_fmt.format(id=task_id1, core=4)
            task_cmd = "calculAllelicBalance.sh -f " + vcf_in + " > " + vcf_hist
            dag_f.write(bytes(task_conf + "\"" + task_cmd + "\"\n", "ASCII"))

            # test and report contamination
            task_id2 = "Report_" + basename_vcf
            task_conf = task_fmt.format(id=task_id2, core=1)
            task_cmd = ("contaReport.R --input " + vcf_hist + " --output " +
                        conta_file + " " + report +
                        " --reportName " + report_name)
            dag_f.write(bytes(task_conf + "\"" + task_cmd + "\"\n", "ASCII"))
            dag_f.write(bytes("EDGE " + task_id1 + " " + task_id2 + "\n",
                              "ASCII"))

            # proceed to comparison
            if check is True:
                filename = basename_vcf.split("_BOTH.HC.annot ")[0]
                ABstart = 0
                ABstop = 0.2
                file_extension = "AB_" + str(ABstart) + "to" + str(ABstop)
                basename_conta = out_dir + filename + "_" + file_extension
                vcf_conta = basename_conta + "_noLCRnoDUP.vcf"
                bedfile = basename_conta + "_noLCRnoDUP.bed"

                # select potentialy contaminant variants
                task_id3 = "RecupConta_" + basename_vcf
                task_conf = task_fmt.format(id=task_id3, core=4)
                task_cmd = ("if [[ $( awk 'END{printf $NF}' " + conta_file +
                            ") = TRUE ]]; then recupConta.sh -f " + vcf_in +
                            " -c " + vcf_conta + " -b " + bedfile + "; fi ")
                dag_f.write(bytes(task_conf + "\"" + task_cmd + "\"\n",
                                  "ASCII"))
                dag_f.write(bytes("EDGE " + task_id2 + " " + task_id3 + "\n",
                                  "ASCII"))

                # summary file for comparisons
                summaryFile = out_dir + basename_vcf + "_comparisonSummary.txt"
                task_id3b = "SummaryFile_" + basename_vcf
                task_conf = task_fmt.format(id=task_id3b, core=1)
                task_cmd = (" if [[ $( awk 'END{printf $NF}' " + conta_file +
                            " ) = TRUE ]]; then echo 'comparison' "
                            "'QUALThreshold' 'NumMatchTest' 'NumNonMatchTest' "
                            "'FDR=nonMatchTest/(matchTest+nonMatchTest)' "
                            "'decreasingFDR' 'TPR=matchTest/totalKey' "
                            "'FPR=nonMatchTest/totalKey' "
                            "'PPV=matchTest/(matchTest+nonMatchTest)' > " +
                            summaryFile + " ; fi")
                dag_f.write(bytes(task_conf + "\"" + task_cmd + "\"\n",
                                  "ASCII"))
                dag_f.write(bytes("EDGE " + task_id3 + " " + task_id3b + "\n",
                                  "ASCII"))

                # comparisons with other vcf
                for vcf_compare in vcfs:
                    if vcf_compare != vcf_in:
                        basename_tmp2 = os.path.basename(vcf_compare)
                        basename_vcf2 = basename_tmp2.split(".vcf")[0]
                        vcf_compare_basename = \
                            basename_vcf2.split("_BOTH.HC.annot ")[0]
                        task_id4 = ("Compare_" + basename_vcf + "_" +
                                    vcf_compare_basename)
                        task_conf = task_fmt.format(id=task_id4, core=7)
                        task_cmd = ("if [[ $( awk 'END{printf $NF}' " +
                                    conta_file + " ) = TRUE ]]; " +
                                    "then checkContaminant.sh -f " +
                                    vcf_compare + " -b " + bedfile +
                                    " -c " + vcf_conta + " -s " + summaryFile +
                                    " -o " + out_dir + "; fi")
                        dag_f.write(bytes(task_conf + "\"" + task_cmd + "\"\n",
                                          "ASCII"))
                        dag_f.write(bytes("EDGE " + task_id3b + " " + task_id4 +
                                          "\n", "ASCII"))

    ntask = 2
    nbVCF = len(vcfs)
    if nbVCF > 48:
        ntask = 48
    elif nbVCF > 1:
        ntask = nbVCF + 1

    with open(msub_file, "w", ) as msub_f:
        # Parametres MSUB
        msub_f.write(("#!/bin/bash\n" +
                      "#MSUB -r " + script_name + "\n" +
                      "#MSUB -n " + str(ntask - 1) + "\n" +
                      "#MSUB -c 7 \n" +
                      "#MSUB -T 28800 \n" +
                      "#MSUB -o " + out_dir + script_name + "%j.out\n" +
                      "#MSUB -e " + out_dir + script_name + "%j.err\n"))

        if len(mail) > 0:
            msub_f.write("#MSUB -@ ${mail}:end\n")

        # Clusters parameters
        hostname = os.popen("dnsdomainname").read()
        if "cng.fr" in hostname or "cnrgh.fr" in hostname:
            # lirac
            msub_f.write("#MSUB -q normal\n")
        elif "ccrt.ccc.cea.fr" in hostname:
            # cobalt
            msub_f.write("#MSUB -A fg0062\n#MSUB -q broadwell\n")

        # MODULES LOAD
        msub_f.write(("module load extenv/ig\n" +
                      "module load pegasus\n" +
                      "module load bcftools\n" +
                      "module load bedtools\n" +
                      "module load bedops\n" +
                      "module load useq\n" +
                      "mpirun -oversubscribe -n " + str(ntask) +
                      " pegasus-mpi-cluster " + dag_file + "\n"))

    # Start Script
    if os.path.isfile((dag_file + ".res*")):
        os.remove((dag_file + ".res*"))
    cmd = ["/usr/bin/ccc_msub", msub_file]
    p = subprocess.call(cmd)
    if p != 0:
        print("Error while running ccc_msub: {} ".format(" ".join(cmd)),
              file=sys.stderr)
    sys.exit(p)


if __name__ == '__main__':
    # execute only if run as a script
    main()
