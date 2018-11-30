import os
from os.path import isfile, isdir, abspath
from typing import Sequence, List, Union
from pytest_mock import mocker

import pytest
from unittest.mock import mock_open

from fr.cea.lbi.contatester.__main__ import get_cli_args


def access_mocking(path: str, mode: int) -> int:
    result = False
    if path == 'foo.input' or path == 'my_input_dir':
        result = True
    else:
        result = os.access(path, mode)
    return result


def isfile_mocking(value: str) -> bool:
    result = False
    if value == 'foo.input':
        result = True
    else:
        result = isfile(value)
    return result


def isdir_mocking(value: str) -> bool:
    result = False
    if value == "my_input_dir":
        result = True
    else:
        result = isdir(value)
    return result


def default_dagfile_name_mocking() -> str:
    dag_filename = "contatest_19000101000000.dagfile"
    return dag_filename


@pytest.fixture
def mock_os(mocker):
    mocker.patch('fr.cea.lbi.contatester.__main__.access', side_effect=access_mocking)
    mocker.patch('fr.cea.lbi.contatester.__main__.isfile', side_effect=isfile_mocking)
    mocker.patch('fr.cea.lbi.contatester.__main__.isdir', side_effect=isdir_mocking)
    mocker.patch('fr.cea.lbi.contatester.__main__.default_dagfile_name', side_effect=default_dagfile_name_mocking)
    mocker.patch('builtins.open', mock_open(read_data=abspath('foo.input')+"\n"))


@pytest.mark.parametrize('parameters, fields_expected',
                         [(('-f', 'foo.input'),                                                      (([abspath('foo.input')], os.getcwd(),           '',         False, '',            '',       'contatest_19000101000000.dagfile'))),
                          (('-l', 'foo.input'),                                                      (([abspath('foo.input')], os.getcwd(),           '',         False, '',            '',       'contatest_19000101000000.dagfile'))),
                          (('-f', 'foo.input', '-o', 'my_out_dir'),                                  (([abspath('foo.input')], abspath('my_out_dir'), '',         False, '',            '',       'contatest_19000101000000.dagfile'))),
                          (('-f', 'foo.input', '-o', 'my_out_dir', '-r'),                            (([abspath('foo.input')], abspath('my_out_dir'), '--report', False, '',            '',       'contatest_19000101000000.dagfile'))),
                          (('-f', 'foo.input', '-o', 'my_out_dir', '-r', '-c', '-m', 'foo@foo.com'), (([abspath('foo.input')], abspath('my_out_dir'), '--report', True,  'foo@foo.com', '',       'contatest_19000101000000.dagfile'))),
                          (('-f', 'foo.input', '-o', 'my_out_dir', '-r', '-c', '-A', 'fg0000'),      (([abspath('foo.input')], abspath('my_out_dir'), '--report', True,  '',            'fg0000', 'contatest_19000101000000.dagfile'))),
                          (('-f', 'foo.input', '-o', 'my_out_dir', '-r', '-c', '-d', 'test.dagfile'),(([abspath('foo.input')], abspath('my_out_dir'), '--report', True,  '',            '',       'test.dagfile'))),
                          (('-l', 'foo.input', '-o', 'my_out_dir'),                                  (([abspath('foo.input')], abspath('my_out_dir'), '',         False, '',            '',       'contatest_19000101000000.dagfile'))),
                          (('-l', 'foo.input', '-o', 'my_out_dir', '-r'),                            (([abspath('foo.input')], abspath('my_out_dir'), '--report', False, '',            '',       'contatest_19000101000000.dagfile'))),
                          (('-l', 'foo.input', '-o', 'my_out_dir', '-r', '-c', '-m', 'foo@foo.com'), (([abspath('foo.input')], abspath('my_out_dir'), '--report', True,  'foo@foo.com', '',       'contatest_19000101000000.dagfile')))
                          ])
@pytest.mark.usefixtures('mock_os')
def test_allowed_usage(parameters: Sequence[str], fields_expected: List[Union[str, int]]):
    args = get_cli_args(parameters)
    for i, expected in enumerate(fields_expected):
        assert args[i] == expected


@pytest.mark.parametrize('parameters',
                         [('-s', 'foo.input'),
                          ('-f', 'foo.input', '-l', 'foo.input'),
                          ('my_input_dir', 'foo.input2', 'foo.result'),
                          ('-f', 'foo.input', '-m'),
                          ('-f', 'foo.input', '-r', 'foo.result'),
                          ('-f', 'my_input_dir')
                         ])
@pytest.mark.usefixtures('mock_os')
def test_not_allowed_usage(parameters: Sequence[str]):
    with pytest.raises(SystemExit):
        args = get_cli_args(parameters)


