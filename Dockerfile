FROM gvenzl/oracle-xe:latest

ENV ORACLE_PASSWORD=060506

COPY src/kura_schema_v5.sql /container-entrypoint-initdb.d/kura_schema_v5.sql

EXPOSE 1521