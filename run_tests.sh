#!/usr/bin/env bash
declare TESTING_ENV_IS_ACTIVATE=false
declare PYTHON_TEST_ENV_NAME='testing'

cleanup(){
  if ${TESTING_ENV_IS_ACTIVATE};then
    deactivate
  fi
  if [[ -d "${PYTHON_TEST_ENV_NAME}" ]]; then
    rm -fr "${PYTHON_TEST_ENV_NAME}"
  fi
}


err_report() {
  echo "Error on ${BASH_SOURCE} line $1" >&2
  exit 1
}


trap 'err_report $LINENO' ERR
trap cleanup INT TERM


display_banner(){
  local -i i=0
  local line=''
  while read line; do 
    ((i++));
    echo -e "$line"
  done < banner.ansi
}

init_env(){
  python3 -m venv "${PYTHON_TEST_ENV_NAME}"
  TESTING_ENV_IS_ACTIVATE=true
  source testing_env/bin/activate
  pip3 install --upgrade pip wheel setuptools
}

declare -r CONTATESTER_VERSION=$(grep -Po "(?<=VERSION = ')[\d\.]+" setup.py)
display_banner

echo -e '\033[31m- Create a python evironnment for testing scripts\033[0m'
init_env

echo -e '\033[31m- Run python tests\033[0m'
python3 setup.py test

echo -e '\033[31m- Testing scripts\033[0m'
pip3 install dist/contatester-"${CONTATESTER_VERSION}"-py2.py3-none-any.whl

echo -e '\033[34m\t- Testing calculAllelicBalance\033[0m'
calculAllelicBalance.sh -f ./data_examples/test_1.vcf.gz > ./data_examples/calculAllelicBalance_output.hist

echo -e '\033[34m\t- Testing contaReport\033[0m'
contaReport.R --input ./data_examples/distrib_allele_balance.hist \
              --output ./data_examples/distrib_allele_balance.conta \
              --report \
              --reportName \
              ./data_examples/distrib_allele_balance.pdf

echo -e '\033[34m\t- Testing recupConta\033[0m'
recupConta.sh -f ./data_examples/test_1.vcf.gz \
              -c ./data_examples/test_1_AB_0.01_to_0.12_noLCRnoDUP.vcf \
              -b ./data_examples/test_1_AB_0.01_to_0.12_noLCRnoDUP.bed

echo -e '\033[34m\t- Testing checkContaminant\033[0m'
checkContaminant.sh -f ./data_examples/test_2.vcf.gz \
                    -b ./data_examples/test_1_AB_0.01_to_0.12_noLCRnoDUP.bed \
                    -c ./data_examples/test_1_AB_0.01_to_0.12_noLCRnoDUP.vcf \
                    -s ./data_examples/test_1_comparisonSummary.txt \
                    -o ./data_examples/

