FROM eclipse-temurin:17-jdk-jammy

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl bash \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://github.com/sbt/sbt/releases/download/v1.10.1/sbt-1.10.1.tgz \
      | tar -xz -C /opt \
    && ln -s /opt/sbt/bin/sbt /usr/local/bin/sbt

ENV SBTOPTS="-Xmx2g -Dsbt.supershell=false"

WORKDIR /work
CMD ["bash", "-c", "sbt -batch package && chown -R \"${BUILD_UID:-1000}:${BUILD_GID:-1000}\" /work"]
