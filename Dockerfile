FROM ubuntu:16.04

# The default source archive.ubuntu.com is busy and slow. We use the following source makes docker build running faster.
RUN echo '\n\
deb http://us.archive.ubuntu.com/ubuntu/ xenial main restricted universe multiverse \n\
deb http://us.archive.ubuntu.com/ubuntu/ xenial-security main restricted universe multiverse \n\
deb http://us.archive.ubuntu.com/ubuntu/ xenial-updates main restricted universe multiverse \n\
deb http://us.archive.ubuntu.com/ubuntu/ xenial-proposed main restricted universe multiverse \n\
deb http://us.archive.ubuntu.com/ubuntu/ xenial-backports main restricted universe multiverse \n\
' > /etc/apt/sources.list

# Install wget, curl, unzip, bzip2, git.
COPY scripts/docker/install-download-tools.bash /
RUN /install-download-tools.bash

# MySQL server and client
COPY scripts/docker/install-mysql.bash /
RUN /install-mysql.bash
COPY doc/datasets/popularize_churn.sql \
     doc/datasets/popularize_iris.sql \
     doc/datasets/popularize_boston.sql \
     doc/datasets/popularize_creditcardfraud.sql \
     doc/datasets/create_model_db.sql \
     /docker-entrypoint-initdb.d/
VOLUME /var/lib/mysql

# Install protobuf and protoc
COPY scripts/docker/install-protobuf.bash /
RUN /install-protobuf.bash

# Need Java SDK to build remote parsers.
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
COPY scripts/docker/install-java.bash /
RUN /install-java.bash

# Using the stable version of Hadoop
ENV HADOOP_VERSION 3.2.1
ENV PATH /opt/hadoop-${HADOOP_VERSION}/bin:/miniconda/envs/sqlflow-dev/bin:/miniconda/bin:/usr/local/go/bin:/go/bin:$PATH
COPY scripts/docker/install-hadoop.bash /
RUN /install-hadoop.bash

# Miniconda, Python 3.6, TensorFlow 2.0.0, etc
COPY scripts/docker/install-python.bash /
RUN /install-python.bash

# Go, goyacc, protoc-gen-go, and other Go tools
ENV GOPATH /root/go
ENV PATH /usr/local/go/bin:$GOPATH/bin:$PATH
COPY scripts/docker/install-go.bash /
RUN /install-go.bash

# ODPS
COPY scripts/docker/install-odps.bash /
RUN /install-odps.bash

# ElasticDL and kubectl
COPY scripts/docker/install-elasticdl.bash /
RUN /install-elasticdl.bash

# The SQLFlow magic command for Jupyter.
ENV IPYTHON_STARTUP /root/.ipython/profile_default/startup/
COPY scripts/docker/install-jupyter.bash /
RUN /install-jupyter.bash

# -----------------------------------------------------------------------------------
# Above Steps Should be Cached for Each CI Build if Dockerfile is not Changed.
# -----------------------------------------------------------------------------------

# Build SQLFlow, copy sqlflow_submitter, install Java parser (129 MB), convert tutorial markdown to ipython notebook
COPY . $GOPATH/src/sqlflow.org/sqlflow
RUN cd $GOPATH/src/sqlflow.org/sqlflow && \
go generate ./... && \
go install -v ./... && \
mv $GOPATH/bin/sqlflowserver /usr/local/bin && \
mv $GOPATH/bin/repl /usr/local/bin && \
cp -r $GOPATH/src/sqlflow.org/sqlflow/python/sqlflow_submitter /miniconda/envs/sqlflow-dev/lib/python3.6/site-packages/ && \
cd java/parser && \
mvn clean compile assembly:single && \
mkdir -p /opt/sqlflow/parser && \
cp target/parser-1.0-SNAPSHOT-jar-with-dependencies.jar /opt/sqlflow/parser && \
cd / && \
bash ${GOPATH}/src/sqlflow.org/sqlflow/scripts/convert_markdown_into_ipynb.sh && \
rm -rf ${GOPATH}/src && rm -rf ${GOPATH}/bin

ARG WITH_SQLFLOW_MODELS="ON"
# Install latest sqlflow_models for testing custom models, see main_test.go:CaseTrainCustomModel
# NOTE: The sqlflow_models works well on the specific Tensorflow version,
#       we can skip installing sqlflow_models if using the older Tensorflow.
RUN if [ "${WITH_SQLFLOW_MODELS:-ON}" = "ON" ]; then \
  git clone https://github.com/sql-machine-learning/models.git && \
  cd models && \
  git checkout 58f4c137129e2bc749320bafcc8fddb7c737fed9 && \
  bash -c "source activate sqlflow-dev && python setup.py install" && \
  cd .. && \
  rm -rf models; \
fi

ADD scripts/start.sh /
CMD ["bash", "/start.sh"]
