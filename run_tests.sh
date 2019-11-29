#!/usr/bin/env bash
declare TESTING_ENV_IS_ACTIVATE=false
declare PYTHON_TEST_ENV_NAME=''
PYTHON_TEST_ENV_NAME=$(mktemp -d $TMPDIR/contatester.XXXX)
readonly PYTHON_TEST_ENV_NAME
declare PYTHON_WHEEL_FOLDER='dist'

cleanup(){
  if ${TESTING_ENV_IS_ACTIVATE};then
    deactivate
  fi
  if [[ -d "${PYTHON_TEST_ENV_NAME}" ]]; then
    rm -fr "${PYTHON_TEST_ENV_NAME}"
  fi
  if [[ -d "${PYTHON_WHEEL_FOLDER}" ]]; then
    rm -fr "${PYTHON_WHEEL_FOLDER}"
  fi
}


err_report() {
  echo "Error on ${BASH_SOURCE[0]} line $1" >&2
  exit 1
}


trap 'err_report $LINENO' ERR
trap cleanup INT TERM

module_load() {
      # Used to load programs with module load function
      if [[ -n "${IG_MODULESHOME}" ]]; then
        module load "$@"
      else
        local dep_name=""
        local dep_version=""
        local is_present=false
        for dependency in "$@"; do
          dep_name="${dependency%/*}"
          dep_version="${dependency#*/}"
          if [[ "${dep_name}" == 'r' ]]; then
            dep_name='R'
          fi
          is_present=$(command -v "${dep_name}" &> /dev/null && echo true || echo false)
          if ! "${is_present}"; then
            echo "ERROR: Missing tools: ${dep_name}" >&2
            exit 1
          #elif [[ -n "${dep_version}" ]]; then
          #  echo 'TODO'
          fi
        done
      fi
    return 0
}

############################# MAIN #############################
declare CONTATESTER_VERSION=0
CONTATESTER_VERSION="$(grep -Po "(?<=version     = )[\d\.]+" setup.cfg)"
readonly CONTATESTER_VERSION

display_banner(){
  local -i i=0
  local line=''
  while read line; do 
    ((i++));
    echo -e "$line"
  done < banner.ansi
}

init_env(){
  module_load python/3.6.5
  python3 -m venv "${PYTHON_TEST_ENV_NAME}"
  TESTING_ENV_IS_ACTIVATE=true
  source "${PYTHON_TEST_ENV_NAME}"/bin/activate
  pip3 install --upgrade pip wheel setuptools
}

install_contatester(){
  local -r wheel_file=dist/contatester-"${CONTATESTER_VERSION}"-py2.py3-none-any.whl
  python3 setup.py clean
  if [[ ! -e "${wheel_file}" ]]; then
    python3 setup.py bdist_wheel
  fi 
  pip3 install "${wheel_file}"
}

display_banner

python3 setup.py clean
rm dist testing build -rf

echo -e '\033[31m- tmpdir : '"$PYTHON_TEST_ENV_NAME"'\033[0m'

echo -e '\033[31m- Create a python evironnment for testing scripts\033[0m'
init_env

echo -e '\033[31m- Run python tests\033[0m'
python3 setup.py test

echo -e '\033[31m- Testing install\033[0m'
install_contatester

echo -e '\033[31m- Testing scripts\033[0m'
contatester -h

echo -e '\033[34m\t- Testing calculAllelicBalance\033[0m'
calculAllelicBalance.sh -f ./data_examples/test_1.vcf.gz \
                        -o ./data_examples/calculAllelicBalance_output.hist
                        -d ./data_examples/calculAllelicBalance_output.meandepth
                        
echo -e '\033[34m\t- Testing contaReport\033[0m'
module_load r
contaReport.R --input ./data_examples/distrib_allele_balance.hist \
              --output ./data_examples/distrib_allele_balance.conta \
              --report \
              --depth 30 \
              --experiment WG \
              --reportName \
              ./data_examples/distrib_allele_balance.pdf

echo -e '\033[34m\t- Testing recupConta\033[0m'
recupConta.sh -f ./data_examples/test_1.vcf.gz \
              -c ./data_examples/test_1_AB_0.00_to_0.11_noLCRnoDUP.vcf.gz

echo -e '\033[34m\t- Testing checkContaminant\033[0m'
checkContaminant.sh -f ./data_examples/test_2.vcf.gz \
                    -c ./data_examples/test_1_AB_0.00_to_0.11_noLCRnoDUP.vcf.gz \
                    -s ./data_examples/test_1_comparisonSummary.txt

