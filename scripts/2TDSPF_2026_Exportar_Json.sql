-- #############################################################################
-- #  KURA - Sprint 4 / Database - Entregavel 3: exportacao do dataset em JSON
-- #
-- #  O QUE FAZ
-- #    Chama PKG_COBRANCA.exportar_todas (o JSON e gerado PELO PACKAGE, nunca
-- #    montado ou editado a mao) e grava o CLOB em
-- #    data/2TDSPF_2026_Dataset_Cobrancas.json: um array JSON, um elemento por
-- #    linha, so cobrancas ativas, UTF-8, sem BOM, sem cabecalho/eco/feedback.
-- #    Esse arquivo e a entrada do mongoimport --jsonArray (entregavel 4).
-- #
-- #  PRE-REQUISITO
-- #    Packages instalados no schema da conexao (src/2TDSPF_2026_Packages_
-- #    Integrantes.sql) e VALID. O cliente precisa de NLS_LANG com charset
-- #    UTF-8 (ex.: .AL32UTF8), senao o acento sai errado.
-- #
-- #  CONEXAO (DE PROPOSITO, NAO HA CONNECT NEM SENHA AQUI)
-- #    O repositorio e publico: o script usa a conexao JA ABERTA pelo sqlplus.
-- #    Abra-a na linha de comando (a senha fica so no seu terminal) ou no
-- #    SQL Developer (conexao do schema do grupo) e rode o script nela.
-- #
-- #  COMO RODAR (a partir da RAIZ do repositorio, pois o SPOOL e relativo):
-- #    sqlplus USUARIO@//host:porta/servico @scripts/2TDSPF_2026_Exportar_Json.sql
-- #      (o sqlplus pede a senha; na FIAP, o mesmo usuario/servico das demais
-- #       entregas)
-- #    Em Docker (a pasta data/ precisa existir no diretorio de trabalho):
-- #      docker exec -w /tmp/s4 <container> sqlplus -s USUARIO/SENHA@localhost/XEPDB1 \
-- #          @scripts/2TDSPF_2026_Exportar_Json.sql
-- #    No SQL Developer: abrir a pasta do repo como diretorio de trabalho e
-- #      executar com "Executar script" (F5); o SET TERMOUT nao tem efeito la.
-- #
-- #  ATENCAO
-- #    exportar_todas devolve as cobrancas de TODAS as clinicas. Por isso ela e
-- #    de uso exclusivo desta exportacao e NUNCA e exposta pela API (vazaria
-- #    dado entre clinicas). A aplicacao chama so listar_json/relatorio_json,
-- #    sempre com a clinica do usuario autenticado.
-- #    Os dados exportados sao a carga FICTICIA da Sprint 3 (nenhum dado real).
-- #    As datas da carga sao relativas a SYSDATE: o conteudo muda se a carga for
-- #    refeita em outro dia; o arquivo versionado e o retrato de uma execucao.
-- #############################################################################
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE
SET ECHO OFF VERIFY OFF FEEDBACK OFF HEADING OFF PAGESIZE 0 TAB OFF
SET LONG 2000000000 LONGCHUNKSIZE 32767 LINESIZE 32767 TRIMSPOOL ON TRIMOUT ON
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED

VARIABLE v_json CLOB
-- Fora do SPOOL: se o package faltar/estiver invalido, o erro aparece no
-- terminal/log e o script sai com codigo diferente de 0, sem criar arquivo.
EXEC PKG_COBRANCA.exportar_todas(:v_json)

SPOOL data/2TDSPF_2026_Dataset_Cobrancas.json
SET TERMOUT OFF
-- Imprime o CLOB linha a linha (DBMS_OUTPUT). O PRINT do SQL*Plus acrescentava
-- linhas em branco no fim; assim o arquivo termina em "]" + 1 quebra de linha.
-- Cada elemento ja vem em sua propria linha (CHR(10)) do package.
DECLARE
    v_pos PLS_INTEGER := 1;
    v_nxt PLS_INTEGER;
    v_tam PLS_INTEGER := DBMS_LOB.GETLENGTH(:v_json);
BEGIN
    WHILE v_pos <= v_tam LOOP
        v_nxt := DBMS_LOB.INSTR(:v_json, CHR(10), v_pos);
        IF v_nxt = 0 THEN v_nxt := v_tam + 1; END IF;
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(:v_json, v_nxt - v_pos, v_pos));
        v_pos := v_nxt + 1;
    END LOOP;
END;
/
SET TERMOUT ON
SPOOL OFF
EXIT
