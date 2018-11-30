FROM registry.cnrgh.fr/images/sources/python-36-centos7:latest

COPY . .
RUN pip3 install --upgrade pip wheel setuptools
RUN cd contatester \
    && ls -lh src/\
    && python3 setup.py bdist_wheel install \
    && python3 setup.py clean
RUN ls /opt/app-root/bin
RUN type contatester

ENTRYPOINT [ 'contatester' ]
