#!/usr/bin/env bash
declare -r prefix=$(readlink -f "$1")
[[ ! -e USeq_9.2.0.zip ]] && curl -LO https://github.com/HuntsmanCancerInstitute/USeq/releases/download/USeq_9.2.0/USeq_9.2.0.zip
[[ ! -e USeq_9.2.0 ]] && unzip USeq_9.2.0.zip
mkdir -p "${prefix}/share/useq/"
for filepath in USeq_9.2.0/Apps/[A-Z]*; do 
  filename=$(basename "${filepath}")
  echo "#!/usr/bin/env bash
java -jar '${prefix}/share/useq/${filename}' \"\$*\" " > "${prefix}/bin/${filename}"
  chmod +x "${prefix}/bin/${filename}"
  install -m 644 "${filepath}" "${prefix}/share/useq/${filename}";
done
