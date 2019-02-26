FROM registry.cnrgh.fr/images/sources/ibfj-bioinfo-analysis-r:latest
ENV R_LIBS="$(pwd)/rlib:/ur/lib64/Rlibrary"
ARG CONTATESTER_VERSION
ARG USEQ_VERSION
ARG ARCHIVE_FILE
# tests and data_example directoryare intentionally ommited
ADD ${ARCHIVE_FILE} ./
RUN mkdir -p /tmp \
    && pip3 install --upgrade pip wheel setuptools \
    && pip3 install contatester-${CONTATESTER_VERSION}-py2.py3-none-any.whl \
    && ./install_useq.sh /usr/local/ ${USEQ_VERSION} \
    && rm USeq_${USEQ_VERSION}.zip \
    && rm -fr USeq_${USEQ_VERSION}

ENTRYPOINT [ 'contatester' ]
