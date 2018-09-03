import os
from os.path import isfile, isdir, abspath
from typing import Sequence, List, Union

import pytest

from fr.cea.lbi.MyAwesomeProject.__main__ import get_cli_args


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
    if value == 'my_input_dir':
        result = True
    else:
        result = isdir(value)
    return result


@pytest.fixture
def mock_os(mocker):
    mocker.patch('fr.cea.lbi.MyAwesomeProject.__main__.access', side_effect=access_mocking)
    mocker.patch('fr.cea.lbi.MyAwesomeProject.__main__.isfile', side_effect=isfile_mocking)
    mocker.patch('fr.cea.lbi.MyAwesomeProject.__main__.isdir', side_effect=isdir_mocking)


@pytest.mark.parametrize('parameters, fields_expected',
                         [(('-n', '10', 'my_input_dir', 'foo.input', 'foo.result'), (('number', 10),
                                                                                     ('INPUT_DIRECTORY',
                                                                                      abspath('my_input_dir')),
                                                                                     ('INPUT_FILE',
                                                                                      abspath('foo.input')),
                                                                                     ('OUTPUT_FILE',
                                                                                      abspath('foo.result')))),
                          (('my_input_dir', 'foo.input', 'foo.result'), (('INPUT_DIRECTORY', abspath('my_input_dir')),
                                                                         ('INPUT_FILE', abspath('foo.input')),
                                                                         ('OUTPUT_FILE', abspath('foo.result'))))])
@pytest.mark.usefixtures('mock_os')
def test_allowed_usage(parameters: Sequence[str], fields_expected: List[Union[str, int]]):
    args = get_cli_args(parameters)
    for field, expected in fields_expected:
        assert field in args
        assert getattr(args, field) == expected


@pytest.mark.parametrize('parameters',
                         [('-s', '10', 'my_input_dir', 'foo.input', 'foo.result'),
                          ('my_input_dir2', 'foo.input', 'foo.result'),
                          ('my_input_dir', 'foo.input2', 'foo.result'),
                          ('my_input_dir', 'foo.input', 'my_input_dir')])
@ pytest.mark.usefixtures('mock_os')
def test_not_allowed_usage(parameters: Sequence[str]):
    with pytest.raises(SystemExit):
        args = get_cli_args(parameters)
