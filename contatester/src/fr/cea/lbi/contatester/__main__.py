# Import necessary libraries:

from pathlib import Path
from os import access, R_OK, getcwd, makedirs, remove, popen
from os.path import isfile, abspath, isdir, join, exists
from typing import Sequence, Tuple, List, BinaryIO, Dict, Union
import argparse
import io
import subprocess
import sys
import glob
from datetime import datetime

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
        -> Tuple[List[str], str, str, bool, str, str, str]:
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

    parser.add_argument("-A", "--accounting", default="", type=str,
                        help="msub option for calculation time imputation")

    parser.add_argument("-d", "--dagname", default=default_dagfile_name(),
                        type=str,
                        help="DAG file name for pegasus")

    # keep arguments
    args = parser.parse_args(parameters)

    vcf_file = [args.file]
    vcf_list = args.list
    out_dir = abspath(args.outdir)
    check = args.check
    mail = args.mail
    accounting = args.accounting
    dagname = args.dagname

    if vcf_list is not None:
        with open(vcf_list, 'r') as filin:
            vcfs = filin.read().splitlines()
    else:
        vcfs = vcf_file

    if not exists(out_dir):
        makedirs(out_dir)

    if args.report:
        report = "--report"
    else:
        report = ""

    return vcfs, out_dir, report, check, mail, accounting, dagname


def default_dagfile_name() -> str:
    dt = datetime.today()
    dag_filename = ("contatest_" + str(dt.year) + str(dt.month) + str(dt.day) +
                    str(dt.hour) + str(dt.minute) + str(dt.second) + ".dagfile")
    return dag_filename


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


def task_cmd_if(conta_file: str, cmd: str) -> str:
    awk_cmd = "{printf \$NF}"
    awk_if_fmt = ("if [[ $( awk \\'END{awk_cmd}\\' {conta_fi}) = TRUE ]];"
                  " then {cmd} ; fi")
    task_cmd = awk_if_fmt.format(awk_cmd=awk_cmd, conta_fi=conta_file,
                                 cmd=cmd)
    return task_cmd


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
    # select potentialy contaminant variants
    task_id3 = "RecupConta_" + basename_vcf
    task_conf = task_fmt.format(id=task_id3, core=4)
    cmd = ("recupConta.sh -f " + current_vcf + " -c " + vcf_conta + " -b "
           + bedfile)
    task_cmd = task_cmd_if(conta_file, cmd)
    write_intermediate_task(dag_f, task_conf, task_cmd, task_id2, task_id3)
    # summary file for comparisons
    summary_file = join(out_dir, basename_vcf + "_comparisonSummary.txt")
    task_id3b = "SummaryFile_" + basename_vcf
    task_conf = task_fmt.format(id=task_id3b, core=1)
    cmd = ("echo \\'comparison\\' \\'QUALThreshold\\' \\'NumMatchTest\\' "
           "\\'NumNonMatchTest\\' "
           "\\'FDR=nonMatchTest/(matchTest+nonMatchTest)\\' "
           "\\'decreasingFDR\\' "
           "\\'TPR=matchTest/totalKey\\' \\'FPR=nonMatchTest/totalKey\\' "
           "\\'PPV=matchTest/(matchTest+nonMatchTest)\\' > " + summary_file)
    task_cmd = task_cmd_if(conta_file, cmd)
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
            task_conf = task_fmt.format(id=task_id4, core=14)
            cmd = ("checkContaminant.sh -f " + vcf_compare + " -b " + bedfile +
                   " -c " + vcf_conta + " -s " + summary_file +
                   " -o " + out_dir)
            task_cmd = task_cmd_if(conta_file, cmd)
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
                     out_dir: str, accounting: str) -> None:
    """Write a Batch file to be processed by SLURM

    Args:
        dag_file: The dag file path
        mail: User mail to be notified
        msub_file: path to write the batch file
        nb_task: number of tasks to process
        out_dir: Directory to put results
        accounting: msub option for calculation time imputation
    """
    with open(msub_file, "wb", ) as msub_f:
        clust_param = machine_param()

        if clust_param.get("cea_clust"):
            # Parametres MSUB
            write_binary(msub_f,
                         "#!/bin/bash\n" +
                         "#MSUB -r " + script_name + "\n" +
                         "#MSUB -n " + str(nb_task) + "\n" +
                         "#MSUB -o " + out_dir + script_name + "%j.out\n" +
                         "#MSUB -e " + out_dir + script_name + "%j.err\n")
            # Clusters parameters
            write_binary(msub_f, clust_param.get("msub_info"))

            if len(mail) > 0:
                write_binary(msub_f, "#MSUB -@ " + mail + ":end\n")

            if len(accounting) > 0:
                write_binary(msub_f, "#MSUB -A " + accounting + "\n")

            # Clusters parameters

            # hostname = popen("dnsdomainname").read()
            # if "cng.fr" in hostname or "cnrgh.fr" in hostname:
            #     # lirac
            #     write_binary(msub_f, "#MSUB -q normal\n")
            # elif "ccrt.ccc.cea.fr" in hostname:
            #     # cobalt
            #     write_binary(msub_f, "#MSUB -A fg0062\n#MSUB -q broadwell\n")

            # MODULES LOAD
            write_binary(msub_f, clust_param.get("msub_module_load"))
            # write_binary(msub_f,
            #              "module load extenv/ig\n" +
            #              "module load pegasus\n" +
            #              "module load bcftools\n" +
            #              "module load bedtools\n" +
            #              "module load bedops\n" +
            #              "module load useq\n")

            # PEGASUS Command

            mpi_exe = clust_param.get("mpi_exe")
            mpi_opt = clust_param.get("mpi_opt")

            # host_cpus = param[4]
            write_binary(msub_f, mpi_exe + " " + mpi_opt + " -n " +
                         str(nb_task + 1) + " pegasus-mpi-cluster " +
                         dag_file + "\n")
            # write_binary(msub_f, mpi_exe + " " + mpi_opt + " -n " +
            #              str(nb_task + 1) + " pegasus-mpi-cluster --host-cpus " +
            #              str(host_cpus) + " " + dag_file + "\n")
        else:
            write_binary(msub_f, "#!/bin/bash\n" + "pegasus-mpi-cluster " +
                         dag_file + "\n")


