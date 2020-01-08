from typing import List, Union
from pkg_resources import resource_filename
from os.path import dirname
from os.path import isdir
import pytest
from pytest_mock import mocker
from fr.cea.cnrgh.lbi.contatester.__main__ import task_cmd_if, nb_vcf_by_tasks, write_batch_file, nb_runs, job_duration, write_dag_file, write_edge_task, create_report, write_intermediate_task, write_intermediate_task, write_binary


def is_default_env_dir(dir: str):
    result = False
    if dir in ('/ccc', '/env/cng'):
        result = False
    else:
        result = isdir(dir)
    return result


def is_cnrgh_env_dir(dir: str):
    result = False
    if dir == '/env/cng':
        result = True
    elif dir == '/ccc':
        result = False
    else:
        result = isdir(dir)
    return result


def is_ccrt_env_dir(dir: str):
    result = False
    if dir == '/ccc':
        result = True
    elif dir == '/env/cng':
        result = False
    else:
        result = isdir(dir)
    return result


@pytest.mark.parametrize('conta_file, cmd, expected',
                         (('test_file', 'echo "Hello world"', 'if [[ $( awk \\\'END{printf \\$NF}\\\' test_file) = TRUE ]]; then echo "Hello world" ; fi'),
                          ('test file', 'cat toto', 'if [[ $( awk \\\'END{printf \\$NF}\\\' test file) = TRUE ]]; then cat toto ; fi')
                          ))
def test_task_cmd_if(conta_file: str, cmd: str, expected: str) -> None:
    res = task_cmd_if(conta_file, cmd)
    assert res == expected


@pytest.mark.parametrize('vcfs, max_vcf_by_task, expected',
                         ((['file1.vcf'], 48, 1),
                          (['file{}.vcf'.format(i) for i in range(0, 12)], 48, 12),
                          (['file{}.vcf'.format(i) for i in range(0, 48)], 48, 48),
                          (['file{}.vcf'.format(i) for i in range(0, 55)], 48, 48),
                          (['file1.vcf'], 96, 1),
                          (['file{}.vcf'.format(i) for i in range(0, 12)], 96, 12),
                          (['file{}.vcf'.format(i) for i in range(0, 96)], 96, 96),
                          (['file{}.vcf'.format(i) for i in range(0, 101)], 96, 96)
                          ))
def test_nb_vcf_by_tasks(vcfs: List[str], max_vcf_by_task: int, expected: int) -> None:
    nb = nb_vcf_by_tasks(vcfs, max_vcf_by_task)
    assert expected == nb


@pytest.mark.parametrize('nb_vcf, nb_vcf_by_task, expected',
                         ((1,  48,  1),
                          (1,  96,  1),
                          (95, 48,  2),
                          (101, 6, 17)
                          ))
def test_nb_runs(nb_vcf: int, nb_vcf_by_task: int, expected: int) -> None:
    nb_run = nb_runs(nb_vcf, nb_vcf_by_task)
    assert nb_run == expected


@pytest.mark.parametrize('nb_vcf, check, expected',
                         ((1,      False,   360),
                          (5,      False,   360),
                          (49,     False,   540),
                          (100000, False, 86400),
                          (1,      True,   540),
                          (5,      True,   600),
                          (49,     True,  1740),
                          (100000, True, 86400)
                          ))
def test_job_duration(nb_vcf: int, check: bool, expected: int) -> None:
    pipeline_duration = job_duration(nb_vcf, check)
    assert pipeline_duration == expected


@pytest.mark.parametrize('env', ('default', 'cnrgh', 'ccrt'))
@pytest.mark.parametrize('dag_file    ,         msub_file,  nb_vcf, thread, out_dir,               mail, accounting, expected_file',
                         (('test1.dag', '/tmp/test1.msub',       5,      4, '/tmp/', 'foo@compagny.com',       None, 'batch_file1_{}.msub'),
                          ('test1.dag', '/tmp/test2.msub',       5,      4, '/tmp/', 'foo@compagny.com',      'foo', 'batch_file2_{}.msub'),
                          ('test1.dag', '/tmp/test3.msub',       5,      4, '/tmp/', 'foo@compagny.com',         '', 'batch_file1_{}.msub'),
                         ))
