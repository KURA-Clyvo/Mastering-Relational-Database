FROM gvenzl/oracle-xe:latest

ENV ORACLE_PASSWORD=060506

COPY src/kura_schema_v4.sql /container-entrypoint-initdb.d/kura_schema_v4.sql

RUN adduser -h /home/appuser -s /bin/bash -D appuser

USER appuser

EXPOSE 1521