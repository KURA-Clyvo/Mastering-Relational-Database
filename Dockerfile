FROM gvenzl/oracle-xe:latest

ENV ORACLE_PASSWORD=060506

COPY kura_schema_v4.sql /container-entrypoint-initdb.d/kura_schema_v4.sql

EXPOSE 1521