# Contatester Wrapper project

Wrapper for the detection and determination of the presence of cross
contaminant using pegasus for high efficiency

## Usage

```
usage: contatester [options]

Wrapper for the detection and determination of the presence of cross
contaminant

optional arguments:
  -h, --help            show this help message and exit
  -f FILE, --file FILE  VCF file version 4.2 to process. If -f is used don't
                        use -l (Mandatory)
  -l LIST, --list LIST  input text file, one vcf by lane. If -l is used don't
                        use -f (Mandatory)
  -o OUTDIR, --outdir OUTDIR
                        folder for storing all output files (optional)
                        [default: current directory]
  -r, --report          create a pdf report for contamination estimation
                        [default: no report]
  -c, --check           enable contaminant check for the list of VCF provided
                        if a VCF is marked as contaminated
  -m MAIL, --mail MAIL  send an email at the end of the job

```

## Before to code

You have to rename the python project, for this task:
- Open the `setup.py` file located into the root of the project
    - Change the value of `name` variable
    - If it is an application:
      - Change the entry point `console_scripts`
      - Rename the directory `src/fr/cea/lbi/contatester` by your project name
    - if it is a library
      - Remove tne entry point `console_scripts`

## License

CEA project should use CeCILL license, see corresponding [CEA presse page](http://www.cea.fr/presse/Pages/actualites-communiques/ntic/licence-CeCILL-reconnue-par-Open-source-initiative.aspx).

## Code quality

Any new python project need to:
 - Be compatible python 3.6 or higher
 - Use Typing see [pep 484](https://www.python.org/dev/peps/pep-0484/) and its [documentation](https://docs.python.org/3/library/typing.html)
 - Own a wide range of tests 

This project include:
 - A framework to test various use cases and unit tests ([pytest](https://pytest.org))
 - A code coverage tools ([coverage.py](https://coverage.readthedocs.io/))

 You have to run `python setup.py coverage` before each production release and most of other times. These tools
 generate html reports into the directory `htmlcov`

## TEMP Install 

'''
# deactivate
# rm -r el7_env/ dist/ build/
python3 -m venv el7_env
source el7_env/bin/activate
pip install --upgrade pip wheel setuptools
python setup.py bdist_wheel 
pip install dist/contatester-0.0.1-py2.py3-none-any.whl
ls el7_env/
'''

## Development environment

In order to test your application and all dependencies are well declared, you have to create a virtual env

```bash
$ python3.6 -m venv linux_venv
$ source linux_venv/bin/activate
```

### Build

We are using `setuptools` as software build tool. In order to build this project, you have to run:

```bash
$ python setup.py build
```

### Local Installation

```bash
$ python setup.py install
```

### Clean

Both setuptools and distutils commands are extended to ensure that all cache files are cleaned. Indeed python generate `*.pyc`, 
`*.pyo` file to store corresponding bytecode. These bytecode files are not always regenerated which could lead to some
problems when working on a cross-environment (Windows <-> Linux). The extended clean command remove either `__pycache__`, `*.egg-info`, `.eggs`, `.pytest_cache`


## Continuous Integration

Continuous Integration (CI) is enabled by default, you have nothing to do.
After each commit you can download (by clicking `Download` a list menu appear):

  - Reports: `Download 'test_python'`
  - Python:  `Download 'python_wheel'`

## Conclusion

Happy coding :-)
