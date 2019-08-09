# Import necessary libraries:

from pathlib import Path
from os import access, R_OK, getcwd, makedirs, remove
from os.path import isfile, abspath, isdir, join, exists, basename
from typing import Sequence, Tuple, List, BinaryIO, Dict, Union
import argparse
import io
import subprocess
import sys
import glob
from datetime import datetime
from math import ceil

script_name = "contatester"


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
        -> Tuple[List[str], str, str, bool, str, str, str, str, int, str]:
    """Parse command line parameters
    Parse program parameters using argparse module
    Args:
        :param parameters: Sequence of parameters to be parsed

    Returns:
        A list of vcf file path
        The output directory to be used
        A flag to generate or not the report
        A flag to enable contaminant check
    """
    parser = argparse.ArgumentParser(prog=script_name,
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

    parser.add_argument("-e", "--experiment", default="WG", type=str,
                        help="Experiment type, could be WG for Whole Genome or EX for Exome [default WG] ")

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

    parser.add_argument("-A", "--accounting", default="", type=str,
                        help="msub option for calculation time imputation")

    parser.add_argument("-d", "--dagname", default=default_dagfile_name(),
                        type=str,
                        help="DAG file name for pegasus")

    parser.add_argument("-t", "--thread", default=4, type=int,
                        help=("number of threads "
                              "(optional) [default: 4]"))

    parser.add_argument("-s", "--threshold", default=4, type=int,
                        help=("Threshold for contaminated status"
                              "(optional) [default: 4]"))

    # keep arguments
    args = parser.parse_args(parameters)

    vcf_file = [args.file]
    vcf_list = args.list
    out_dir = abspath(args.outdir)
    check = args.check
    mail = args.mail
    accounting = args.accounting
    dagname = args.dagname
    thread = args.thread
    conta_threshold = args.threshold
    experiment = args.experiment

    if vcf_list is not None:
        try:
            with open(vcf_list, 'r') as filin:
                vcfs = filin.read().splitlines()
                pass
        except IOError:
            print("Error while opening list file {} : "
                  "file does not exist".format(" ".join(vcf_list)),
                  file=sys.stderr)
    else:
        vcfs = vcf_file

    #
    for vcf in vcfs:
        try:
            with open(vcf, 'r'):
                pass
        except IOError:
            print("Error while opening VCF file {} : "
                  "file does not exist".format(" ".join(vcf)),
                  file=sys.stderr)

    if not exists(out_dir):
        makedirs(out_dir)

    if args.report:
        report = "--report"
    else:
        report = ""

    if not thread > 0:
        print("Error : --thread must be greather than 0 ", file=sys.stderr)

    return vcfs, out_dir, report, check, mail, accounting, dagname, thread, conta_threshold, experiment


def default_dagfile_name() -> str:
    dt = datetime.today()
    dag_filename = ("contatest_" + str(dt.year) + str(dt.month) + str(dt.day) +
                    str(dt.hour) + str(dt.minute) + str(dt.second) + ".dagfile")
    return dag_filename


def write_binary(file_handler: BinaryIO, statement: str) -> None:
    """Convert a statement to byte and write it into a file

    Args:
        :param file_handler: A writeable file
        :param statement: any string to be write into the provided file
    """
    file_handler.write(bytes(statement, "ASCII"))


def write_intermediate_task(file_handler: BinaryIO, conf: str, cmd: str,
                            task_a: str, task_b: str) -> None:
    write_binary(file_handler, conf + "\"" + cmd + "\"\n")
    write_binary(file_handler, "EDGE " + task_a + " " + task_b + "\n")


def write_edge_task(file_handler: BinaryIO, task_a: str, task_b: str) -> None:
    write_binary(file_handler, "EDGE " + task_a + " " + task_b + "\n")


def task_cmd_if(conta_file: str, cmd: str) -> str:
    awk_cmd = "{printf \\$NF}"
    awk_if_fmt = ("if [[ $( awk \\'END{awk_cmd}\\' {conta_fi}) = TRUE ]];"
                  " then {cmd} ; fi")
    task_cmd = awk_if_fmt.format(awk_cmd=awk_cmd, conta_fi=conta_file,
                                 cmd=cmd)
    return task_cmd


def create_report(basename_vcf: str, conta_file: str, dag_f: BinaryIO,
                  out_dir: str, task_fmt: str, task_id2: str, current_vcf: str,
                  vcfs: List[str], thread: int) -> None:
    """Report generator

    This function append some extra tasks to the DAG in order to generate a
    report on each provided vcf file

    Args:
        :param basename_vcf: The base name of vcf file
        :param conta_file: The generated contaminant file to be processed
        :param dag_f: the dag file to append the extra tasks
        :param out_dir: Directory to put results
        :param task_fmt: A format string to write a task into the DAG
        :param task_id2: The task id which generate generate the contaminant file
        :param current_vcf: Path to current vcf analysed
        :param vcfs: A list of vcf file path
        :param thread:
    """
    file_extension = "AB_0.00_to_0.11"
    basename_conta = join(out_dir, basename_vcf + "_" + file_extension)
    vcf_conta = join(out_dir, basename_conta + "_noLCRnoDUP.vcf.gz")
    # select potentialy contaminant variants
    task_id3 = "RecupConta_" + basename_vcf
    task_conf = task_fmt.format(id=task_id3, core=thread)
    cmd = ("recupConta.sh -f " + current_vcf + " -c " + vcf_conta)
    task_cmd = task_cmd_if(conta_file, cmd)
    write_intermediate_task(dag_f, task_conf, task_cmd, task_id2, task_id3)
    # summary file for comparisons
    summary_file = join(out_dir, basename_vcf + "_comparisonSummary.txt")
    # comparisons with other vcf
    for vcf_compare in vcfs:
        if vcf_compare != current_vcf:
            vcf_name = basename(vcf_compare)
            vcf_compare_basename = str(vcf_name.split(".vcf")[0])
            task_id4 = ("Compare_" + basename_vcf + "_" +
                        vcf_compare_basename)
            task_conf = task_fmt.format(id=task_id4, core=ceil(thread / 2))
            cmd = ("checkContaminant.sh -f " + vcf_compare +
                   " -c " + vcf_conta + " -s " + summary_file)
            task_cmd = task_cmd_if(conta_file, cmd)
            write_intermediate_task(dag_f, task_conf, task_cmd, task_id3,
                                    task_id4)


def write_dag_file(check: bool, dag_file: str, out_dir: str, report: str,
                   task_fmt: str, vcfs: List[str], thread: int,
                   conta_threshold: int, experiment: str) -> None:
    """Write a DAG of tasks into a file

    Args:
        :param check: A flag to enable contaminant check
        :param dag_file: the dag file path
        :param out_dir: Directory to put results
        :param report: A flag to generate or not the report
        :param task_fmt: A format string to write a task into the DAG
        :param vcfs: A list of vcf file path
        :param thread:
        :param conta_threshold:
        :param experiment:
    """
    page_size = io.DEFAULT_BUFFER_SIZE
    with open(dag_file, "wb", buffering=10 * page_size) as dag_f:
        for current_vcf in vcfs:
            # path_obj = Path(current_vcf)
            # basename_vcf = path_obj.stem
            vcf_name = str(basename(current_vcf))
            basename_vcf = str(vcf_name.split(".vcf")[0])
            vcf_hist = join(out_dir, basename_vcf + ".hist")
            depth_estim = join(out_dir, basename_vcf + ".meandepth")
            conta_file = join(out_dir, basename_vcf + ".conta")
            report_name = join(out_dir, basename_vcf + ".pdf")

            # calcul allelic balance
            task_id1 = "ABCalc_" + basename_vcf
            task_conf = task_fmt.format(id=task_id1, core=1)
            task_cmd = "calculAllelicBalance.sh -f " + current_vcf + " -o " \
                       + vcf_hist
            write_binary(dag_f, task_conf + "\"" + task_cmd + "\"\n")

            # estimate depth
            task_id1b = "EstimDepth_" + basename_vcf
            task_conf = task_fmt.format(id=task_id1b, core=1)
            task_cmd = "depth_estim_from_vcf.sh -f " + current_vcf + " -o " \
                       + depth_estim
            write_binary(dag_f, task_conf + "\"" + task_cmd + "\"\n")

            # test and report contamination
            task_id2 = "Report_" + basename_vcf
            task_conf = task_fmt.format(id=task_id2, core=1)
            task_cmd = ("contaReport.R --input " + vcf_hist + " --output "
                        + conta_file + " " + report + " --reportName "
                        + report_name + " -t " + str(conta_threshold) +
                        " --experiment " + experiment +
                        " -d $(< " + depth_estim + " )")
            write_binary(dag_f, task_conf + "\"" + task_cmd + "\"\n")
            write_edge_task(dag_f, task_id1, task_id2)
            write_edge_task(dag_f, task_id1b, task_id2)

            # proceed to comparison
            if check is True:
                create_report(basename_vcf, conta_file, dag_f, out_dir,
                              task_fmt, task_id2, current_vcf, vcfs, thread)


def write_batch_file(dag_file: str, msub_file: str, nb_vcf: int, out_dir: str,
                     mail: Union[str, None] = None,
                     accounting: Union[str, None] = None,
                     check: bool = False) -> None:
    """Write a Batch file to be processed by SLURM

    Args:
        :param dag_file: The dag file path
        :param mail: User mail to be notified
        :param msub_file: path to write the batch file
        :param nb_vcf: number of tasks to process
        :param out_dir: Directory to put results
        :param accounting: msub option for calculation time imputation
        :param check: option for contaminant identification
    """
    with open(msub_file, "wb", ) as msub_f:
        nb_vcf_by_task = nb_vcf_by_tasks(nb_vcf)
        clust_param = machine_param(out_dir, nb_vcf, check)

        if clust_param.get("cea_clust"):
            # Clusters parameters
            write_binary(msub_f, clust_param.get("msub_info"))
            if clust_param.get("batch_exe") == "ccc_msub":
                batch_exe_mail = ("#MSUB -@ " + mail + ":end\n")
                batch_exe_accounting = "#MSUB -A "
            else:
                batch_exe_mail = ("#MSUB -@ " + mail + ":end\n")
                batch_exe_accounting = "#MSUB -A "

            if mail is not None:
                if len(mail) > 0:
                    write_binary(msub_f, batch_exe_mail)

            if accounting is not None:
                if len(accounting) > 0:
                    write_binary(msub_f, batch_exe_accounting + accounting + "\n")

            # MODULES LOAD
            write_binary(msub_f, clust_param.get("msub_module_load"))

            # PEGASUS Command
            mpi_exe = clust_param.get("mpi_exe")
            mpi_opt = clust_param.get("mpi_opt")

            # host_cpus = param[4]
            write_binary(msub_f, mpi_exe + " " + mpi_opt + " -n " +
                         str(nb_vcf_by_task + 1) + " pegasus-mpi-cluster " +
                         dag_file + "\n")

        else:
            write_binary(msub_f, clust_param.get("msub_info"))
            # PEGASUS Command
            mpi_exe = clust_param.get("mpi_exe")
            mpi_opt = clust_param.get("mpi_opt")
            write_binary(msub_f, mpi_exe + " " + mpi_opt + " -n " +
                         str(2) + " pegasus-mpi-cluster --keep-affinity " +
                         dag_file + "\n")
            if mail is not None:
                if len(mail) > 0:
                    write_binary(msub_f, 'mail -s "[Contatester] is terminate" '
                                 + mail + ' < /dev/null\n')


def machine_param(out_dir: str, nb_vcf: int,
                  check: bool = False) -> Dict[str, Union[bool, str]]:
    """ Test machine and apply a configuration
    Usage :
    clust_param = machine_param(out_dir, nb_task))
    mpi_exe = clust_param.get("mpi_exe")
    mpi_opt = clust_param.get("mpi_opt")
    tasks = 10
    dag = "dag.txt"
    cmd = mpi_exe + " " + mpi_opt + " -n " + str(tasks) +
    " pegasus-mpi-cluster " + dag
    :param out_dir:
    :param nb_vcf:
    :param check
    :return: dictionary
    """
    nb_vcf_by_task = nb_vcf_by_tasks(nb_vcf)
    pipeline_duration = job_duration(nb_vcf, check)

    common_load = ("module load pegasus\n" +
                   "module load bcftools\n" +
                   "module load samtools\n" +
                   "module load r\n")

    if isdir("/ccc"):
        # si machine cobalt
        cea_clust = True
        batch_exe = "ccc_msub"
        run_exe = "ccc_mprun"
        mpi_exe = "ccc_mprun"
        mpi_opt = "-E '--overcommit'"
        nb_core = 4
        # host_cpus = 28

        msub_info = ("#!/bin/bash\n" +
                     "#MSUB -r " + script_name + "\n" +
                     "#MSUB -n " + str(nb_vcf_by_task) + "\n" +
                     "#MSUB -o " + join(out_dir, script_name) + "%j.out\n" +
                     "#MSUB -e " + join(out_dir, script_name) + "%j.err\n" +
                     "#MSUB -c " + str(nb_core) + "\n" +
                     "#MSUB -q broadwell\n" +
                     "#MSUB -T " + str(pipeline_duration) + "\n")
        msub_module_load = ("module load extenv/ig\n" +
                            common_load)
    elif isdir("/env/cng"):
        # # si machine cnrgh
        cea_clust = True
        batch_exe = "ccc_msub"
        run_exe = "ccc_mprun"
        mpi_exe = "mpirun"
        mpi_opt = "-oversubscribe"
        nb_core = 4
        # host_cpus = 32

        msub_info = ("#!/bin/bash\n" +
                     "#MSUB -r " + script_name + "\n" +
                     "#MSUB -n " + str(nb_vcf_by_task) + "\n" +
                     "#MSUB -o " + join(out_dir, script_name) + "%j.out\n" +
                     "#MSUB -e " + join(out_dir, script_name) + "%j.err\n" +
                     "#MSUB -c " + str(nb_core) + "\n" +
                     "#MSUB -q normal\n" +
                     "#MSUB -T " + str(pipeline_duration) + "\n")
        msub_module_load = common_load
    else:
        # Default machine
        cea_clust = False
        batch_exe = "bash"
        run_exe = ""
        mpi_exe = "mpirun"
        mpi_opt = "-oversubscribe"
        nb_core = 1
        # host_cpus = ""
        msub_info = ("#!/bin/bash\n" +
                     "err_report(){ echo \"Error on ${BASH_SOURCE} line $1\" >&2; exit 1; }\n" +
                     "trap 'err_report $LINENO' ERR\n" +
                     "set -eo pipefail\n")
        msub_module_load = ""

    clust_param = {}
    clust_param["cea_clust"] = cea_clust
    clust_param["batch_exe"] = batch_exe
    clust_param["run_exe"] = run_exe
    clust_param["mpi_exe"] = mpi_exe
    clust_param["mpi_opt"] = mpi_opt
    clust_param["nb_core"] = nb_core
    # clust_param["host_cpus"] = host_cpus
    clust_param["msub_module_load"] = msub_module_load
    clust_param["msub_info"] = msub_info

    return clust_param


def nb_vcf_by_tasks(nb_vcf: int) -> int:
    """
    Used to set a maximum number of task to launch in parallele depending of the
    total number of task
    :param nb_vcf:
    :return: nb_vcf_by_task
    """
    if nb_vcf > 48:
        nb_vcf_by_task = 48
    elif nb_vcf > 1:
        nb_vcf_by_task = nb_vcf
    else:
        nb_vcf_by_task = 1
    return nb_vcf_by_task


def nb_runs(nb_vcf: int, nb_vcf_by_task: int) -> int:
    nb_run = ceil(nb_vcf / nb_vcf_by_task)
    return nb_run


def job_duration(nb_vcf: int, check: bool = False) -> int:
    """
    Used to set an optimised maximum time duration for the job
    :param nb_vcf:
    :param check:
    :return: pipeline_duration
    """
    ABcalcul_time = 3 * 60
    if check:
        recupConta_time = 3 * 60
        checkconta_time = 1 * 60
    else:
        recupConta_time = 0
        checkconta_time = 0
    nb_vcf_by_task = nb_vcf_by_tasks(nb_vcf)
    nb_run = nb_runs(nb_vcf, nb_vcf_by_task) + 1
    # Max 1/3 samples are contaminated case
    nb_conta = ceil(nb_vcf * 1 / 3)
    nb_run_recupconta = nb_runs(nb_conta, nb_vcf_by_tasks(nb_conta))
    nb_checkconta = nb_conta * (nb_vcf - 1)
    nb_run_checkconta = nb_runs(nb_checkconta, nb_vcf_by_tasks(nb_checkconta))
    pipeline_duration = (ABcalcul_time * nb_run +
                         recupConta_time * nb_run_recupconta +
                         checkconta_time * nb_run_checkconta)
    # maximum job duration 24h
    if pipeline_duration > 86400:
        pipeline_duration = 86400
    return pipeline_duration


# Main
def main():
    vcfs, out_dir, report, check, mail, accounting, dagname, thread, conta_threshold, experiment = get_cli_args()

    dag_file = join(out_dir, dagname)
    msub_file = join(out_dir, dagname + ".msub")
    if isfile(dag_file):
        remove(dag_file)
    task_fmt = "TASK {id} -c {core} bash -c "
    write_dag_file(check, dag_file, out_dir, report, task_fmt, vcfs, int(thread),
                   conta_threshold, experiment)

    nb_vcf = len(vcfs)
    nb_vcf_by_task = nb_vcf_by_tasks(nb_vcf)
    write_batch_file(dag_file, msub_file, nb_vcf_by_task, out_dir, mail, accounting)

    # remove rescue file and ressource file
    res_files = glob.glob(dag_file + ".res*")
    for res in res_files:
        if isfile(res):
            remove(res)

    # Start Script
    clust_param = machine_param(out_dir, nb_vcf, check)
    batch_exe = clust_param.get("batch_exe")
    cmd = [batch_exe, msub_file]

    p = subprocess.call(cmd)
    if p != 0:
        print("Error while running contatester: {} ".format(" ".join(cmd)),
              file=sys.stderr)
    sys.exit(p)


if __name__ == '__main__':
    # execute only if run as a script
    main()
