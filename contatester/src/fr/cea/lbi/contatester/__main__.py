# Import necessary libraries:

from pathlib import Path
from os import access, R_OK, getcwd, makedirs, remove, popen
from os.path import isfile, abspath, isdir, join
from typing import Sequence, Tuple, List, BinaryIO
import argparse
import io
import subprocess
import sys

script_name = "contaTester"


def readable_file(prospective_file: str) -> str:
    if not isfile(prospective_file):
        raise SystemExit("File:{0} is not a valid path"
                         .format(prospective_file))
    if not access(prospective_file, R_OK):
        raise SystemExit("File:{0} is not a readable file"
                         .format(prospective_file))
    return abspath(prospective_file)


def valid_output_dir(prospective_path: str) -> str:
    abs_path = abspath(prospective_path)
    if isfile(prospective_path):
        raise SystemExit("A file exists already at requested location: {0}"
                         .format(prospective_path))
    elif isdir(prospective_path):
        raise SystemExit("A Directory exists already at requested location: {0}"
                         .format(prospective_path))
    else:
        makedirs(abs_path)
    return abs_path


def get_cli_args(parameters: Sequence[str] = sys.argv[1:]) \
        -> Tuple[List[str], str, str, bool, str]:
    """Parse command line parameters
    Parse program parameters using argparse module
    Args:
        parameters: Sequence of parameters to be parsed

    Returns:
        A list of vcf file path
        The output directory to be used
        A flag to generate or not the report
        A flag to enable contaminant check
    """
    parser = argparse.ArgumentParser(prog=script_name,
                                     usage="%(prog)s [options]",
                                     description=("Wrapper for the detection"
                                                  " and determination of "
                                                  "the presence of cross "
                                                  "contaminant"))
    group = parser.add_mutually_exclusive_group(required=True)

    group.add_argument("-f", "--file", type=readable_file,
                       help=("VCF file version 4.2 to process. "
                             "If -f is used don't use -l (Mandatory)"))

    group.add_argument("-l", "--list", type=readable_file,
                       help=("input text file, one vcf by lane. "
                             "If -l is used don't use -f (Mandatory)"))

    parser.add_argument("-o", "--outdir", default=getcwd(), type=str,
                        help=("folder for storing all output files "
                              "(optional) [default: current directory]"))

    parser.add_argument("-r", "--report",
                        help=("create a pdf report for contamination "
                              "estimation [default: no report]"),
                        action="store_true")

    parser.add_argument("-c", "--check",
                        help=("enable contaminant check for each VCF "
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

    return vcfs, out_dir, report, check, mail


def write_binary(file_handler: BinaryIO, statement: str) -> None:
    """Convert a statement to byte and write it into a file

    Args:
        file_handler: A writeable file
        statement: any string to be write into the provided file
    """
    file_handler.write(bytes(statement, "ASCII"))


def write_intermediate_task(file_handler: BinaryIO, conf: str, cmd: str,
                            task_a: str, task_b: str) -> None:
    write_binary(file_handler, conf + "\"" + cmd + "\"\n")
    write_binary(file_handler, "EDGE " + task_a + " " + task_b + "\n")


def create_report(basename_vcf: str, conta_file: str, dag_f: BinaryIO,
                  out_dir: str, task_fmt: str, task_id2: str, current_vcf: str,
                  vcfs: List[str]) -> None:
    """Report generator

    This function append some extra tasks to the DAG in order to generate a
    report on each provided vcf file

    Args:
        basename_vcf: The base name of vcf file
        conta_file: The generated contaminant file to be processed
        dag_f: the dag file to append the extra tasks
        out_dir: Directory to put results
        task_fmt: A format string to write a task into the DAG
        task_id2: The task id which generate generate the contaminant file
        current_vcf: Path to current vcf analysed
        vcfs: A list of vcf file path
    """
    filename = basename_vcf.split("_BOTH.HC.annot ")[0]
    file_extension = "AB_0_to_0.2"
    basename_conta = join(out_dir, filename + "_" + file_extension)
    vcf_conta = basename_conta + "_noLCRnoDUP.vcf"
    bedfile = basename_conta + "_noLCRnoDUP.bed"
    awk_if_fmt = ("if [[ $( awk \\'END{printf $NF}\\' {conta_fi}) = TRUE ]];"
                  " then {cmd} ; fi")
    # select potentialy contaminant variants
    task_id3 = "RecupConta_" + basename_vcf
    task_conf = task_fmt.format(id=task_id3, core=4)
    cmd = ("recupConta.sh - f " + current_vcf + " -c " + vcf_conta + " -b "
           + bedfile)
    task_cmd = awk_if_fmt.format(conta_fi=conta_file, cmd=cmd)
    write_intermediate_task(dag_f, task_conf, task_cmd, task_id2, task_id3)
    # summary file for comparisons
    summary_file = join(out_dir, basename_vcf + "_comparisonSummary.txt")
    task_id3b = "SummaryFile_" + basename_vcf
    task_conf = task_fmt.format(id=task_id3b, core=1)
    cmd = ("echo 'comparison' 'QUALThreshold' 'NumMatchTest' 'NumNonMatchTest' "
           "'FDR=nonMatchTest/(matchTest+nonMatchTest)' 'decreasingFDR' "
           "'TPR=matchTest/totalKey' 'FPR=nonMatchTest/totalKey' "
           "'PPV=matchTest/(matchTest+nonMatchTest)' > " + summary_file)
    task_cmd = awk_if_fmt.format(conta_fi=conta_file, cmd=cmd)
    write_intermediate_task(dag_f, task_conf, task_cmd, task_id3, task_id3b)
    # comparisons with other vcf
    for vcf_compare in vcfs:
        if vcf_compare != current_vcf:
            path_obj = Path(vcf_compare)
            basename_vcf2 = path_obj.stem
            vcf_compare_basename = \
                basename_vcf2.split("_BOTH.HC.annot ")[0]
            task_id4 = ("Compare_" + basename_vcf + "_" +
                        vcf_compare_basename)
            task_conf = task_fmt.format(id=task_id4, core=7)
            cmd = ("checkContaminant.sh -f " + vcf_compare + " -b " + bedfile +
                   " -c " + vcf_conta + " -s " + summary_file +
                   " -o " + out_dir)
            task_cmd = awk_if_fmt.format(conta_fi=conta_file, cmd=cmd)
            write_intermediate_task(dag_f, task_conf, task_cmd, task_id3b,
                                    task_id4)


def write_dag_file(check: bool, dag_file: str, out_dir: str, report: str,
                   task_fmt: str, vcfs: List[str]) -> None:
    """Write a DAG of tasks into a file

    Args:
        check: A flag to enable contaminant check
        dag_file: the dag file path
        out_dir: Directory to put results
        report: A flag to generate or not the report
        task_fmt: A format string to write a task into the DAG
        vcfs: A list of vcf file path
    """
    page_size = io.DEFAULT_BUFFER_SIZE
    with open(dag_file, "wb", buffering=10 * page_size) as dag_f:
        for current_vcf in vcfs:
            path_obj = Path(current_vcf)
            basename_vcf = path_obj.stem
            vcf_hist = join(out_dir, basename_vcf + ".hist")
            conta_file = join(out_dir, basename_vcf + ".conta")
            report_name = join(out_dir, basename_vcf + ".pdf")

            # calcul allelic balance
            task_id1 = "ABCalc_" + basename_vcf
            task_conf = task_fmt.format(id=task_id1, core=4)
            task_cmd = "calculAllelicBalance.sh -f " + current_vcf + " > " \
                       + vcf_hist
            write_binary(dag_f, task_conf + "\"" + task_cmd + "\"\n")

            # test and report contamination
            task_id2 = "Report_" + basename_vcf
            task_conf = task_fmt.format(id=task_id2, core=1)
            task_cmd = ("contaReport.R --input " + vcf_hist + " --output "
                        + conta_file + " " + report + " --reportName "
                        + report_name)
            write_intermediate_task(dag_f, task_conf, task_cmd, task_id1,
                                    task_id2)

            # proceed to comparison
            if check is True:
                create_report(basename_vcf, conta_file, dag_f, out_dir,
                              task_fmt, task_id2, current_vcf, vcfs)


def write_batch_file(dag_file: str, mail: str, msub_file: str, nb_task: int,
                     out_dir: str) -> None:
    """Write a Batch file to be processed by SLURM

    Args:
        dag_file: The dag file path
        mail: User mail to be notified
        msub_file: path to write the batch file
        nb_task: number of tasks to process
        out_dir: Directory to put results
    """
    with open(msub_file, "wb", ) as msub_f:
        # Parametres MSUB
        write_binary(msub_f,
                     "#!/bin/bash\n" +
                     "#MSUB -r " + script_name + "\n" +
                     "#MSUB -n " + str(nb_task - 1) + "\n" +
                     "#MSUB -c 7 \n" +
                     "#MSUB -T 28800 \n" +
                     "#MSUB -o " + out_dir + script_name + "%j.out\n" +
                     "#MSUB -e " + out_dir + script_name + "%j.err\n")

        if len(mail) > 0:
            msub_f.write(b"#MSUB -@ ${mail}:end\n")

        # Clusters parameters
        hostname = popen("dnsdomainname").read()
        if "cng.fr" in hostname or "cnrgh.fr" in hostname:
            # lirac
            msub_f.write(b"#MSUB -q normal\n")
        elif "ccrt.ccc.cea.fr" in hostname:
            # cobalt
            msub_f.write(b"#MSUB -A fg0062\n#MSUB -q broadwell\n")

        # MODULES LOAD
        write_binary(msub_f,
                     "module load extenv/ig\n" +
                     "module load pegasus\n" +
                     "module load bcftools\n" +
                     "module load bedtools\n" +
                     "module load bedops\n" +
                     "module load useq\n" +
                     "mpirun -oversubscribe -n " + str(nb_task) +
                     " pegasus-mpi-cluster " + dag_file + "\n")


# Main
def main():
    vcfs, out_dir, report, check, mail = get_cli_args()

    dag_file = join(out_dir, script_name + ".dagfile")
    msub_file = join(out_dir, script_name + ".msub")
    if isfile(dag_file):
        remove(dag_file)
    task_fmt = "TASK {id} -c {core} bash -c "
    write_dag_file(check, dag_file, out_dir, report, task_fmt, vcfs)

    nb_task = 2
    nb_vcf = len(vcfs)
    if nb_vcf > 48:
        nb_task = 48
    elif nb_vcf > 1:
        nb_task = nb_vcf + 1

    write_batch_file(dag_file, mail, msub_file, nb_task, out_dir)

    # Start Script
    if isfile((dag_file + ".res*")):
        remove((dag_file + ".res*"))
    cmd = ["/usr/bin/ccc_msub", msub_file]
    p = subprocess.call(cmd)
    if p != 0:
        print("Error while running ccc_msub: {} ".format(" ".join(cmd)),
              file=sys.stderr)
    sys.exit(p)


if __name__ == '__main__':
    # execute only if run as a script
    main()
