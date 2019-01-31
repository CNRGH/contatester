import pytest
from typing import List, Union
from pkg_resources import resource_filename
from fr.cea.lbi.contatester.__main__ import task_cmd_if, nb_tasks, write_batch_file
from os.path import dirname
from pytest_mock import mocker
from os.path import isdir


def is_default_env_dir(dir: str):
    result = False
    if dir in ('/ccc', '/env/cnrgh'):
        result = False
    else:
        result = isdir(dir)

    return result


def is_cnrgh_env_dir(dir: str):
    result = False
    if dir == '/env/cnrgh':
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
    elif dir == '/env/cnrgh':
        result = False
    else:
        result = isdir(dir)
    return result


@pytest.mark.parametrize('conta_file, cmd, expected',
                            (
                                ('test_file', 'echo "Hello world"', 'if [[ $( awk \\\'END{printf \\$NF}\\\' test_file) = TRUE ]]; then echo "Hello world" ; fi'),
                                ('test file', 'cat toto', 'if [[ $( awk \\\'END{printf \\$NF}\\\' test file) = TRUE ]]; then cat toto ; fi')
                            ))
def test_task_cmd_if(conta_file: str, cmd: str, expected: str) -> None:
    res = task_cmd_if(conta_file, cmd)
    assert res == expected


@pytest.mark.parametrize('vcfs, expected', (
                                                (['file1.vcf'], 1),
                                                (['file{}.vcf'.format(i) for i in range(0, 12)], 12),
                                                (['file{}.vcf'.format(i) for i in range(0, 48)], 48),
                                                (['file{}.vcf'.format(i) for i in range(0, 55)], 48))
                        )
def test_nb_tasks(vcfs: List[str], expected: int) -> None:
    nb = nb_tasks(vcfs)
    assert expected == nb


@pytest.mark.parametrize('env', ('default', 'cnrgh', 'ccrt'))
@pytest.mark.parametrize('dag_file  , msub_file         , nb_task   , out_dir, mail             , accounting, expected_file', (
                        ('test1.dag', '/tmp/test1.msub' , 5         , '/tmp/', 'foo@compagny.com', None     , 'batch_file1_{}.msub'),
                        ('test1.dag', '/tmp/test2.msub' , 5         , '/tmp/', 'foo@compagny.com', 'foo'    , 'batch_file2_{}.msub'),
                        ('test1.dag', '/tmp/test3.msub' , 5         , '/tmp/', 'foo@compagny.com', ''       , 'batch_file1_{}.msub'),)
                        )
def test_write_batch_file(mocker, env: str, dag_file: str, msub_file: str, nb_task: int,
                          out_dir: str, mail: Union[str, None],
                          accounting: Union[str, None], expected_file: str):
    if env == 'default':
        mocker.patch('fr.cea.lbi.contatester.__main__.isdir', side_effect=is_default_env_dir )
    elif env == 'cnrgh':
        mocker.patch('fr.cea.lbi.contatester.__main__.isdir', side_effect=is_cnrgh_env_dir )
    elif env == 'ccrt':
        mocker.patch('fr.cea.lbi.contatester.__main__.isdir', side_effect=is_ccrt_env_dir )
    else:
        raise Exception('Not yet supported environnement: ' + env)

    write_batch_file(dag_file, msub_file, nb_task, out_dir, mail, accounting)
    content = open(msub_file, 'r').readlines()
    expected_filename = resource_filename('tests.fr.cea.lbi.contatester.resources', expected_file.format(env))
    expected_content = open(expected_filename, 'r').readlines()
    assert content == expected_content
    assert dirname(msub_file) == dirname(out_dir)
