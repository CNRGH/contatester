FROM registry.cnrgh.fr/images/sources/python-36-centos7:latest

COPY . .

RUN cd contatester \
    && python3 setup.py install \
    && python3 setup.py clean

CMD [ "contatester" ]
