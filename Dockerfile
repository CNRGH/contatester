FROM registry.cnrgh.fr/images/sources/ibfj-bioinfo-analysis-r:latest
ENV R_LIBS="/usr/local/lib64:/ur/lib64/Rlibrary"
ARG CONTATESTER_VERSION
ARG ARCHIVE_FILE
# tests and data_example directoryare intentionally ommited
ADD ${ARCHIVE_FILE} ./
RUN mkdir -p /tmp /usr/local/lib64 \
    && mv rlib/* /usr/local/lib64 \
    && yum install -y libcurl openssl \
    && pip3 install --upgrade pip wheel setuptools \
    && pip3 install dist/contatester-${CONTATESTER_VERSION}-py2.py3-none-any.whl \
    && yum clean all \
    && rm -fr rlib

ENTRYPOINT [ 'contatester' ]