def machine_param() -> Dict[str, Union[bool, str]]:
    """ Test machine and apply a configuration
    Usage :
    clust_param = machine_param()
    mpi_exe = clust_param.get("mpi_exe")
    mpi_opt = clust_param.get("mpi_opt")
    tasks = 10
    dag = "dag.txt"
    cmd = mpi_exe + " " + mpi_opt + " -n " + str(tasks) +
    " pegasus-mpi-cluster " + dag

    :return: dictionary
    """

    common_load = ("module load pegasus\n" +
                   "module load bcftools\n" +
                   "module load bedtools\n" +
                   "module load bedops\n" +
                   "module load useq\n")

    if isdir("/ccc"):
        # si machine cobalt
        cea_clust = True
        batch_exe = "ccc_msub"
        run_exe = "ccc_mprun"
        mpi_exe = "ccc_mprun"
        mpi_opt = "-E '--overcommit '"
        nb_core = 14
        # host_cpus = 28
        msub_info = ("#MSUB -c " + str(nb_core) + " \n" +
                     "#MSUB -q broadwell\n" +
                     "#MSUB -T 86400 \n")
        msub_module_load = ("module load extenv/ig\n" +
                            common_load)
    elif isdir("/env/cnrgh"):
        # si machine cnrgh
        cea_clust = True
        batch_exe = "sbatch"
        run_exe = "srun"
        mpi_exe = "mpirun"
        mpi_opt = "-E '--oversubscribe'"
        nb_core = 7
        # host_cpus = 32
        msub_info = ("#MSUB -c " + str(nb_core) + " \n" +
                     "#MSUB -q normal\n" +
                     "#MSUB -T 86400 \n")
        msub_module_load = common_load
    else:
        # Default machine
        cea_clust = False
        batch_exe = ""
        run_exe = ""
        mpi_exe = ""
        mpi_opt = ""
        nb_core = 4
        # host_cpus = ""
        msub_info = ""
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


def nb_tasks(vcfs: List[str]) -> int:
    nb_vcf = len(vcfs)
    if nb_vcf > 48:
        nb_task = 48
    elif nb_vcf > 1:
        nb_task = nb_vcf
    else:
        nb_task = 1
    return nb_task


# Main
def main():
    vcfs, out_dir, report, check, mail, accounting, dagname = get_cli_args()

    dag_file = join(out_dir, dagname)
    msub_file = join(out_dir, dagname[0:-8] + ".msub")
    if isfile(dag_file):
        remove(dag_file)
    task_fmt = "TASK {id} -c {core} bash -c "
    write_dag_file(check, dag_file, out_dir, report, task_fmt, vcfs)

    nb_task = nb_tasks(vcfs)
    write_batch_file(dag_file, mail, msub_file, nb_task, out_dir, accounting)

    # remove rescue file and ressource file
    res_files = glob.glob(dag_file + ".res*")
    for res in res_files:
        if isfile(res):
            remove(res)

    # Start Script

    clust_param = machine_param()
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
