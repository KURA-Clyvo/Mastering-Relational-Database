-- #############################################################################
-- #  2TDSPF_2026_Packages_Integrantes.sql
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
-- #  ESCOPO DESTE ARQUIVO (tasks S4-DB-02 e S4-DB-03)
-- #
-- #  Evolui a Sprint 3: troca as funcoes/procedimentos standalone por quatro
-- #  packages, troca a trigger de auditoria por uma trigger FINA que delega a um
-- #  package, e cria a ESTRUTURA da trilha de auditoria (tabela, sequence e
-- #  indices). NAO recria tabelas de negocio.
-- #
-- #    BLOCO 0  - Cabecalho, sessao e PRE-REQUISITO (verificado: o script PARA)
-- #    BLOCO 1  - Limpeza da FN_CALCULAR_SCORE_URGENCIA standalone (idempotente)
-- #    BLOCO 2  - AUDITORIA_COBRANCA + sequence + indices (se nao existirem)
-- #    BLOCO 3  - PKG_KURA_LOG   (log em transacao autonoma)
-- #    BLOCO 4  - PKG_TRIAGEM    (score de urgencia, porte 1:1 da Sprint 3)
-- #    BLOCO 5  - PKG_COBRANCA   (JSON e relatorio de cobranca)
-- #    BLOCO 6  - PKG_AUDITORIA  (grava a trilha; mesma transacao do DML)
-- #    BLOCO 7  - TRG_AUDITORIA_COBRANCA fina (CREATE OR REPLACE, mesmo nome)
-- #    BLOCO 8  - Verificacao: recompila e confere TODOS os dependentes (PARA)
-- #    BLOCO 9  - Remove as standalone da Sprint 3 (so depois do BLOCO 8)
-- #    DEMO 02  - confere (OK/FALHOU) log e triagem
-- #    DEMO 03  - confere (OK/FALHOU) cobranca e auditoria; desfaz todo o DML
-- #    BLOCO 8  - repetido no fim do arquivo
-- #
-- #  ORDEM SEM JANELA (de proposito): os packages e a trigger entram por
-- #  CREATE OR REPLACE (nunca por DROP), a verificacao do BLOCO 8 vem ANTES de
-- #  qualquer remocao, e so entao as standalone da Sprint 3 saem. Se o script
-- #  parar em qualquer ponto antes do BLOCO 9, a trigger continua apontando para
-- #  codigo que existe. NAO ha DROP de package nem de trigger neste arquivo.
-- #
-- #  PRE-REQUISITO: o schema ja deve ter as tabelas da Sprint 3 (script
-- #  2TDSPF_2026_CodigoSql_Integrantes.sql) ou o equivalente via Flyway. O
-- #  BLOCO 0 confere por nome e aborta se faltar alguma das 5 tabelas usadas.
-- #
-- #  *** NAO destrutivo ***: este arquivo nao apaga dado, tabela nem sequence.
-- #  Os unicos DROP sao os das standalone da Sprint 3 (BLOCOS 1 e 9). Ele pode
-- #  ser executado varias vezes seguidas sobre o mesmo schema. A demonstracao
-- #  desfaz (ROLLBACK) todo o DML que faz em COBRANCA e SERVICO_PRECO; as unicas
-- #  linhas que ela deixa sao as de LOG_ERRO (log autonomo, sinteticas, sem dado
-- #  pessoal) - e as sequences consomem alguns valores (ids com "buracos").
-- #
-- #  *** CODIGO DE SAIDA ***: o sqlplus sai com SQLCODE modulo 256 (medido).
-- #  Codigos proprios deste arquivo: ORA-20900 -> 164 (pre-requisito),
-- #  ORA-20901 -> 165 (invalido/erro de compilacao), ORA-20902 -> 166 (demo com
-- #  FALHOU). Todo erro cujo codigo e MULTIPLO DE 256 sai com 0 (ex.: ORA-20224,
-- #  e tambem ORA-01536, quota de espaco): por isso este arquivo nao usa codigos
-- #  assim (-20224, -20480, -20736, -20992 evitados), e quem automatiza deve
-- #  decidir por EXIT = 0 E nenhum "ORA-" fora da demo E "RESUMO: n OK, 0 FALHOU".
-- #
-- #  *** ESTE ARQUIVO REMOVE (BLOCO 9) AS standalone DA SPRINT 3 ***:
-- #  FN_COBRANCA_JSON, PRC_LISTAR_COBRANCAS_JSON e PRC_RELATORIO_COBRANCAS (as
-- #  versoes novas moram no PKG_COBRANCA). A trigger da Sprint 3 chamava a
-- #  FN_COBRANCA_JSON; ela e substituida (BLOCO 7) ANTES da remocao.
-- #
-- #  NENHUMA credencial, host, senha ou connection string neste arquivo.
-- #############################################################################

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET VERIFY OFF
SET FEEDBACK ON
SET LINESIZE 400
SET PAGESIZE 1000
SET TRIMSPOOL ON
SET TAB OFF
-- Qualquer erro SQL/PL-SQL ENCERRA o script (sqlplus sai com o codigo Oracle) - do
-- inicio ao fim, demonstracao inclusa. ATENCAO: erro de COMPILACAO de um
-- CREATE PACKAGE e so um "Warning" para o sqlplus e NAO dispara esta clausula;
-- quem o pega e o BLOCO 8 (user_errors / user_objects).
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT
PROMPT === BLOCO 0: pre-requisito (5 tabelas da Sprint 3) ===
DECLARE
    v_qtd PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_qtd
      FROM user_tables
     WHERE table_name IN ('COBRANCA','SERVICO_PRECO','LOG_ERRO','CLINICA','TRIAGEM_LUNA');
    IF v_qtd <> 5 THEN
        RAISE_APPLICATION_ERROR(-20900,
            'PRE-REQUISITO NAO ATENDIDO: esperadas 5 tabelas (COBRANCA, SERVICO_PRECO, LOG_ERRO, CLINICA, TRIAGEM_LUNA), '
            || 'encontradas ' || v_qtd || '. Aplique antes o schema da Sprint 3. Script interrompido.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('pre-requisito OK: ' || v_qtd || ' de 5 tabelas presentes.');
END;
/


-- #############################################################################
-- #  BLOCO 1 - LIMPEZA DA FUNCAO STANDALONE DE TRIAGEM
-- #
-- #  Derruba a FN_CALCULAR_SCORE_URGENCIA standalone da Sprint 3 (agora
-- #  substituida por PKG_TRIAGEM.fn_calcular_score_urgencia); nada do arquivo
-- #  depende dela (a trigger chama a funcao de COBRANCA, nao a de triagem). O
-- #  DROP ignora ORA-04043 (objeto inexistente); qualquer outro erro e propagado
-- #  e encerra o script.
-- #
-- #  Os packages e a trigger NAO sao derrubados em bloco nenhum, de proposito:
-- #  entram so por CREATE OR REPLACE (BLOCOS 3 a 7), que e idempotente e PRESERVA
-- #  os objetos dependentes - desde que a versao nova COMPILE (medido na re-G2:
-- #  uma spec quebrada invalida o dependente na hora, e o BLOCO 8 acusa). Com
-- #  DROP PACKAGE todo dependente (medido) fica INVALID; um script interrompido
-- #  depois do DROP deixaria todo INSERT em COBRANCA falhando com ORA-04098 (no
-- #  banco do aplicativo: o lancamento de cobranca cairia).
-- #
-- #  As standalone de COBRANCA (BLOCO 9) so saem depois da verificacao do
-- #  BLOCO 8. Nenhuma tabela e nenhuma sequence e apagada neste arquivo.
-- #############################################################################
PROMPT
PROMPT === BLOCO 1: limpeza da funcao standalone antiga ===
DECLARE
    PROCEDURE remove (p_tipo IN VARCHAR2, p_nome IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'DROP ' || p_tipo || ' ' || p_nome;
        DBMS_OUTPUT.PUT_LINE('removido: ' || p_tipo || ' ' || p_nome);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -4043 THEN
                DBMS_OUTPUT.PUT_LINE('ja nao existia: ' || p_tipo || ' ' || p_nome);
            ELSE
                RAISE;
            END IF;
    END remove;
BEGIN
    remove('FUNCTION', 'FN_CALCULAR_SCORE_URGENCIA');  -- standalone da Sprint 3
END;
/


-- #############################################################################
-- #  BLOCO 2 - AUDITORIA_COBRANCA (somente se ainda nao existir)
-- #
-- #  Mesma DDL do BLOCO 6 da Sprint 3. Cada CREATE ignora ORA-00955 (nome ja
-- #  usado); o historico de auditoria ja gravado NUNCA e apagado.
-- #############################################################################
PROMPT
PROMPT === BLOCO 2: AUDITORIA_COBRANCA (cria se nao existir) ===
DECLARE
    PROCEDURE cria (p_rotulo IN VARCHAR2, p_ddl IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_ddl;
        DBMS_OUTPUT.PUT_LINE('criado: ' || p_rotulo);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -955 THEN
                DBMS_OUTPUT.PUT_LINE('ja existia: ' || p_rotulo);
            ELSE
                RAISE;
            END IF;
    END cria;
BEGIN
    cria('SEQ_AUDITORIA_COBRANCA',
         'CREATE SEQUENCE SEQ_AUDITORIA_COBRANCA START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE');
    cria('AUDITORIA_COBRANCA',
         'CREATE TABLE AUDITORIA_COBRANCA ('
      || ' ID_AUDITORIA   NUMBER(15)   DEFAULT SEQ_AUDITORIA_COBRANCA.NEXTVAL PRIMARY KEY,'
      || ' NM_USUARIO     VARCHAR2(60)  NOT NULL,'
      || ' DS_OPERACAO    VARCHAR2(10)  NOT NULL,'
      || ' DT_OPERACAO    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,'
      || ' ID_COBRANCA    NUMBER(10),'
      || ' DS_VALORES_OLD VARCHAR2(4000),'
      || ' DS_VALORES_NEW VARCHAR2(4000),'
      || ' CONSTRAINT CHK_AUDITORIA_COBRANCA_OP CHECK (DS_OPERACAO IN (''INSERT'',''UPDATE'',''DELETE'')))');
    cria('IDX_AUDITORIA_COB_DATA',
         'CREATE INDEX IDX_AUDITORIA_COB_DATA ON AUDITORIA_COBRANCA(DT_OPERACAO DESC)');
    cria('IDX_AUDITORIA_COB_REG',
         'CREATE INDEX IDX_AUDITORIA_COB_REG ON AUDITORIA_COBRANCA(ID_COBRANCA)');
END;
/

-- COMMENT ON e idempotente (sobrescreve o texto), nao gera erro se repetido.
COMMENT ON TABLE  AUDITORIA_COBRANCA                IS 'Trilha de auditoria DML de COBRANCA (Sprint 3 - FIAP). Alimentada pela trigger TRG_AUDITORIA_COBRANCA (BLOCO 7), via PKG_AUDITORIA. Objeto academico - nao vai para o Flyway.';
COMMENT ON COLUMN AUDITORIA_COBRANCA.NM_USUARIO     IS 'Usuario Oracle que executou a operacao (funcao USER).';
COMMENT ON COLUMN AUDITORIA_COBRANCA.DS_OPERACAO    IS 'Tipo do DML capturado: INSERT, UPDATE ou DELETE.';
COMMENT ON COLUMN AUDITORIA_COBRANCA.DS_VALORES_OLD IS 'Snapshot :OLD serializado em JSON - nulo em INSERT.';
COMMENT ON COLUMN AUDITORIA_COBRANCA.DS_VALORES_NEW IS 'Snapshot :NEW serializado em JSON - nulo em DELETE.';


-- #############################################################################
-- #  BLOCO 3 - PKG_KURA_LOG
-- #
-- #  Ponto unico de gravacao em LOG_ERRO para os demais packages.
-- #
-- #  POR QUE TRANSACAO AUTONOMA: o log precisa sobreviver ao ROLLBACK de quem o
-- #  chamou e, ao mesmo tempo, NAO pode dar COMMIT na transacao do chamador (o
-- #  chamador pode estar no meio de um lancamento de cobranca). Com
-- #  PRAGMA AUTONOMOUS_TRANSACTION a gravacao do log e o COMMIT dela acontecem
-- #  numa transacao separada: o que o chamador ja inseriu sem commit continua
-- #  pendente e visivel so para ele.
-- #
-- #  Package SEM ESTADO (nenhuma variavel de package) e NAO SERIALLY_REUSABLE.
-- #  Nunca propaga erro DO PROPRIO INSERT: um log que falha nao pode derrubar o
-- #  chamador. (Isto NAO cobre o package inutilizavel - spec/body invalido
-- #  propaga ORA-04063/06508 na chamada; quem chama via log_seguro, privado de
-- #  PKG_TRIAGEM e PKG_COBRANCA, engole tambem esse caso.)
-- #############################################################################
PROMPT
PROMPT === BLOCO 3: PKG_KURA_LOG ===

CREATE OR REPLACE PACKAGE PKG_KURA_LOG AS
    -- Grava uma linha em LOG_ERRO e a confirma (COMMIT) em transacao AUTONOMA.
    --   p_origem     - nome do objeto que falhou (vai para NM_PROCEDURE, ate 120 bytes)
    --   p_codigo     - codigo do erro (SQLCODE ou codigo -20xxx proprio), NUMBER(10)
    --   p_mensagem   - texto do erro; truncado em 2000 BYTES (coluna VARCHAR2(2000))
    --   p_parametros - resumo NAO sensivel dos parametros (ex.: 'len=4001');
    --                  NUNCA passe conteudo de mensagem de tutor/paciente (LGPD)
    -- DS_STACK_TRACE recebe DBMS_UTILITY.FORMAT_ERROR_BACKTRACE.
    -- Nao propaga excecao do proprio INSERT; nao faz COMMIT/ROLLBACK na
    -- transacao de quem chama. Valida para todos os chamadores: pode ser chamada
    -- de dentro de uma TRIGGER (a transacao autonoma torna o COMMIT legal).
    PROCEDURE registrar_erro (
        p_origem     IN VARCHAR2,
        p_codigo     IN NUMBER,
        p_mensagem   IN VARCHAR2,
        p_parametros IN VARCHAR2 DEFAULT NULL
    );
END PKG_KURA_LOG;
/
SHOW ERRORS PACKAGE PKG_KURA_LOG

CREATE OR REPLACE PACKAGE BODY PKG_KURA_LOG AS

    -- Limites reais das colunas (NLS_LENGTH_SEMANTICS=BYTE, banco AL32UTF8).
    c_max_origem    CONSTANT PLS_INTEGER := 120;
    c_max_mensagem  CONSTANT PLS_INTEGER := 2000;
    c_max_parametro CONSTANT PLS_INTEGER := 2000;

    -- Corta ate p_max BYTES sem partir caractere multibyte. SUBSTRB tambem nao
    -- parte caractere: o Oracle troca o pedaco do caractere que nao coube por
    -- ESPACOS, e o texto gravado terminaria com espacos que nao estavam na
    -- origem. Aqui o texto termina sempre no ultimo caractere INTEIRO que cabe.
    -- Parte de SUBSTR por caracteres (p_max caracteres podem ocupar ate 4*p_max
    -- bytes, por isso o texto ainda pode passar de p_max bytes) e recua o numero
    -- de caracteres, em passos de ~1/4 do excesso, ate caber.
    FUNCTION corta_bytes (p_txt IN VARCHAR2, p_max IN PLS_INTEGER) RETURN VARCHAR2 IS
        v_txt VARCHAR2(32767) := SUBSTR(p_txt, 1, p_max);
    BEGIN
        WHILE LENGTHB(v_txt) > p_max LOOP
            v_txt := SUBSTR(v_txt, 1, LENGTH(v_txt) - GREATEST(1, CEIL((LENGTHB(v_txt) - p_max) / 4)));
        END LOOP;
        RETURN v_txt;
    END corta_bytes;

    PROCEDURE registrar_erro (
        p_origem     IN VARCHAR2,
        p_codigo     IN NUMBER,
        p_mensagem   IN VARCHAR2,
        p_parametros IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_trace VARCHAR2(32767);
        v_orig  VARCHAR2(200);
        v_msg   VARCHAR2(4000);
        v_par   VARCHAR2(4000);
    BEGIN
        v_trace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
        -- funcao de package nao pode ser chamada de dentro do SQL (PLS-00231):
        -- os valores sao calculados em variaveis antes do INSERT.
        v_orig := corta_bytes(p_origem, c_max_origem);
        v_msg  := corta_bytes(NVL(p_mensagem, '(sem mensagem)'), c_max_mensagem);
        v_par  := corta_bytes(p_parametros, c_max_parametro);
        INSERT INTO LOG_ERRO (NM_PROCEDURE, NM_USUARIO, NR_CODIGO_ERRO,
                              DS_MENSAGEM_ERRO, DS_PARAMETROS, DS_STACK_TRACE)
        VALUES (v_orig, USER, p_codigo, v_msg, v_par, v_trace);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            -- Um log que falha nao pode derrubar o chamador, entao NAO relancamos.
            -- O ROLLBACK encerra a transacao autonoma (so ela; a do chamador nao e
            -- afetada) e a rotina termina em silencio.
            -- Hoje o corpo tem um UNICO DML (o INSERT): se ele falha, o Oracle o
            -- desfaz no nivel do comando e a autonoma sai sem DML pendente, entao
            -- "ROLLBACK" e "NULL" se comportam igual (medido; a demo D.2(d)
            -- exercita este handler mas NAO distingue um do outro). O ROLLBACK fica
            -- como defesa: se um dia houver um 2o DML ANTES do que falha, sair da
            -- autonoma com DML pendente levanta ORA-06519 e o erro VAZARIA para o
            -- chamador (medido no G0, quando havia um DML bem-sucedido antes).
            ROLLBACK;
    END registrar_erro;

END PKG_KURA_LOG;
/
SHOW ERRORS PACKAGE BODY PKG_KURA_LOG

PROMPT === BLOCO 3: PKG_KURA_LOG criado ===


-- #############################################################################
-- #  BLOCO 4 - PKG_TRIAGEM
-- #
-- #  Porte 1:1 da FN_CALCULAR_SCORE_URGENCIA da Sprint 3 (que por sua vez e o
-- #  porte do motor Python TriageEngine.classificar, TRIAGE_RULES_VERSION 1.0):
-- #    * pontos ALTA=10 / MEDIA=3 / BAIXA=1, acumulados por CATEGORIA que casa
-- #      (cada categoria conta uma vez por nivel);
-- #    * nivel = primeiro de ALTA > MEDIA > BAIXA com qualquer match; sem match,
-- #      texto nulo, vazio ou so espacos => 'BAIXA';
-- #    * normalizacao: minusculas + remocao de acento (TRANSLATE com UNISTR, para
-- #      nao depender da codificacao do arquivo); match por substring.
-- #  As listas de palavras e a normalizacao ficam PRIVADAS no body.
-- #
-- #  DIFERENCAS EM RELACAO A SPRINT 3 (todas; nenhuma altera nivel ou score -
-- #  27 frases de fronteira deram o mesmo nivel e o mesmo score nas duas):
-- #    1. os handlers gravam via PKG_KURA_LOG (transacao autonoma) e NAO fazem
-- #       mais ROLLBACK/COMMIT: a transacao do chamador fica intacta (a S3
-- #       desfazia o trabalho pendente do chamador com o ROLLBACK do handler);
-- #    2. texto acima do limite grava o codigo -20003 (antes -20001), para nao
-- #       colidir com o -20001 ("clinica nula") do PKG_COBRANCA da S4-DB-03;
-- #    3. DS_STACK_TRACE passa a ser gravado (a S3 gravava NULL);
-- #    4. o DBMS_OUTPUT do handler OTHERS nao imprime mais o codigo
-- #       ("OTHERS (<cod>)" virou "OTHERS"; o codigo continua em LOG_ERRO);
-- #    5. as variaveis v_baixa (so atribuida, nunca lida) e v_cod foram removidas;
-- #    6. a chamada de log e feita por log_seguro (privada): se o PKG_KURA_LOG
-- #       estiver inutilizavel, a funcao ainda devolve 'BAIXA' (ver abaixo).
-- #  Em erro a funcao retorna 'BAIXA' e nao propaga - inclusive com o BODY do
-- #  PKG_KURA_LOG invalido (medido). Com a SPEC do PKG_KURA_LOG invalida
-- #  o BODY do PKG_TRIAGEM tambem fica INVALID e a chamada propaga ORA-06508
-- #  (medido): esse caso nao e tratavel dentro da funcao, quem o pega e o BLOCO 5.
-- #
-- #  LGPD: DS_PARAMETROS recebe so 'len=<tamanho>' - nunca o texto do tutor.
-- #############################################################################
PROMPT
PROMPT === BLOCO 4: PKG_TRIAGEM ===

CREATE OR REPLACE PACKAGE PKG_TRIAGEM AS
    -- Classifica o texto de uma mensagem de triagem em 'ALTA', 'MEDIA' ou 'BAIXA'.
    -- Codigos gravados em LOG_ERRO quando algo falha (a funcao retorna 'BAIXA'):
    --   -20003  texto com mais de 4000 caracteres (era -20001 na Sprint 3)
    --    -6502  VALUE_ERROR (estouro de buffer na normalizacao)
    --   SQLCODE qualquer outra falha
    FUNCTION fn_calcular_score_urgencia (p_texto IN VARCHAR2) RETURN VARCHAR2;
END PKG_TRIAGEM;
/
SHOW ERRORS PACKAGE PKG_TRIAGEM

CREATE OR REPLACE PACKAGE BODY PKG_TRIAGEM AS

    c_fn         CONSTANT VARCHAR2(30) := 'FN_CALCULAR_SCORE_URGENCIA';
    c_max_texto  CONSTANT PLS_INTEGER  := 4000;
    c_pts_alta   CONSTANT PLS_INTEGER  := 10;
    c_pts_media  CONSTANT PLS_INTEGER  := 3;
    c_pts_baixa  CONSTANT PLS_INTEGER  := 1;

    -- Normalizacao: minusculas + remocao de acento. 1o argumento do TRANSLATE
    -- montado por UNISTR (fonte 100% ASCII).
    --   a: E1 E0 E2 E3 E4 | e: E9 E8 EA EB | i: ED EC EE EF
    --   o: F3 F2 F4 F5 F6 | u: FA F9 FB FC | c: E7
    FUNCTION f_normalizar (p_in IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TRANSLATE(
            LOWER(p_in),
            UNISTR('\00E1\00E0\00E2\00E3\00E4\00E9\00E8\00EA\00EB\00ED\00EC\00EE\00EF\00F3\00F2\00F4\00F5\00F6\00FA\00F9\00FB\00FC\00E7'),
            'aaaaaeeeeiiiiooooouuuuc');
    END f_normalizar;

    -- TRUE se qualquer keyword da lista (delimitada por '|') e substring do texto.
    FUNCTION cat_bate (p_txt IN VARCHAR2, p_kws IN VARCHAR2) RETURN BOOLEAN IS
        v_rest VARCHAR2(4000) := p_kws;
        v_pos  PLS_INTEGER;
        v_kw   VARCHAR2(200);
    BEGIN
        WHILE v_rest IS NOT NULL LOOP
            v_pos := INSTR(v_rest, '|');
            IF v_pos = 0 THEN
                v_kw   := v_rest;
                v_rest := NULL;
            ELSE
                v_kw   := SUBSTR(v_rest, 1, v_pos - 1);
                v_rest := SUBSTR(v_rest, v_pos + 1);
            END IF;
            IF v_kw IS NOT NULL AND INSTR(p_txt, v_kw) > 0 THEN
                RETURN TRUE;
            END IF;
        END LOOP;
        RETURN FALSE;
    END cat_bate;

    -- Grava em LOG_ERRO via PKG_KURA_LOG sem NUNCA propagar. O PKG_KURA_LOG ja
    -- engole falha do proprio INSERT; este bloco cobre o que ele nao cobre: o
    -- package de log INUTILIZAVEL (body invalido => ORA-04063 / ORA-06508 na
    -- chamada). Sem isto a triagem propagaria o erro em vez de devolver BAIXA.
    -- Nao ha transacao pendente do log a proteger aqui (a gravacao e autonoma),
    -- entao "THEN NULL" e seguro. Mesmo padrao para a fn_cobranca_json da S4-DB-03,
    -- que a trigger de COBRANCA chama.
    -- Devolve TRUE se a chamada ao PKG_KURA_LOG RETORNOU (o registrar_erro engole
    -- falha do proprio INSERT, entao TRUE nao garante a linha - o que ela garante
    -- e que o package de log nao estava inutilizavel) e FALSE se a chamada
    -- levantou excecao (spec/body invalido). Quem imprime "registrado" usa o
    -- retorno (RE-M3 da re-G2: antes a mensagem era incondicional).
    FUNCTION log_seguro (p_codigo IN NUMBER, p_mensagem IN VARCHAR2, p_parametros IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        BEGIN
            PKG_KURA_LOG.registrar_erro(c_fn, p_codigo, p_mensagem, p_parametros);
            RETURN TRUE;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN FALSE;
        END;
    END log_seguro;

    FUNCTION msg_reg (p_ok IN BOOLEAN) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN p_ok THEN 'registrado em LOG_ERRO' ELSE 'NAO foi possivel registrar em LOG_ERRO (PKG_KURA_LOG inutilizavel)' END;
    END msg_reg;

    FUNCTION fn_calcular_score_urgencia (p_texto IN VARCHAR2) RETURN VARCHAR2 IS
        e_texto_excede_limite EXCEPTION;

        v_txt    VARCHAR2(4000);
        v_score  PLS_INTEGER := 0;
        v_alta   BOOLEAN := FALSE;
        v_media  BOOLEAN := FALSE;
        v_nivel  VARCHAR2(10);
        v_msg    VARCHAR2(2000);
        v_reg    BOOLEAN;
    BEGIN
        IF p_texto IS NULL OR TRIM(p_texto) IS NULL THEN
            RETURN 'BAIXA';
        END IF;

        IF LENGTH(p_texto) > c_max_texto THEN
            RAISE e_texto_excede_limite;
        END IF;

        v_txt := f_normalizar(p_texto);

        -- ===== NIVEL ALTA (5 categorias, 10 pts cada categoria que casa) =====
        IF cat_bate(v_txt, 'convulsao|convulsionando|convulsoes|tremendo muito|espasmo|desmaiou|perdeu a consciencia')
            THEN v_score := v_score + c_pts_alta; v_alta := TRUE; END IF;
        IF cat_bate(v_txt, 'sangrando|sangue|hemorragia|sangramento|ferida aberta')
            THEN v_score := v_score + c_pts_alta; v_alta := TRUE; END IF;
        IF cat_bate(v_txt, 'envenenado|envenenamento|veneno|intoxicado|intoxicacao|comeu produto|ingeriu produto|rato veneno|raticida')
            THEN v_score := v_score + c_pts_alta; v_alta := TRUE; END IF;
        IF cat_bate(v_txt, 'dificuldade respirar|nao respira|respiracao dificil|ofegante|sufocando|engasgou')
            THEN v_score := v_score + c_pts_alta; v_alta := TRUE; END IF;
        IF cat_bate(v_txt, 'atropelado|atropelamento|caiu de altura|bateu a cabeca|fratura|osso quebrado|acidente')
            THEN v_score := v_score + c_pts_alta; v_alta := TRUE; END IF;

        -- ===== NIVEL MEDIA (4 categorias, 3 pts cada) =====
        IF cat_bate(v_txt, 'vomitando|vomitou|vomito|enjoo|nausea')
            THEN v_score := v_score + c_pts_media; v_media := TRUE; END IF;
        IF cat_bate(v_txt, 'diarreia|fezes moles|coco mole|intestino solto')
            THEN v_score := v_score + c_pts_media; v_media := TRUE; END IF;
        IF cat_bate(v_txt, 'letargico|sem apetite|nao quer comer|muito quieto|parado demais|fraco|cansado demais')
            THEN v_score := v_score + c_pts_media; v_media := TRUE; END IF;
        IF cat_bate(v_txt, 'febre|temperatura alta|quente demais|febril')
            THEN v_score := v_score + c_pts_media; v_media := TRUE; END IF;

        -- ===== NIVEL BAIXA (2 categorias, 1 pt cada) =====
        IF cat_bate(v_txt, 'duvida|pergunta|queria saber|como faco|informacao')
            THEN v_score := v_score + c_pts_baixa; END IF;
        IF cat_bate(v_txt, 'comportamento estranho|latindo muito|miando muito|roendo|arranhando|pulga|carrapato')
            THEN v_score := v_score + c_pts_baixa; END IF;

        IF    v_alta  THEN v_nivel := 'ALTA';
        ELSIF v_media THEN v_nivel := 'MEDIA';
        ELSE               v_nivel := 'BAIXA';
        END IF;

        DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] score=' || v_score || ' -> nivel=' || v_nivel);
        RETURN v_nivel;
    EXCEPTION
        WHEN e_texto_excede_limite THEN
            v_msg := 'texto com ' || LENGTH(p_texto) || ' chars excede o limite de ' || c_max_texto;
            v_reg := log_seguro(-20003, 'TEXTO_EXCEDE_LIMITE: ' || v_msg,
                        'len=' || LENGTH(p_texto));
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] TEXTO_EXCEDE_LIMITE -- ' || msg_reg(v_reg) || '. Retorna BAIXA.');
            RETURN 'BAIXA';
        WHEN VALUE_ERROR THEN
            v_msg := SQLERRM;
            v_reg := log_seguro(-6502, 'VALUE_ERROR: ' || SUBSTR(v_msg, 1, 400), NULL);
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] VALUE_ERROR -- ' || msg_reg(v_reg) || '. Retorna BAIXA.');
            RETURN 'BAIXA';
        WHEN OTHERS THEN
            -- SQLCODE/SQLERRM precisam ser lidos ANTES de qualquer outra chamada.
            v_msg := SQLERRM;
            v_reg := log_seguro(SQLCODE, 'OTHERS: ' || SUBSTR(v_msg, 1, 400), NULL);
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] OTHERS -- ' || msg_reg(v_reg) || '. Retorna BAIXA.');
            RETURN 'BAIXA';
    END fn_calcular_score_urgencia;

END PKG_TRIAGEM;
/
SHOW ERRORS PACKAGE BODY PKG_TRIAGEM

PROMPT === BLOCO 4: PKG_TRIAGEM criado ===

PROMPT
PROMPT === BLOCO 5: verificacao (objetos validos e sem erro de compilacao) ===
DECLARE
    v_lista VARCHAR2(4000);
    v_qtd   PLS_INTEGER;
BEGIN
    FOR r IN (SELECT object_name || ' (' || object_type || ') ' || status AS d
                FROM user_objects
               WHERE object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'AUDITORIA_COBRANCA',
                                     'SEQ_AUDITORIA_COBRANCA', 'IDX_AUDITORIA_COB_DATA',
                                     'IDX_AUDITORIA_COB_REG')
                 AND status <> 'VALID'
              UNION ALL
              SELECT name || ' (' || type || ') erro na linha ' || line || ': '
                     || SUBSTR(REPLACE(text, CHR(10), ' '), 1, 160)
                FROM user_errors
               WHERE name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM') AND attribute = 'ERROR') LOOP
        v_lista := v_lista || CHR(10) || '  - ' || r.d;
    END LOOP;
    SELECT COUNT(*) INTO v_qtd
      FROM user_objects
     WHERE object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM')
       AND object_type IN ('PACKAGE', 'PACKAGE BODY')
       AND status = 'VALID';
    IF v_qtd <> 4 THEN
        v_lista := v_lista || CHR(10) || '  - esperados 4 objetos de package VALID (2 specs + 2 bodies), encontrados ' || v_qtd;
    END IF;
    IF v_lista IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20901,
            SUBSTR('BLOCO 5: objeto(s) invalido(s) ou com erro de compilacao:' || v_lista, 1, 2000));
    END IF;
    DBMS_OUTPUT.PUT_LINE('verificacao OK: PKG_KURA_LOG e PKG_TRIAGEM (spec + body) VALID, 0 erros de compilacao, AUDITORIA_COBRANCA VALID.');
END;
/


-- #############################################################################
-- #  DEMONSTRACAO (S4-DB-02)
-- #
-- #  A demonstracao CONFERE: cada caso imprime "OK: <caso>" ou
-- #  "FALHOU: <caso> (esperado X, obtido Y)" e o bloco termina com
-- #  "RESUMO: n OK, m FALHOU". Se m > 0 o script encerra com erro.
-- #
-- #  Escopo das linhas de LOG_ERRO contadas: somente as DESTA execucao - ID_LOG
-- #  acima do maior existente no inicio, do usuario da sessao e com origem
-- #  FN_CALCULAR_SCORE_URGENCIA ou DEMO_S4_TRUNCAMENTO (assim, linhas que outra
-- #  aplicacao grave no mesmo intervalo nao entram na conta). Premissa: nenhuma
-- #  outra sessao DO MESMO USUARIO chama a triagem durante a demonstracao.
-- #
-- #  A demonstracao grava 5 linhas sinteticas em LOG_ERRO por execucao (sem dado
-- #  pessoal) e NAO executa DDL: a transacao do chamador (D.3) e provada com uma
-- #  linha marcadora pendente em LOG_ERRO, desfeita pelo ROLLBACK.
-- #############################################################################
PROMPT
PROMPT ###################  DEMO S4-DB-02: INICIO  ###################
DECLARE
    c_fn      CONSTANT VARCHAR2(30) := 'FN_CALCULAR_SCORE_URGENCIA';
    -- frase REAL de triagem (40 chars), repetida para montar o texto de 4001
    -- chars: se o texto fosse gravado no log, o detector de LGPD (D.5) o acharia.
    c_frase   CONSTANT VARCHAR2(40) := 'meu cao teve convulsao e esta sangrando ';

    v_base    LOG_ERRO.ID_LOG%TYPE;
    v_ok      PLS_INTEGER := 0;
    v_falhou  PLS_INTEGER := 0;
    v_nivel   VARCHAR2(10);
    v_texto   VARCHAR2(32767);
    v_longo   VARCHAR2(32767);    -- texto de 4001 chars montado a partir de c_frase
    v_antes   PLS_INTEGER;
    v_tx_ant  VARCHAR2(200);
    v_tx_dep  VARCHAR2(200);
    v_terr    VARCHAR2(100);
    v_numch   VARCHAR2(10);
    v_prop    VARCHAR2(100);
    v_n       PLS_INTEGER;
    v_cob     PLS_INTEGER;
    v_aud     PLS_INTEGER;
    v_marca   VARCHAR2(100) := 'marcadora pendente do chamador ' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF6');
    r         LOG_ERRO%ROWTYPE;

    PROCEDURE confere (p_caso IN VARCHAR2, p_esperado IN VARCHAR2, p_obtido IN VARCHAR2) IS
    BEGIN
        IF p_esperado = p_obtido OR (p_esperado IS NULL AND p_obtido IS NULL) THEN
            v_ok := v_ok + 1;
            DBMS_OUTPUT.PUT_LINE('OK: ' || p_caso);
        ELSE
            v_falhou := v_falhou + 1;
            DBMS_OUTPUT.PUT_LINE('FALHOU: ' || p_caso || ' (esperado ' || SUBSTR(NVL(p_esperado, '(nulo)'), 1, 100)
                                 || ', obtido ' || SUBSTR(NVL(p_obtido, '(nulo)'), 1, 100)
                                 || CASE WHEN LENGTH(p_obtido) > 100 THEN '... [' || LENGTH(p_obtido) || ' chars]' END || ')');
        END IF;
    END confere;

    -- linhas de LOG_ERRO gravadas por ESTA execucao
    FUNCTION n_log RETURN PLS_INTEGER IS
        n PLS_INTEGER;
    BEGIN
        SELECT COUNT(*) INTO n FROM LOG_ERRO
         WHERE ID_LOG > v_base AND NM_USUARIO = USER
           AND NM_PROCEDURE IN (c_fn, 'DEMO_S4_TRUNCAMENTO');
        RETURN n;
    END n_log;

    -- ultima linha de LOG_ERRO desta execucao (ID_LOG nulo se nao ha nenhuma)
    FUNCTION ultima RETURN LOG_ERRO%ROWTYPE IS
        v LOG_ERRO%ROWTYPE;
    BEGIN
        SELECT * INTO v FROM LOG_ERRO
         WHERE ID_LOG = (SELECT MAX(ID_LOG) FROM LOG_ERRO
                          WHERE ID_LOG > v_base AND NM_USUARIO = USER
                            AND NM_PROCEDURE IN (c_fn, 'DEMO_S4_TRUNCAMENTO'));
        RETURN v;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN v;
    END ultima;

    -- linha marcadora pendente da transacao do chamador (D.3), visivel so a esta sessao
    FUNCTION n_marca RETURN PLS_INTEGER IS
        n PLS_INTEGER;
    BEGIN
        SELECT COUNT(*) INTO n FROM LOG_ERRO
         WHERE NM_PROCEDURE = 'DEMO_S4_TX' AND NM_USUARIO = USER AND DS_MENSAGEM_ERRO = v_marca;
        RETURN n;
    END n_marca;

    PROCEDURE nivel (p_caso IN VARCHAR2, p_texto IN VARCHAR2, p_esperado IN VARCHAR2) IS
    BEGIN
        confere(p_caso, p_esperado, PKG_TRIAGEM.fn_calcular_score_urgencia(p_texto));
    END nivel;

    PROCEDURE restaura_nls IS
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_TERRITORY = ''' || v_terr || '''';
    END restaura_nls;
BEGIN
    SELECT NVL(MAX(ID_LOG), 0) INTO v_base FROM LOG_ERRO;
    DBMS_OUTPUT.PUT_LINE('LOG_ERRO: maior ID_LOG antes da demo = ' || v_base);

    WHILE v_longo IS NULL OR LENGTH(v_longo) < 4001 LOOP
        v_longo := v_longo || c_frase;
    END LOOP;
    v_longo := SUBSTR(v_longo, 1, 4001);
    confere('montagem do texto longo (chars)', '4001', TO_CHAR(LENGTH(v_longo)));

    -- ======================= D.1 caminho feliz / equivalencia ================
    DBMS_OUTPUT.PUT_LINE('---- D.1 niveis (as 18 frases da equivalencia com a Sprint 3) ----');
    nivel('D.1-01 convulsao + sangrando',            'Meu cachorro teve uma convulsao e esta sangrando muito', 'ALTA');
    nivel('D.1-02 vomitando + diarreia',             'A gata esta vomitando e com diarreia desde ontem',       'MEDIA');
    nivel('D.1-03 duvida sobre a racao',             'Tenho uma duvida sobre a racao do filhote',              'BAIXA');
    nivel('D.1-04 agradecimento',                    'Ele esta otimo, so passei para agradecer o atendimento', 'BAIXA');
    nivel('D.1-05 vazio',                            '',                                                       'BAIXA');
    nivel('D.1-06 convulsao + febre + duvida',       'meu cao teve convulsao, esta com febre e uma duvida',    'ALTA');
    nivel('D.1-07 convulsao + sangramento',          'convulsao e sangramento intenso',                        'ALTA');
    nivel('D.1-08 vomitando + febre',                'vomitando e febre',                                      'MEDIA');
    nivel('D.1-09 duvida alimentacao',               'duvida alimentacao',                                     'BAIXA');
    nivel('D.1-10 MAIUSCULA com acento',             UNISTR('MEU C\00C3O TEVE CONVULS\00C3O'),                 'ALTA');
    nivel('D.1-11 febre + nao quer comer (acento)',  UNISTR('febre alta e n\00E3o quer comer'),                'MEDIA');
    nivel('D.1-12 atropelado + respiracao dificil',  UNISTR('atropelado, respira\00E7\00E3o dif\00EDcil'),     'ALTA');
    nivel('D.1-13 raticida',                         'comeu raticida',                                         'ALTA');
    nivel('D.1-14 pulga e carrapato',                'pulga e carrapato',                                      'BAIXA');
    nivel('D.1-15 venenoso (substring de veneno)',   'remedio venenoso',                                       'ALTA');
    nivel('D.1-16 NULL',                             NULL,                                                     'BAIXA');
    nivel('D.1-17 so espacos',                       '     ',                                                  'BAIXA');
    nivel('D.1-18 intoxicacao + diarreia + pulga',   UNISTR('intoxica\00E7\00E3o + diarreia + pulga'),         'ALTA');
    confere('D.1 nenhuma linha de log no caminho feliz', '0', TO_CHAR(n_log));

    -- ======================= D.2 excecoes provocadas =========================
    DBMS_OUTPUT.PUT_LINE('---- D.2 excecoes provocadas ----');
    -- (a) texto de 4001 caracteres => -20003, DS_PARAMETROS = len=4001
    v_antes := n_log;
    v_nivel := PKG_TRIAGEM.fn_calcular_score_urgencia(v_longo);
    confere('D.2a retorno', 'BAIXA', v_nivel);
    confere('D.2a linhas novas', '1', TO_CHAR(n_log - v_antes));
    r := ultima;
    confere('D.2a NM_PROCEDURE', c_fn, r.NM_PROCEDURE);
    confere('D.2a NR_CODIGO_ERRO', '-20003', TO_CHAR(r.NR_CODIGO_ERRO));
    confere('D.2a DS_PARAMETROS', 'len=4001', r.DS_PARAMETROS);
    confere('D.2a DS_STACK_TRACE preenchido', 'SIM', CASE WHEN r.DS_STACK_TRACE IS NULL THEN 'NAO' ELSE 'SIM' END);

    -- (b) 3000 caracteres de 2 bytes que sobrevivem a normalizacao (6000 bytes > buffer de 4000) => VALUE_ERROR
    v_antes := n_log;
    v_texto := RPAD(UNISTR('\00F1'), 3000, UNISTR('\00F1'));
    v_nivel := PKG_TRIAGEM.fn_calcular_score_urgencia(v_texto);
    confere('D.2b retorno', 'BAIXA', v_nivel);
    confere('D.2b linhas novas', '1', TO_CHAR(n_log - v_antes));
    r := ultima;
    confere('D.2b NR_CODIGO_ERRO', '-6502', TO_CHAR(r.NR_CODIGO_ERRO));
    confere('D.2b mensagem comeca por VALUE_ERROR', 'VALUE_ERROR: ', SUBSTR(r.DS_MENSAGEM_ERRO, 1, 13));
    confere('D.2b DS_PARAMETROS nulo (1:1 com a Sprint 3)', NULL, r.DS_PARAMETROS);

    -- (c) PKG_KURA_LOG direto: mensagem de 3000 caracteres de 2 bytes => truncada em 2000 bytes
    v_antes := n_log;
    v_texto := RPAD(UNISTR('\00E7'), 3000, UNISTR('\00E7'));
    PKG_KURA_LOG.registrar_erro('DEMO_S4_TRUNCAMENTO', -20999, v_texto, 'len=3000');
    confere('D.2c linhas novas', '1', TO_CHAR(n_log - v_antes));
    r := ultima;
    confere('D.2c NR_CODIGO_ERRO', '-20999', TO_CHAR(r.NR_CODIGO_ERRO));
    confere('D.2c bytes da mensagem (limite da coluna)', '2000', TO_CHAR(LENGTHB(r.DS_MENSAGEM_ERRO)));
    confere('D.2c caracteres da mensagem (nenhum partido)', '1000', TO_CHAR(LENGTH(r.DS_MENSAGEM_ERRO)));
    confere('D.2c DS_PARAMETROS', 'len=3000', r.DS_PARAMETROS);

    -- (d) PKG_KURA_LOG direto com origem NULA (NM_PROCEDURE e NOT NULL): o log falha e NAO propaga
    v_antes := n_log;
    BEGIN
        PKG_KURA_LOG.registrar_erro(NULL, -20998, 'falha provocada do proprio log', NULL);
        v_prop := 'NAO';
    EXCEPTION
        WHEN OTHERS THEN
            v_prop := 'SIM (' || SQLCODE || ')';
    END;
    confere('D.2d registrar_erro com falha propaga excecao', 'NAO', v_prop);
    confere('D.2d nenhuma linha gravada', '0', TO_CHAR(n_log - v_antes));
    confere('D.2 total de linhas ate aqui (a, b, c)', '3', TO_CHAR(n_log));

    -- ======================= D.3 transacao do chamador =======================
    DBMS_OUTPUT.PUT_LINE('---- D.3 a transacao do CHAMADOR sobrevive ao log autonomo (sem DDL) ----');
    -- Linha marcadora PENDENTE (sem COMMIT) = trabalho nao confirmado do chamador.
    INSERT INTO LOG_ERRO (NM_PROCEDURE, NM_USUARIO, NR_CODIGO_ERRO, DS_MENSAGEM_ERRO)
    VALUES ('DEMO_S4_TX', USER, -20997, v_marca);
    v_tx_ant := DBMS_TRANSACTION.LOCAL_TRANSACTION_ID;
    confere('D.3 ha transacao pendente antes da chamada', 'SIM', CASE WHEN v_tx_ant IS NULL THEN 'NAO' ELSE 'SIM' END);
    confere('D.3 marcadora visivel antes da chamada', '1', TO_CHAR(n_marca));
    v_antes := n_log;
    v_nivel := PKG_TRIAGEM.fn_calcular_score_urgencia(v_longo);      -- erro => log autonomo (COMMIT proprio)
    v_tx_dep := DBMS_TRANSACTION.LOCAL_TRANSACTION_ID;
    confere('D.3 retorno da chamada com erro', 'BAIXA', v_nivel);
    confere('D.3 o log gravou 1 linha', '1', TO_CHAR(n_log - v_antes));
    confere('D.3 mesma transacao (transaction id igual) depois da chamada', v_tx_ant, v_tx_dep);
    confere('D.3 marcadora continua pendente depois da chamada', '1', TO_CHAR(n_marca));
    ROLLBACK;
    confere('D.3 marcadora some no ROLLBACK do chamador', '0', TO_CHAR(n_marca));
    confere('D.3 o log autonomo sobrevive ao ROLLBACK (a, b, c + este)', '4', TO_CHAR(n_log));

    -- ======================= D.4 NLS_TERRITORY = BRAZIL ======================
    DBMS_OUTPUT.PUT_LINE('---- D.4 mesma demo com NLS_TERRITORY=BRAZIL (separador decimal virgula) ----');
    SELECT value INTO v_terr FROM nls_session_parameters WHERE parameter = 'NLS_TERRITORY';
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_TERRITORY = ''BRAZIL''';
        SELECT value INTO v_numch FROM nls_session_parameters WHERE parameter = 'NLS_NUMERIC_CHARACTERS';
        confere('D.4 NLS_NUMERIC_CHARACTERS sob BRAZIL', ',.', v_numch);
        nivel('D.4 caminho feliz sob BRAZIL', 'Meu cachorro teve uma convulsao e esta sangrando muito', 'ALTA');
        v_antes := n_log;
        nivel('D.4 excecao sob BRAZIL (retorno)', v_longo, 'BAIXA');
        confere('D.4 linhas novas sob BRAZIL', '1', TO_CHAR(n_log - v_antes));
        r := ultima;
        confere('D.4 NR_CODIGO_ERRO sob BRAZIL', '-20003', TO_CHAR(r.NR_CODIGO_ERRO));
        confere('D.4 DS_PARAMETROS sob BRAZIL', 'len=4001', r.DS_PARAMETROS);
    EXCEPTION
        WHEN OTHERS THEN
            restaura_nls;
            RAISE;
    END;
    restaura_nls;

    -- ======================= D.5 LGPD ========================================
    DBMS_OUTPUT.PUT_LINE('---- D.5 LGPD: nenhum trecho da frase de triagem foi para o LOG_ERRO ----');
    SELECT COUNT(*) INTO v_n
      FROM LOG_ERRO
     WHERE ID_LOG > v_base AND NM_USUARIO = USER AND NM_PROCEDURE IN (c_fn, 'DEMO_S4_TRUNCAMENTO')
       AND (   INSTR(LOWER(DS_MENSAGEM_ERRO), 'convulsao') > 0 OR INSTR(LOWER(DS_PARAMETROS), 'convulsao') > 0
            OR INSTR(LOWER(DS_MENSAGEM_ERRO), 'sangrando') > 0 OR INSTR(LOWER(DS_PARAMETROS), 'sangrando') > 0
            OR INSTR(LOWER(DS_MENSAGEM_ERRO), 'meu cao')   > 0 OR INSTR(LOWER(DS_PARAMETROS), 'meu cao')   > 0
            OR DBMS_LOB.INSTR(LOWER(DS_STACK_TRACE), 'convulsao') > 0
            OR DBMS_LOB.INSTR(LOWER(DS_STACK_TRACE), 'sangrando') > 0
            OR DBMS_LOB.INSTR(LOWER(DS_STACK_TRACE), 'meu cao')   > 0);
    confere('D.5 linhas desta execucao com trecho da frase', '0', TO_CHAR(v_n));
    SELECT COUNT(*) INTO v_n
      FROM LOG_ERRO
     WHERE ID_LOG > v_base AND NM_USUARIO = USER AND NM_PROCEDURE = c_fn AND DS_PARAMETROS = 'len=4001';
    confere('D.5 controle: linhas com DS_PARAMETROS = len=4001 (a, D.3, D.4)', '3', TO_CHAR(v_n));

    -- ======================= D.6 fechamento ==================================
    DBMS_OUTPUT.PUT_LINE('---- D.6 contagens ----');
    confere('D.6 linhas gravadas por esta execucao (a, b, c, D.3, D.4)', '5', TO_CHAR(n_log));
    SELECT COUNT(*) INTO v_cob FROM COBRANCA;
    SELECT COUNT(*) INTO v_aud FROM AUDITORIA_COBRANCA;
    DBMS_OUTPUT.PUT_LINE('COBRANCA = ' || v_cob || ' | AUDITORIA_COBRANCA = ' || v_aud
                         || ' (somente leitura: a demo nao as altera)');

    DBMS_OUTPUT.PUT_LINE('RESUMO: ' || v_ok || ' OK, ' || v_falhou || ' FALHOU');
    IF v_falhou > 0 THEN
        RAISE_APPLICATION_ERROR(-20902, 'DEMO S4-DB-02: ' || v_falhou || ' caso(s) FALHOU - ver as linhas FALHOU acima');
    END IF;
END;
/
PROMPT ###################  DEMO S4-DB-02: FIM  ###################

-- BLOCO 5 de novo: a demonstracao nao deixou nada invalido.
PROMPT
PROMPT === BLOCO 5: verificacao (objetos validos e sem erro de compilacao) ===
DECLARE
    v_lista VARCHAR2(4000);
    v_qtd   PLS_INTEGER;
BEGIN
    FOR r IN (SELECT object_name || ' (' || object_type || ') ' || status AS d
                FROM user_objects
               WHERE object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'AUDITORIA_COBRANCA',
                                     'SEQ_AUDITORIA_COBRANCA', 'IDX_AUDITORIA_COB_DATA',
                                     'IDX_AUDITORIA_COB_REG')
                 AND status <> 'VALID'
              UNION ALL
              SELECT name || ' (' || type || ') erro na linha ' || line || ': '
                     || SUBSTR(REPLACE(text, CHR(10), ' '), 1, 160)
                FROM user_errors
               WHERE name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM') AND attribute = 'ERROR') LOOP
        v_lista := v_lista || CHR(10) || '  - ' || r.d;
    END LOOP;
    SELECT COUNT(*) INTO v_qtd
      FROM user_objects
     WHERE object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM')
       AND object_type IN ('PACKAGE', 'PACKAGE BODY')
       AND status = 'VALID';
    IF v_qtd <> 4 THEN
        v_lista := v_lista || CHR(10) || '  - esperados 4 objetos de package VALID (2 specs + 2 bodies), encontrados ' || v_qtd;
    END IF;
    IF v_lista IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20901,
            SUBSTR('BLOCO 5: objeto(s) invalido(s) ou com erro de compilacao:' || v_lista, 1, 2000));
    END IF;
    DBMS_OUTPUT.PUT_LINE('verificacao OK: PKG_KURA_LOG e PKG_TRIAGEM (spec + body) VALID, 0 erros de compilacao, AUDITORIA_COBRANCA VALID.');
END;
/
PROMPT
PROMPT === FIM DO ARQUIVO 2TDSPF_2026_Packages_Integrantes.sql ===
