import itertools
from os import path

import os
import shutil
import subprocess
from distutils.command.clean import clean
from glob import glob
from typing import List

from pkg_resources.extern import packaging
from setuptools import setup, find_packages, Command

NAME = 'contatester'
VERSION = '1.0.0'
DESCRIPTION = 'Detect human contamination for whole genome non-tumorous human' \
              ' sequencing.'
KEYWORDS = 'contamination, vcf, allelic balance, Whole Genome'


def get_files(directory: str) -> str:
    return glob(path.join(directory, '*'))


class ExtendedClean(clean):
    """
    This class extend clean command in order to remove all __pycache__ directories.
    Indeed these directories contains pre-computed file with module path write in
    unix or windows style. Depends of latest os which build the file.
    In multi-OS environment this could lead to strange behavior.
    """

    @staticmethod
    def _find_all_directories(dir_name: str, path: str) -> List[str]:
        result = []
        for root, dirs, files in os.walk(path):
            if dir_name in dirs:
                result.append(os.path.join(root, dir_name))
        return result

    def run(self) -> None:
        clean.run(self)
        c = clean(self.distribution)
        c.finalize_options()
        c.run()
        # sources directories
        for directory in self.distribution.package_dir.values():
            for file_path in self._find_all_directories('__pycache__', directory):
                shutil.rmtree(file_path)
            for file_path in self._find_all_directories(self.distribution.metadata.name+'.egg-info', directory):
                shutil.rmtree(file_path)
        # tests directory
        if os.path.exists('tests'):
            for file_path in self._find_all_directories('__pycache__', 'tests'):
                shutil.rmtree(file_path)
        if os.path.exists('.coverage'):
            os.remove('.coverage')
        if os.path.exists('htmlcov'):
            shutil.rmtree('htmlcov')
        if os.path.exists('.eggs'):
            shutil.rmtree('.eggs')
        if os.path.exists('.pytest_cache'):
            shutil.rmtree('.pytest_cache')


class Coverage(Command):
    description = 'generate report'

    user_options = [
        ('source=', 's', 'source directory')
    ]

    @staticmethod
    def evaluate_marker(text, extra=None):
        """
        Evaluate a PEP 508 environment marker.
        Return a boolean indicating the marker result in this environment.
        Raise SyntaxError if marker is invalid.

        This implementation uses the 'pyparsing' module.
        """
        try:
            marker = packaging.markers.Marker(text)
            return marker.evaluate()
        except packaging.markers.InvalidMarker as e:
            raise SyntaxError(e)

    @staticmethod
    def install_dists(dist):
        """
        Install the requirements indicated by self.distribution and
        return an iterable of the dists that were built.
        """
        ir_d = dist.fetch_build_eggs(dist.install_requires)
        tr_d = dist.fetch_build_eggs(dist.tests_require or [])
        er_d = dist.fetch_build_eggs(
                v for k, v in dist.extras_require.items()
                if k.startswith(':') and Coverage.evaluate_marker(k[1:])
        )
        return itertools.chain(ir_d, tr_d, er_d)

    def initialize_options(self):
        self.sources = None

    def finalize_options(self):
        if self.sources is None:
            self.sources = ['--source={dir}'.format(dir=directory) for directory in
                            self.distribution.package_dir.values()]

    def run(self) -> None:
        installed_dists = self.install_dists(self.distribution)
        subprocess.call(['coverage', 'run'] + self.sources + ['setup.py', 'test'])
        subprocess.call(['coverage', 'report'])
        subprocess.call(['coverage', 'html'])


if __name__ == '__main__':
    setup(
        name=NAME,
        version=VERSION,
        description=DESCRIPTION,
        author='CEA / CNRGH / LBI',
        author_email='bioinfo@cng.fr',
        license='CeCILL',
        classifiers=[
            'Development Status :: 5 - Production/Stable',
            'Intended Audience :: Developers',
            'License :: CeCILL Free Software License Agreement (CeCILL)',
            'Programming Language :: Python :: 3.6'
        ],
        keywords='foo, bar',
        cmdclass={'clean': ExtendedClean, 'coverage': Coverage},
        packages=find_packages('src'),
        package_dir={'': 'src'},
        include_package_data=True,
        data_files=[('share/{}/'.format(NAME), get_files('data'))],
        scripts=get_files('scripts'),
        install_requires=['wheel >= 0.31.0'],
        setup_requires=['pytest-runner', 'setuptools >= 40.0.0 '],
        tests_require=['pytest  >= 3.4.0',
                       'pytest-dependency >= 0.3.0',
                       'pytest-mock >= 1.10.0',
                       'coverage >= 4.5.1'],
        entry_points={
            'console_scripts': [
                'contatester = fr.cea.lbi.contatester.__main__:main'
            ]
        },
        extras_require={}
    )
