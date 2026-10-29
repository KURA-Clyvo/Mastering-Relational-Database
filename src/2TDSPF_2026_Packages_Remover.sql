-- #############################################################################
-- #  2TDSPF_2026_Packages_Remover.sql
-- #  KURA - Sistema de Gestao de Continuidade Veterinaria (Clyvo Vet)
-- #  FIAP Challenge 2026 - Sprint 4 - Mastering Relational and Non-Relational Database
-- #############################################################################
-- #
-- #  INTEGRANTES (ordem alfabetica pelo primeiro nome):
-- #    - Clayton Alves dos Santos................... RM562285
-- #    - Felipe Ferrete Soares Lemes ............... RM562999
-- #    - Guilherme Sola Guarcia..................... RM563674
-- #    - Gustavo Bosak Santos....................... RM566315
-- #    - Nikolas Henrique de Souza Lemes Brisola ... RM564371
-- #
-- #############################################################################
-- #  SAIDA DE EMERGENCIA (task S4-DB-03)
-- #
-- #  Remove SO CODIGO: a trigger TRG_AUDITORIA_COBRANCA e os 4 packages
-- #  (PKG_AUDITORIA, PKG_COBRANCA, PKG_TRIAGEM, PKG_KURA_LOG), nesta ordem - a
-- #  TRIGGER PRIMEIRO, para que o lancamento de cobranca da aplicacao volte a
-- #  funcionar mesmo que um package esteja quebrado (trigger apontando para package
-- #  ausente/invalido faz todo INSERT em COBRANCA falhar com ORA-04098/ORA-04063).
-- #
-- #  NAO toca tabela, sequence nem dado: COBRANCA, SERVICO_PRECO, LOG_ERRO,
-- #  AUDITORIA_COBRANCA e suas sequences ficam exatamente como estao (a trilha de
-- #  auditoria ja gravada e preservada). O custo de remover a trigger e que novas
-- #  operacoes em COBRANCA deixam de ser auditadas ate reinstalar o arquivo
-- #  2TDSPF_2026_Packages_Integrantes.sql.
-- #
-- #  Idempotente: pode rodar varias vezes; objeto que nao existe (ORA-04043,
-- #  ORA-04080) e ignorado; qualquer outro erro e propagado e encerra o script.
-- #  Termina listando o que sobrou de codigo. Nenhuma credencial neste arquivo.
-- #############################################################################

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET VERIFY OFF
SET FEEDBACK ON
SET LINESIZE 200
SET PAGESIZE 100
SET TRIMSPOOL ON
SET TAB OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT
PROMPT === Remocao da trigger e dos packages (so codigo; nenhuma tabela/sequence e tocada) ===
DECLARE
    PROCEDURE remove (p_tipo IN VARCHAR2, p_nome IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'DROP ' || p_tipo || ' ' || p_nome;
        DBMS_OUTPUT.PUT_LINE('removido: ' || p_tipo || ' ' || p_nome);
    EXCEPTION
        WHEN OTHERS THEN
            -- 04043 = objeto inexistente; 04080 = trigger inexistente
            IF SQLCODE IN (-4043, -4080) THEN
                DBMS_OUTPUT.PUT_LINE('ja nao existia: ' || p_tipo || ' ' || p_nome);
            ELSE
                RAISE;
            END IF;
    END remove;
BEGIN
    remove('TRIGGER', 'TRG_AUDITORIA_COBRANCA');   -- 1o: a aplicacao nao depende mais de package
    remove('PACKAGE', 'PKG_AUDITORIA');
    remove('PACKAGE', 'PKG_COBRANCA');
    remove('PACKAGE', 'PKG_TRIAGEM');
    remove('PACKAGE', 'PKG_KURA_LOG');
END;
/

PROMPT
PROMPT === Codigo PL/SQL que sobrou neste schema (esperado: nenhum dos 5 acima) ===
SELECT object_type || ' ' || object_name || ' ' || status AS sobrou
  FROM user_objects
 WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'FUNCTION', 'PROCEDURE')
 ORDER BY object_type, object_name;

PROMPT
PROMPT === Tabelas/sequences NAO foram tocadas (apenas contagem informativa) ===
SELECT 'objetos de dados: ' || COUNT(CASE WHEN object_type = 'TABLE' THEN 1 END) || ' tabela(s), '
       || COUNT(CASE WHEN object_type = 'SEQUENCE' THEN 1 END) || ' sequence(s)' AS dados
  FROM user_objects
 WHERE object_type IN ('TABLE', 'SEQUENCE');

PROMPT
PROMPT === FIM DO ARQUIVO 2TDSPF_2026_Packages_Remover.sql ===
