FROM registry.cnrgh.fr/images/sources/ibfj-bioinfo-analysis-r:latest
ENV R_LIBS="/usr/local/lib64:/usr/lib64/Rlibrary"
ENV PMC_VERSION="4.8.2"
ARG CONTATESTER_VERSION
COPY dist/contatester-${CONTATESTER_VERSION}-py2.py3-none-any.whl /dist/
COPY rlib /usr/local/lib64/
# COPY --from=builder /data/rlib/* /usr/local/lib64/
# COPY --from=builder /data/dist/dist/contatester-${CONTATESTER_VERSION}-py2.py3-none-any.whl /contatester-${CONTATESTER_VERSION}-py2.py3-none-any.whl
# tests and data_example directory are intentionally ommited
RUN curl -LO https://repo.ius.io/ius-release-el7.rpm \
    && yum update -y ius-release-el7.rpm \
    && yum install -y libcurl openssl curl ant openmpi-devel cppcheck numactl-devel graphviz \
    && yum group install -y "Development Tools" \
    && export PATH=$PATH:/usr/lib64/openmpi/bin/ \
    && mkdir -p /bin \
    && which mpiexec \
    && which mpirun \
    && echo -e '#!/bin/bash\n/usr/lib64/openmpi/bin/mpiexec --allow-run-as-root "$@"' > /bin/mpiexec \
    && echo -e '#!/bin/bash\n/usr/lib64/openmpi/bin/mpirun --allow-run-as-root "$@"' > /bin/mpirun \
    && chmod u+x /bin/mpiexec \
    && chmod u+x /bin/mpirun \
    && which mpiexec \
    && which mpirun \
    && curl -LO https://github.com/pegasus-isi/pegasus/archive/${PMC_VERSION}.tar.gz \
    && tar -xf ${PMC_VERSION}.tar.gz \
    && pushd pegasus-${PMC_VERSION}/src/tools/pegasus-mpi-cluster \
    && make \
    && make install \
    && popd \
    && pegasus-mpi-cluster --version \
    && pip3 install --upgrade pip wheel setuptools \
    && pip3 install dist/contatester-${CONTATESTER_VERSION}-py2.py3-none-any.whl \
    && yum clean all \
    && rm -fr dist
ENTRYPOINT ["contatester"]