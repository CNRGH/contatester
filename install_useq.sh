#!/usr/bin/env bash

err_report() {
  echo "Error on line $1"
}

trap 'err_report $LINENO' ERR


declare -r USEQ_VERSION=$( (($# >=2)) && echo "$2" || echo '9.0.7')
declare -r PREFIX=$(readlink -f "$1")
declare -r EXEC_DIR="${PREFIX}/bin/"
declare -r TOOL_DIR="${PREFIX}/share/useq/ToolJars"
declare -r LIB_DIR="${PREFIX}/share/useq/LibraryJars"


wrapper_creator(){
  local filepath="$1"
  local filename=$(basename "${filepath}")
  echo "#!/usr/bin/env bash
java -jar '${TOOL_DIR}/${filename}' \$*" > "${PREFIX}/bin/${filename}"
  chmod +x "${PREFIX}/bin/${filename}"
  install -m 0644 "${filepath}" "${TOOL_DIR}/";

}


get_useq_binaries(){
  if [[ ! -e "USeq_${USEQ_VERSION}" ]]; then
    if [[ ! -e USeq_${USEQ_VERSION}.zip ]]; then
      curl -LO "https://github.com/HuntsmanCancerInstitute/USeq/releases/download/USeq_${USEQ_VERSION}/USeq_${USEQ_VERSION}.zip"
    fi
    unzip "USeq_${USEQ_VERSION}.zip" 
  fi
}


get_useq_binaries

mkdir -p "${EXEC_DIR}" "${TOOL_DIR}" "${LIB_DIR}"

install -m 0644 "USeq_${USEQ_VERSION}"/LibraryJars/bioToolsCodeLibrary.jar "${LIB_DIR}"

for filepath in "USeq_${USEQ_VERSION}"/Apps/[A-Z]*; do 
  wrapper_creator "${filepath}"
done