def test_write_batch_file(mocker, env: str, dag_file: str, msub_file: str, nb_vcf: int,
                          thread: int,
                          out_dir: str, mail: Union[str, None],
                          accounting: Union[str, None], expected_file: str):
    if env == 'default':
        mocker.patch('fr.cea.cnrgh.lbi.contatester.__main__.isdir', side_effect=is_default_env_dir )
    elif env == 'cnrgh':
        mocker.patch('fr.cea.cnrgh.lbi.contatester.__main__.isdir', side_effect=is_cnrgh_env_dir )
    elif env == 'ccrt':
        mocker.patch('fr.cea.cnrgh.lbi.contatester.__main__.isdir', side_effect=is_ccrt_env_dir )
    else:
        raise Exception('Not yet supported environnement: ' + env)

    write_batch_file(dag_file, msub_file, nb_vcf, thread, out_dir, mail, accounting)
    content = open(msub_file, 'r').readlines()
    expected_filename = resource_filename('tests.fr.cea.cnrgh.lbi.contatester.resources', expected_file.format(env))
    expected_content = open(expected_filename, 'r').readlines()
    assert content == expected_content
    # assert dirname(msub_file) == dirname(out_dir)


# TODO create_report


@pytest.mark.parametrize('check,                                 dag_file, out_dir,     report,                       task_fmt,                                          vcfs, thread, conta_threshold, experiment,                    expected_file',
                         ((False, '/tmp/test_5vcf_report_nocheck.dagfile', '/tmp/', '--report', "TASK {id} -c {core} bash -c ", ['file{}.vcf'.format(i) for i in range(0, 5)],      1,               4,       'WG', 'test_5vcf_report_nocheck.dagfile'),
                          (False,        '/tmp/test_5vcf_nocheck.dagfile', '/tmp/',         '', "TASK {id} -c {core} bash -c ", ['file{}.vcf'.format(i) for i in range(0, 5)],      1,               4,       'WG',        'test_5vcf_nocheck.dagfile'),
                          (True,    '/tmp/test_5vcf_report_check.dagfile', '/tmp/', '--report', "TASK {id} -c {core} bash -c ", ['file{}.vcf'.format(i) for i in range(0, 5)],      7,               4,       'WG',   'test_5vcf_report_check.dagfile'),
                          (True,           '/tmp/test_5vcf_check.dagfile', '/tmp/',         '', "TASK {id} -c {core} bash -c ", ['file{}.vcf'.format(i) for i in range(0, 5)],      7,               4,       'WG',          'test_5vcf_check.dagfile'),
                          (False, '/tmp/test_1vcf_report_nocheck.dagfile', '/tmp/', '--report', "TASK {id} -c {core} bash -c ",                                 ['file1.vcf'],      1,               4,       'WG', 'test_1vcf_report_nocheck.dagfile'),
                          (False,        '/tmp/test_1vcf_nocheck.dagfile', '/tmp/',         '', "TASK {id} -c {core} bash -c ",                                 ['file1.vcf'],      1,               4,       'WG',        'test_1vcf_nocheck.dagfile')
                          # (True,    '/tmp/test_1vcf_report_check.dagfile', '/tmp/', '--report', "TASK {id} -c {core} bash -c ",                                 ['file1.vcf'],      7,               4,       'WG',   'test_1vcf_report_check.dagfile'),
                          # (True,           '/tmp/test_1vcf_check.dagfile', '/tmp/',         '', "TASK {id} -c {core} bash -c ",                                 ['file1.vcf'],      7,               4,       'WG',          'test_1vcf_check.dagfile'),
                         ))
def test_write_dag_file(check: bool, dag_file: str, out_dir: str, report: str,
                        task_fmt: str, vcfs: List[str], thread: int,
                        conta_threshold: int, experiment: str, expected_file: str):
    write_dag_file(check, dag_file, out_dir, report, task_fmt, vcfs, thread, conta_threshold, experiment)
    content = open(dag_file, 'r').readlines()
    expected_filename = resource_filename(
        'tests.fr.cea.cnrgh.lbi.contatester.resources', expected_file)
    expected_content = open(expected_filename, 'r').readlines()
    assert content == expected_content
    # assert dirname(dag_file) == dirname(out_dir)
