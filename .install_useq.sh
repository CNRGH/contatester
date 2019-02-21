#!/usr/bin/env bash
declare -r prefix=$(readlink -f "$1")
[[ ! -e USeq_9.2.0.zip ]] && curl -LO https://github.com/HuntsmanCancerInstitute/USeq/releases/download/USeq_9.2.0/USeq_9.2.0.zip
[[ ! -e USeq_9.2.0 ]] && unzip USeq_9.2.0.zip
for filepath in USeq_9.2.0/Apps/[A-Z]*; do 
  filename=$(basename "${filepath}")
  install -m 0755 "${filepath}" "${prefix}/bin/${filename}";
done
