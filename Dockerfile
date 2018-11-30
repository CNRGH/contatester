FROM registry.cnrgh.fr/images/sources/python-36-centos7:latest
ARG ARCHIVE_FILE
# tests and data_example directoryare intentionally ommited
ADD ${ARCHIVE_FILE} ./
RUN mkdir /tmp \
    && pip3 install --upgrade pip wheel setuptools \
    && python3 setup.py bdist_wheel install \
    && python3 setup.py clean

ENTRYPOINT [ 'contatester' ]
