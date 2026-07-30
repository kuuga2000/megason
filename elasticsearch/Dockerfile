ARG ELASTICSEARCH_VERSION=7.16
FROM eclipse-temurin:17-jre AS current_jre

FROM docker.elastic.co/elasticsearch/elasticsearch:${ELASTICSEARCH_VERSION}

USER root
RUN rm -rf /usr/share/elasticsearch/jdk
COPY --from=current_jre --chown=elasticsearch:root /opt/java/openjdk /usr/share/elasticsearch/jdk
USER elasticsearch
