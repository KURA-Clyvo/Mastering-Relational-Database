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
-- #  FALHOU), ORA-20903 -> 167 (BLOCO 9: algo depende da FN_COBRANCA_JSON da
-- #  Sprint 3 que seria removida). Todo erro cujo codigo e MULTIPLO DE 256 sai com 0 (ex.: ORA-20224,
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
PROMPT === BLOCO 1: limpeza da funcao standalone de triagem ===
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
-- #  propaga ORA-04063/06508 na chamada direta. PKG_TRIAGEM e PKG_COBRANCA o
-- #  chamam por SQL dinamico dentro de log_seguro (privado), que engole esse
-- #  caso SEM depender do PKG_KURA_LOG em tempo de compilacao - ver I-1 no
-- #  cabecalho do BLOCO 5.)
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
-- #  Em erro a funcao retorna 'BAIXA' e nao propaga - inclusive com o BODY ou a
-- #  SPEC do PKG_KURA_LOG invalidos (medido): o log_seguro chama o PKG_KURA_LOG
-- #  por SQL dinamico (EXECUTE IMMEDIATE), entao o BODY do PKG_TRIAGEM NAO tem
-- #  dependencia de compilacao dele e nao fica INVALID quando a spec do log
-- #  quebra (antes da fix wave ficava, e a chamada propagava ORA-06508).
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
    -- levantou excecao (spec/body invalido). Quem imprime "enviado" usa o
    -- retorno (RE-M3 da re-G2: antes a mensagem era incondicional).
    FUNCTION log_seguro (p_codigo IN NUMBER, p_mensagem IN VARCHAR2, p_parametros IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        BEGIN
            EXECUTE IMMEDIATE 'BEGIN PKG_KURA_LOG.registrar_erro(:1, :2, :3, :4); END;'
                USING c_fn, p_codigo, p_mensagem, p_parametros;
            RETURN TRUE;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN FALSE;
        END;
    END log_seguro;

    FUNCTION msg_reg (p_ok IN BOOLEAN) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN p_ok THEN 'enviado ao PKG_KURA_LOG' ELSE 'NAO foi possivel chamar o PKG_KURA_LOG (inutilizavel)' END;
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

-- #############################################################################
-- #  BLOCO 5 - PKG_COBRANCA
-- #
-- #  Evolui as tres rotinas de cobranca da Sprint 3 (FN_COBRANCA_JSON,
-- #  PRC_LISTAR_COBRANCAS_JSON, PRC_RELATORIO_COBRANCAS) para um package e
-- #  acrescenta tres rotinas que a APLICACAO (.NET) chama: listar_json,
-- #  relatorio_json e exportar_todas.
-- #
-- #  JSON 100% a mao (concatenacao + escape proprio), como na Sprint 3: nenhum
-- #  construtor, serializador ou acessor JSON nativo do Oracle e usado. Soma
-- #  100% manual (acumuladores + quebra de grupo): nenhuma clausula de
-- #  agrupamento nem funcao de agregacao.
-- #
-- #  DIFERENCAS EM RELACAO A SPRINT 3 (todas):
-- #    1. o tratamento de erro grava via PKG_KURA_LOG (transacao AUTONOMA) e NAO
-- #       faz mais ROLLBACK/COMMIT: a S3 desfazia o trabalho pendente de quem
-- #       chamava. Isto e o que torna LEGAL logar dentro da FN_COBRANCA_JSON, que
-- #       a trigger chama (a S3 NAO podia: COMMIT em trigger e ORA-04092);
-- #    2. toda gravacao de log passa por log_seguro (privada, bloco aninhado com
-- #       WHEN OTHERS): se o PKG_KURA_LOG estiver inutilizavel (spec OU body
-- #       invalido), a fn_cobranca_json ainda devolve o JSON de fallback e NAO
-- #       derruba o INSERT em COBRANCA. I-1 da G2: com chamada ESTATICA
-- #       (PKG_KURA_LOG.registrar_erro(...)) o BODY do PKG_COBRANCA depende, em
-- #       tempo de COMPILACAO, da SPEC do log; spec invalida => body do
-- #       PKG_COBRANCA invalido => a trigger nao consegue chamar a
-- #       fn_cobranca_json => ORA-04063 em todo INSERT/UPDATE em COBRANCA (o
-- #       WHEN OTHERS nao ajuda: o body nem executa). Por isso o log e chamado
-- #       por EXECUTE IMMEDIATE (resolvido na execucao): o body do PKG_COBRANCA
-- #       e o do PKG_TRIAGEM nao dependem mais do PKG_KURA_LOG (confira em
-- #       user_dependencies). CONTINUA sem protecao: PKG_AUDITORIA ausente/
-- #       invalido e o proprio PKG_COBRANCA invalido derrubam o DML (ver RISCO
-- #       CONHECIDO no BLOCO 7);
-- #    3. NM_PROCEDURE em LOG_ERRO passa a ser 'PKG_COBRANCA.<ROTINA>';
-- #    4. a mensagem "enviado ao PKG_KURA_LOG" so e impressa se a chamada ao log
-- #       retornou (RE-M3 da re-G2);
-- #    5. rotinas novas: listar_json, relatorio_json, exportar_todas.
-- #  Mesmos nomes de campo, mesma ordem, mesmo escape, mesmo ponto decimal e mesma
-- #  data ISO-8601 da S3; o formato do relatorio e BYTE A BYTE o da S3 (medido
-- #  com diff dos spools, ver relatorio da task).
-- #
-- #  LGPD: so ids, valores e o nome do servico/clinica vao para o JSON; em
-- #  LOG_ERRO vai apenas 'p_id_clinica=<n>' / 'idCobranca=<n>', nunca texto.
-- #
-- #  Package SEM ESTADO (so constantes) e NAO SERIALLY_REUSABLE.
-- #############################################################################
PROMPT
PROMPT === BLOCO 5: PKG_COBRANCA ===

CREATE OR REPLACE PACKAGE PKG_COBRANCA AS
    -- Serializa UMA cobranca em JSON (objeto), a partir de ESCALARES.
    -- Escalares de proposito: a trigger de COBRANCA a chama com :OLD/:NEW e uma
    -- trigger FOR EACH ROW nao pode ler a propria tabela (ORA-04091); a funcao so
    -- consulta SERVICO_PRECO (para o nome do servico), que a trigger nao toca.
    -- Campos (nesta ordem): idCobranca, idEvento, idClinica, idServico, servico
    -- (STRING com o nome, ou null), valor (ponto decimal, 2 casas), formaPagamento,
    -- dataCobranca (ISO-8601 sem fuso), ativa (true/false). NULL vira o literal null.
    -- NUNCA propaga excecao (e chamada pela trigger: propagar derrubaria o DML):
    --   servico inexistente -> {"erro":"NO_DATA_FOUND","idCobranca":<id>,"detalhe":"servico inexistente"}
    --   estouro de buffer   -> {"erro":"VALUE_ERROR","idCobranca":<id>}
    --   qualquer outra      -> {"erro":"OTHERS","idCobranca":<id>,"sqlcode":<cod>}
    -- e grava a falha em LOG_ERRO (codigos 100, -6502 ou SQLCODE).
    FUNCTION fn_cobranca_json (
        p_id_cobranca IN NUMBER,
        p_id_evento   IN NUMBER,
        p_id_clinica  IN NUMBER,
        p_id_servico  IN NUMBER,
        p_vl_cobrado  IN NUMBER,
        p_ds_forma    IN VARCHAR2,
        p_dt_cobranca IN TIMESTAMP,
        p_st_ativa    IN CHAR
    ) RETURN VARCHAR2;

    -- Versao Sprint 3 para demonstracao em SQL*Plus: imprime (DBMS_OUTPUT) um
    -- objeto JSON por linha, agrupado por clinica, das cobrancas ATIVAS. NULL = todas.
    -- Clinica inexistente/inativa ou sem cobrancas: grava LOG_ERRO e imprime aviso.
    -- Nao faz ROLLBACK/COMMIT e NAO propaga excecao.
    PROCEDURE prc_listar_cobrancas_json (p_id_clinica IN NUMBER DEFAULT NULL);

    -- Versao Sprint 3: relatorio totalizado (combinacao clinica x forma, Sub Total
    -- por clinica, Total Geral) em formato fixo, via DBMS_OUTPUT. NULL = todas.
    -- Soma manual com quebra de grupo. Nao faz ROLLBACK/COMMIT; nao propaga excecao.
    PROCEDURE prc_relatorio_cobrancas (p_id_clinica IN NUMBER DEFAULT NULL);

    -- CHAMADA PELA APLICACAO. Array JSON das cobrancas ATIVAS da clinica, um objeto
    -- por linha (CHR(10) depois de cada elemento, para o spool nao quebrar o
    -- JSON), cada objeto = o da fn_cobranca_json + "nmClinica" no fim. Ordenado por
    -- ID_COBRANCA. Sem cobrancas => [] (nao e erro). CLOB temporario de duracao
    -- SESSION: quem chama deve liberar (Dispose no ODP.NET).
    --   p_id_clinica nulo       -> ORA-20001
    --   clinica inexistente ou inativa -> ORA-20002
    -- Erro: grava LOG_ERRO e RELANCA (a aplicacao precisa saber). Garante que
    -- nenhuma cobranca de OUTRA clinica entra no resultado.
    PROCEDURE listar_json (p_id_clinica IN NUMBER, p_saida OUT CLOB);

    -- CHAMADA PELA APLICACAO. Os numeros do prc_relatorio_cobrancas daquela clinica:
    -- {"idClinica":<id>,"grupos":[{"forma":"BOLETO","total":386.75},...],"subTotal":1565.10}
    -- um grupo por linha; grupos ordenados por forma; cobranca sem forma entra como
    -- "(nao informado)" (igual a S3); sem cobrancas => "grupos":[] e subTotal 0.00.
    -- Soma MANUAL. Mesmos erros e mesmo comportamento de erro do listar_json.
    PROCEDURE relatorio_json (p_id_clinica IN NUMBER, p_saida OUT CLOB);

    -- SO PARA O ARQUIVO DO ENTREGAVEL 3 (dataset JSON). Array de TODAS as
    -- cobrancas ativas de TODAS as clinicas, no mesmo formato do listar_json.
    -- *** NUNCA deve ser exposta pela aplicacao: devolve dado de todos os
    -- tenants (vazamento cross-tenant). *** Erro: grava LOG_ERRO e relanca.
    PROCEDURE exportar_todas (p_saida OUT CLOB);
END PKG_COBRANCA;
/
SHOW ERRORS PACKAGE PKG_COBRANCA

CREATE OR REPLACE PACKAGE BODY PKG_COBRANCA AS

    c_pkg                     CONSTANT VARCHAR2(20) := 'PKG_COBRANCA.';
    c_err_clinica_nula        CONSTANT PLS_INTEGER  := -20001;
    c_err_clinica_inexistente CONSTANT PLS_INTEGER  := -20002;
    c_larg_val                CONSTANT PLS_INTEGER  := 12;   -- largura da coluna numerica
    c_larg_rot                CONSTANT PLS_INTEGER  := 31;   -- largura do rotulo antes do valor

    -- ------------------------------------------------------------------ helpers

    -- Escape manual de string JSON (RFC 8259). ORDEM: barra invertida ANTES da
    -- aspa dupla - senao a '\' inserida pelo escape da aspa e re-escapada.
    FUNCTION escapar (p_txt IN VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(4000);
    BEGIN
        IF p_txt IS NULL THEN RETURN NULL; END IF;
        v := REPLACE(p_txt, '\', '\\');    -- 1o
        v := REPLACE(v,     '"', '\"');    -- 2o
        v := REPLACE(v, CHR(13), '\r');
        v := REPLACE(v, CHR(10), '\n');
        v := REPLACE(v, CHR(9),  '\t');
        RETURN v;
    END escapar;

    -- "conteudo escapado" OU o literal null (sem aspas).
    FUNCTION txt_ou_null (p_txt IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        IF p_txt IS NULL THEN RETURN 'null'; END IF;
        RETURN '"' || escapar(p_txt) || '"';
    END txt_ou_null;

    -- Numero JSON com PONTO decimal forcado, independente do NLS da sessao
    -- (sessao FIAP/Brasil = ',.': TO_CHAR(12.5) daria "12,5" = JSON invalido).
    FUNCTION num_json (p_num IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF p_num IS NULL THEN RETURN 'null'; END IF;
        RETURN TO_CHAR(p_num, 'FM99999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''');
    END num_json;

    -- Idem para SOMAS (mais largo: a soma de muitas cobrancas passa de 8 digitos).
    FUNCTION soma_json (p_num IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_num, 'FM9999999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''');
    END soma_json;

    -- Data ISO-8601 estavel, nunca o default de NLS_TIMESTAMP_FORMAT.
    FUNCTION data_iso (p_dt IN TIMESTAMP) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_dt, 'YYYY-MM-DD"T"HH24:MI:SS');
    END data_iso;

    -- Grava em LOG_ERRO via PKG_KURA_LOG sem NUNCA propagar (mesmo padrao do
    -- PKG_TRIAGEM). TRUE = a chamada retornou; FALSE = o package de log estava
    -- inutilizavel (spec/body invalido). Chamavel de dentro de trigger: o log e
    -- autonomo, entao o COMMIT dele nao e ORA-04092.
    FUNCTION log_seguro (p_rotina IN VARCHAR2, p_codigo IN NUMBER, p_mensagem IN VARCHAR2,
                         p_parametros IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        BEGIN
            EXECUTE IMMEDIATE 'BEGIN PKG_KURA_LOG.registrar_erro(:1, :2, :3, :4); END;'
                USING c_pkg || p_rotina, p_codigo, p_mensagem, p_parametros;
            RETURN TRUE;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN FALSE;
        END;
    END log_seguro;

    FUNCTION msg_reg (p_ok IN BOOLEAN) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN p_ok THEN 'enviado ao PKG_KURA_LOG.' ELSE 'NAO foi possivel chamar o PKG_KURA_LOG (inutilizavel).' END;
    END msg_reg;

    -- Acrescenta texto ao CLOB temporario (amount de CLOB e em CARACTERES).
    PROCEDURE anexa (p_lob IN OUT NOCOPY CLOB, p_txt IN VARCHAR2) IS
    BEGIN
        IF p_txt IS NOT NULL THEN
            DBMS_LOB.WRITEAPPEND(p_lob, LENGTH(p_txt), p_txt);
        END IF;
    END anexa;

    PROCEDURE inicia_lob (p_lob IN OUT NOCOPY CLOB) IS
    BEGIN
        DBMS_LOB.CREATETEMPORARY(p_lob, TRUE, DBMS_LOB.SESSION);
    END inicia_lob;

    -- Libera o CLOB temporario (usado so no caminho de erro). O p_lob := NULL
    -- vale so para a copia local: como a excecao propaga, o OUT de quem chamou
    -- NAO e alterado (medido na G2/M8) - o que importa aqui e liberar o LOB.
    PROCEDURE libera_lob (p_lob IN OUT NOCOPY CLOB) IS
    BEGIN
        IF p_lob IS NOT NULL THEN
            IF DBMS_LOB.ISTEMPORARY(p_lob) = 1 THEN
                DBMS_LOB.FREETEMPORARY(p_lob);
            END IF;
        END IF;
        p_lob := NULL;
    EXCEPTION
        WHEN OTHERS THEN
            p_lob := NULL;
    END libera_lob;

    -- Monta o objeto JSON de UMA cobranca. O nome do servico e passado (a
    -- fn_cobranca_json o busca; o listar_json o traz no JOIN). p_inclui_clinica
    -- acrescenta "nmClinica" no fim (so nas listas).
    FUNCTION monta_json (
        p_id_cobranca IN NUMBER, p_id_evento IN NUMBER, p_id_clinica IN NUMBER,
        p_id_servico  IN NUMBER, p_vl_cobrado IN NUMBER, p_ds_forma IN VARCHAR2,
        p_dt_cobranca IN TIMESTAMP, p_st_ativa IN CHAR, p_nm_servico IN VARCHAR2,
        p_inclui_clinica IN BOOLEAN DEFAULT FALSE, p_nm_clinica IN VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2 IS
        v_json VARCHAR2(4000);
    BEGIN
        v_json :=
            '{'
            ||  '"idCobranca":'     || NVL(TO_CHAR(p_id_cobranca), 'null')
            || ',"idEvento":'       || NVL(TO_CHAR(p_id_evento),   'null')
            || ',"idClinica":'      || NVL(TO_CHAR(p_id_clinica),  'null')
            || ',"idServico":'      || NVL(TO_CHAR(p_id_servico),  'null')
            || ',"servico":'        || txt_ou_null(p_nm_servico)
            || ',"valor":'          || num_json(p_vl_cobrado)
            || ',"formaPagamento":' || txt_ou_null(p_ds_forma)
            || ',"dataCobranca":'   || txt_ou_null(data_iso(p_dt_cobranca))
            || ',"ativa":'          || CASE WHEN p_st_ativa = 'S' THEN 'true' ELSE 'false' END;
        IF p_inclui_clinica THEN
            v_json := v_json || ',"nmClinica":' || txt_ou_null(p_nm_clinica);
        END IF;
        RETURN v_json || '}';
    END monta_json;

    -- Valida a clinica de uma rotina chamada pela aplicacao.
    PROCEDURE valida_clinica (p_id_clinica IN NUMBER) IS
        v_chk NUMBER;
    BEGIN
        IF p_id_clinica IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_clinica_nula, 'p_id_clinica e obrigatorio');
        END IF;
        BEGIN
            SELECT ID_CLINICA INTO v_chk
              FROM CLINICA
             WHERE ID_CLINICA = p_id_clinica AND ST_ATIVA = 'S';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_clinica_inexistente,
                    'clinica inexistente ou inativa: ' || p_id_clinica);
        END;
    END valida_clinica;

    -- Array de cobrancas ativas, um elemento por linha. p_id_clinica NULL = todas
    -- (so o exportar_todas passa NULL; o listar_json valida antes).
    PROCEDURE gera_array (p_id_clinica IN NUMBER, p_saida IN OUT NOCOPY CLOB) IS
        v_primeiro BOOLEAN := TRUE;
        CURSOR c_cob IS
            SELECT c.ID_COBRANCA, c.ID_EVENTO_CLINICO, c.ID_CLINICA,
                   c.ID_SERVICO_PRECO, c.VL_COBRADO, c.DS_FORMA_PAGAMENTO,
                   c.DT_COBRANCA, c.ST_ATIVA,
                   cl.NM_CLINICA, sp.NM_SERVICO
              FROM COBRANCA           c
              JOIN CLINICA            cl ON cl.ID_CLINICA       = c.ID_CLINICA
              LEFT JOIN SERVICO_PRECO sp ON sp.ID_SERVICO_PRECO = c.ID_SERVICO_PRECO
             WHERE c.ST_ATIVA = 'S'
               AND (p_id_clinica IS NULL OR c.ID_CLINICA = p_id_clinica)
             ORDER BY c.ID_CLINICA, c.ID_COBRANCA;
    BEGIN
        anexa(p_saida, '[');
        FOR r IN c_cob LOOP
            IF NOT v_primeiro THEN
                anexa(p_saida, ',' || CHR(10));   -- um elemento por linha
            END IF;
            anexa(p_saida, monta_json(r.ID_COBRANCA, r.ID_EVENTO_CLINICO, r.ID_CLINICA,
                                      r.ID_SERVICO_PRECO, r.VL_COBRADO, r.DS_FORMA_PAGAMENTO,
                                      r.DT_COBRANCA, r.ST_ATIVA, r.NM_SERVICO,
                                      TRUE, r.NM_CLINICA));
            v_primeiro := FALSE;
        END LOOP;
        anexa(p_saida, ']');
    END gera_array;

    -- ------------------------------------------------------------ rotinas publicas

    FUNCTION fn_cobranca_json (
        p_id_cobranca IN NUMBER,
        p_id_evento   IN NUMBER,
        p_id_clinica  IN NUMBER,
        p_id_servico  IN NUMBER,
        p_vl_cobrado  IN NUMBER,
        p_ds_forma    IN VARCHAR2,
        p_dt_cobranca IN TIMESTAMP,
        p_st_ativa    IN CHAR
    ) RETURN VARCHAR2 IS
        c_fn         CONSTANT VARCHAR2(30) := 'FN_COBRANCA_JSON';
        v_nm_servico SERVICO_PRECO.NM_SERVICO%TYPE;
        v_msg        VARCHAR2(2000);
        v_cod        NUMBER;
        v_reg        BOOLEAN;
    BEGIN
        -- Nome do servico buscado AQUI (funcao autocontida). p_id_servico nulo =>
        -- nao busca => "servico":null.
        IF p_id_servico IS NOT NULL THEN
            SELECT NM_SERVICO INTO v_nm_servico
              FROM SERVICO_PRECO
             WHERE ID_SERVICO_PRECO = p_id_servico;
        END IF;

        RETURN monta_json(p_id_cobranca, p_id_evento, p_id_clinica, p_id_servico,
                          p_vl_cobrado, p_ds_forma, p_dt_cobranca, p_st_ativa, v_nm_servico);
    EXCEPTION
        -- Excecao 1: p_id_servico informado mas inexistente em SERVICO_PRECO.
        WHEN NO_DATA_FOUND THEN
            v_reg := log_seguro(c_fn, 100, 'NO_DATA_FOUND: servico inexistente em SERVICO_PRECO',
                                'idCobranca=' || NVL(TO_CHAR(p_id_cobranca), 'null')
                                || ' idServico=' || NVL(TO_CHAR(p_id_servico), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] NO_DATA_FOUND: servico ' || p_id_servico || ' inexistente.');
            RETURN '{"erro":"NO_DATA_FOUND","idCobranca":' || NVL(TO_CHAR(p_id_cobranca), 'null')
                   || ',"detalhe":"servico inexistente"}';
        -- Excecao 2: estouro do VARCHAR2 de retorno / conversao invalida.
        WHEN VALUE_ERROR THEN
            v_msg := SQLERRM;
            v_reg := log_seguro(c_fn, -6502, 'VALUE_ERROR: ' || SUBSTR(v_msg, 1, 400),
                                'idCobranca=' || NVL(TO_CHAR(p_id_cobranca), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] VALUE_ERROR: ' || v_msg);
            RETURN '{"erro":"VALUE_ERROR","idCobranca":' || NVL(TO_CHAR(p_id_cobranca), 'null') || '}';
        -- Excecao 3: qualquer outra falha. OBRIGATORIA (funcao chamada pela
        -- trigger): devolve fallback, NUNCA propaga.
        WHEN OTHERS THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            v_reg := log_seguro(c_fn, v_cod, 'OTHERS: ' || SUBSTR(v_msg, 1, 400),
                                'idCobranca=' || NVL(TO_CHAR(p_id_cobranca), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] OTHERS (' || v_cod || '): ' || v_msg);
            RETURN '{"erro":"OTHERS","idCobranca":' || NVL(TO_CHAR(p_id_cobranca), 'null')
                   || ',"sqlcode":' || v_cod || '}';
    END fn_cobranca_json;

    PROCEDURE prc_listar_cobrancas_json (p_id_clinica IN NUMBER DEFAULT NULL) IS
        c_proc          CONSTANT VARCHAR2(30) := 'PRC_LISTAR_COBRANCAS_JSON';
        v_cod           NUMBER;
        v_msg           VARCHAR2(2000);
        v_chk           NUMBER;
        v_qtd           NUMBER := 0;
        v_clinica_atual NUMBER := NULL;
        v_json          VARCHAR2(4000);
        v_reg           BOOLEAN;

        CURSOR c_cob IS
            SELECT c.ID_COBRANCA, c.ID_EVENTO_CLINICO, c.ID_CLINICA,
                   c.ID_SERVICO_PRECO, c.VL_COBRADO, c.DS_FORMA_PAGAMENTO,
                   c.DT_COBRANCA, c.ST_ATIVA,
                   cl.NM_CLINICA,
                   sp.NM_SERVICO
              FROM COBRANCA           c
              JOIN CLINICA            cl ON cl.ID_CLINICA       = c.ID_CLINICA
              LEFT JOIN SERVICO_PRECO sp ON sp.ID_SERVICO_PRECO = c.ID_SERVICO_PRECO
             WHERE c.ST_ATIVA = 'S'
               AND (p_id_clinica IS NULL OR c.ID_CLINICA = p_id_clinica)
             ORDER BY cl.NM_CLINICA, c.ID_COBRANCA;
    BEGIN
        -- Valida o filtro ANTES de abrir o cursor (dispara NO_DATA_FOUND).
        IF p_id_clinica IS NOT NULL THEN
            SELECT ID_CLINICA INTO v_chk
              FROM CLINICA
             WHERE ID_CLINICA = p_id_clinica AND ST_ATIVA = 'S';
        END IF;

        DBMS_OUTPUT.PUT_LINE('==== PRC_LISTAR_COBRANCAS_JSON (clinica: '
            || NVL(TO_CHAR(p_id_clinica), 'TODAS') || ') ====');

        FOR r IN c_cob LOOP
            IF v_clinica_atual IS NULL OR v_clinica_atual <> r.ID_CLINICA THEN
                v_clinica_atual := r.ID_CLINICA;
                DBMS_OUTPUT.PUT_LINE('-- Clinica: ' || r.NM_CLINICA || ' (id ' || r.ID_CLINICA || ') --');
            END IF;

            v_json := fn_cobranca_json(
                p_id_cobranca => r.ID_COBRANCA,
                p_id_evento   => r.ID_EVENTO_CLINICO,
                p_id_clinica  => r.ID_CLINICA,
                p_id_servico  => r.ID_SERVICO_PRECO,
                p_vl_cobrado  => r.VL_COBRADO,
                p_ds_forma    => r.DS_FORMA_PAGAMENTO,
                p_dt_cobranca => r.DT_COBRANCA,
                p_st_ativa    => r.ST_ATIVA
            );

            DBMS_OUTPUT.PUT_LINE('  [' || NVL(r.NM_SERVICO, '(avulso)') || '] ' || v_json);
            v_qtd := v_qtd + 1;
        END LOOP;

        IF v_qtd = 0 THEN
            RAISE NO_DATA_FOUND;
        END IF;

        DBMS_OUTPUT.PUT_LINE('==== ' || v_qtd || ' cobranca(s) serializada(s) ====');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            v_reg := log_seguro(c_proc, NVL(v_cod, 100),
                    'NO_DATA_FOUND: clinica inexistente/inativa ou sem cobrancas. ' || SUBSTR(v_msg, 1, 400),
                    'p_id_clinica=' || NVL(TO_CHAR(p_id_clinica), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_proc || '] NO_DATA_FOUND -- ' || msg_reg(v_reg));
        WHEN VALUE_ERROR THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            v_reg := log_seguro(c_proc, -6502, 'VALUE_ERROR: ' || SUBSTR(v_msg, 1, 400),
                    'p_id_clinica=' || NVL(TO_CHAR(p_id_clinica), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_proc || '] VALUE_ERROR -- ' || msg_reg(v_reg));
        WHEN OTHERS THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            v_reg := log_seguro(c_proc, v_cod, 'OTHERS: ' || SUBSTR(v_msg, 1, 400),
                    'p_id_clinica=' || NVL(TO_CHAR(p_id_clinica), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_proc || '] OTHERS (' || v_cod || ') -- ' || msg_reg(v_reg));
    END prc_listar_cobrancas_json;

    PROCEDURE prc_relatorio_cobrancas (p_id_clinica IN NUMBER DEFAULT NULL) IS
        c_proc  CONSTANT VARCHAR2(30) := 'PRC_RELATORIO_COBRANCAS';
        v_cod   NUMBER;
        v_msg   VARCHAR2(2000);
        v_chk   NUMBER;
        v_reg   BOOLEAN;

        v_soma_comb    NUMBER := 0;   -- acumulador da combinacao (clinica, forma)
        v_sub_clinica  NUMBER := 0;   -- acumulador do subtotal da clinica
        v_total_geral  NUMBER := 0;   -- acumulador do total geral
        v_cli_ant      NUMBER;
        v_forma_ant    VARCHAR2(40);
        v_primeira     BOOLEAN := TRUE;
        v_qtd          PLS_INTEGER := 0;

        CURSOR c_det IS
            SELECT c.ID_CLINICA                                       AS id_clinica,
                   COALESCE(c.DS_FORMA_PAGAMENTO, '(nao informado)')  AS forma,
                   c.VL_COBRADO                                       AS valor
              FROM COBRANCA c
             WHERE c.ST_ATIVA = 'S'
               AND (p_id_clinica IS NULL OR c.ID_CLINICA = p_id_clinica)
             ORDER BY c.ID_CLINICA, COALESCE(c.DS_FORMA_PAGAMENTO, '(nao informado)');

        -- formata um numero com ponto decimal fixo (independe do NLS da sessao)
        FUNCTION val_txt (p_num IN NUMBER) RETURN VARCHAR2 IS
        BEGIN
            RETURN TO_CHAR(p_num, 'FM99999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''');
        END val_txt;

        -- linha de DETALHE: clinica (dir.) + forma (esq.) + valor (dir., col 43)
        PROCEDURE emitir_detalhe (p_cli IN NUMBER, p_forma IN VARCHAR2, p_val IN NUMBER) IS
        BEGIN
            DBMS_OUTPUT.PUT_LINE(
                LPAD(TO_CHAR(p_cli), 9) || '   ' || RPAD(p_forma, 16) || '   '
                || LPAD(val_txt(p_val), c_larg_val));
        END emitir_detalhe;

        -- linha de SUB TOTAL: rotulo ocupando o espaco das categoricas (vazias),
        -- valor no MESMO offset da coluna numerica das linhas de detalhe.
        PROCEDURE emitir_subtotal (p_val IN NUMBER) IS
        BEGIN
            DBMS_OUTPUT.PUT_LINE(
                RPAD('  Sub Total', c_larg_rot) || LPAD(val_txt(p_val), c_larg_val));
        END emitir_subtotal;

        PROCEDURE emitir_total (p_val IN NUMBER) IS
        BEGIN
            DBMS_OUTPUT.PUT_LINE(
                RPAD('Total Geral', c_larg_rot) || LPAD(val_txt(p_val), c_larg_val));
        END emitir_total;
    BEGIN
        -- valida o filtro ANTES do loop (dispara NO_DATA_FOUND)
        IF p_id_clinica IS NOT NULL THEN
            SELECT ID_CLINICA INTO v_chk
              FROM CLINICA
             WHERE ID_CLINICA = p_id_clinica AND ST_ATIVA = 'S';
        END IF;

        -- cabecalho
        DBMS_OUTPUT.PUT_LINE('==== PRC_RELATORIO_COBRANCAS (clinica: '
            || NVL(TO_CHAR(p_id_clinica), 'TODAS') || ') ====');
        DBMS_OUTPUT.PUT_LINE(LPAD('Clinica', 9) || '   ' || RPAD('Forma', 16) || '   '
            || LPAD('Valor', c_larg_val));
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 9, '-') || '   ' || RPAD('-', 16, '-') || '   '
            || RPAD('-', c_larg_val, '-'));

        FOR r IN c_det LOOP
            -- QUEBRA 1: mudou a combinacao (forma OU clinica) -> emite a combinacao acumulada
            IF NOT v_primeira AND (r.id_clinica <> v_cli_ant OR r.forma <> v_forma_ant) THEN
                emitir_detalhe(v_cli_ant, v_forma_ant, v_soma_comb);
                v_soma_comb := 0;
            END IF;

            -- QUEBRA 2: mudou a clinica -> emite o Sub Total da clinica anterior
            IF NOT v_primeira AND r.id_clinica <> v_cli_ant THEN
                emitir_subtotal(v_sub_clinica);
                v_sub_clinica := 0;
            END IF;

            -- acumula (somas manuais)
            v_soma_comb   := v_soma_comb   + r.valor;
            v_sub_clinica := v_sub_clinica + r.valor;
            v_total_geral := v_total_geral + r.valor;

            v_cli_ant   := r.id_clinica;
            v_forma_ant := r.forma;
            v_primeira  := FALSE;
            v_qtd       := v_qtd + 1;
        END LOOP;

        -- ULTIMO GRUPO: fora do loop, porque nao ha proxima iteracao para detectar a quebra
        IF v_primeira THEN
            RAISE NO_DATA_FOUND;   -- cursor vazio
        END IF;

        emitir_detalhe(v_cli_ant, v_forma_ant, v_soma_comb);   -- ultima combinacao
        emitir_subtotal(v_sub_clinica);                        -- ultimo Sub Total
        emitir_total(v_total_geral);                           -- Total Geral

        DBMS_OUTPUT.PUT_LINE('==== ' || v_qtd || ' lancamento(s) totalizado(s) ====');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            v_reg := log_seguro(c_proc, NVL(v_cod, 100),
                    'NO_DATA_FOUND: clinica inexistente/inativa ou sem cobrancas. ' || SUBSTR(v_msg, 1, 400),
                    'p_id_clinica=' || NVL(TO_CHAR(p_id_clinica), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_proc || '] NO_DATA_FOUND -- ' || msg_reg(v_reg));
        WHEN VALUE_ERROR THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            v_reg := log_seguro(c_proc, -6502, 'VALUE_ERROR: ' || SUBSTR(v_msg, 1, 400),
                    'p_id_clinica=' || NVL(TO_CHAR(p_id_clinica), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_proc || '] VALUE_ERROR -- ' || msg_reg(v_reg));
        WHEN OTHERS THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            v_reg := log_seguro(c_proc, v_cod, 'OTHERS: ' || SUBSTR(v_msg, 1, 400),
                    'p_id_clinica=' || NVL(TO_CHAR(p_id_clinica), 'null'));
            DBMS_OUTPUT.PUT_LINE('[' || c_proc || '] OTHERS (' || v_cod || ') -- ' || msg_reg(v_reg));
    END prc_relatorio_cobrancas;

    PROCEDURE listar_json (p_id_clinica IN NUMBER, p_saida OUT CLOB) IS
        c_proc CONSTANT VARCHAR2(30) := 'LISTAR_JSON';
        v_cod  NUMBER;
        v_msg  VARCHAR2(2000);
        v_reg  BOOLEAN;
    BEGIN
        valida_clinica(p_id_clinica);
        inicia_lob(p_saida);
        gera_array(p_id_clinica, p_saida);
    EXCEPTION
        WHEN OTHERS THEN
            -- SQLCODE/SQLERRM lidos ANTES de qualquer outra chamada. Loga e RELANCA:
            -- a aplicacao precisa saber que falhou (ao contrario das rotinas de demo).
            v_cod := SQLCODE; v_msg := SQLERRM;
            libera_lob(p_saida);
            v_reg := log_seguro(c_proc, v_cod, SUBSTR(v_msg, 1, 1000),
                                'p_id_clinica=' || NVL(TO_CHAR(p_id_clinica), 'null'));
            RAISE;
    END listar_json;

    PROCEDURE relatorio_json (p_id_clinica IN NUMBER, p_saida OUT CLOB) IS
        c_proc      CONSTANT VARCHAR2(30) := 'RELATORIO_JSON';
        v_cod       NUMBER;
        v_msg       VARCHAR2(2000);
        v_reg       BOOLEAN;
        v_forma_ant VARCHAR2(40);
        v_soma      NUMBER := 0;     -- acumulador da forma
        v_sub       NUMBER := 0;     -- acumulador da clinica
        v_primeira  BOOLEAN := TRUE;
        v_grupos    PLS_INTEGER := 0;

        CURSOR c_det IS
            SELECT COALESCE(c.DS_FORMA_PAGAMENTO, '(nao informado)') AS forma,
                   c.VL_COBRADO                                      AS valor
              FROM COBRANCA c
             WHERE c.ST_ATIVA = 'S'
               AND c.ID_CLINICA = p_id_clinica
             ORDER BY COALESCE(c.DS_FORMA_PAGAMENTO, '(nao informado)');

        -- um grupo (forma) por linha
        PROCEDURE emite_grupo IS
        BEGIN
            anexa(p_saida, CASE WHEN v_grupos > 0 THEN ',' END || CHR(10)
                           || '{"forma":' || txt_ou_null(v_forma_ant) || ',"total":' || soma_json(v_soma) || '}');
            v_grupos := v_grupos + 1;
        END emite_grupo;
    BEGIN
        valida_clinica(p_id_clinica);
        inicia_lob(p_saida);
        anexa(p_saida, '{"idClinica":' || TO_CHAR(p_id_clinica) || ',"grupos":[');

        FOR r IN c_det LOOP
            -- QUEBRA: mudou a forma -> emite a forma acumulada
            IF NOT v_primeira AND r.forma <> v_forma_ant THEN
                emite_grupo;
                v_soma := 0;
            END IF;
            v_soma      := v_soma + r.valor;     -- somas manuais
            v_sub       := v_sub  + r.valor;
            v_forma_ant := r.forma;
            v_primeira  := FALSE;
        END LOOP;

        -- ULTIMO GRUPO: fora do loop (nao ha proxima iteracao para detectar a quebra)
        IF NOT v_primeira THEN
            emite_grupo;
            anexa(p_saida, CHR(10));
        END IF;
        anexa(p_saida, '],"subTotal":' || soma_json(v_sub) || '}');
    EXCEPTION
        WHEN OTHERS THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            libera_lob(p_saida);
            v_reg := log_seguro(c_proc, v_cod, SUBSTR(v_msg, 1, 1000),
                                'p_id_clinica=' || NVL(TO_CHAR(p_id_clinica), 'null'));
            RAISE;
    END relatorio_json;

    PROCEDURE exportar_todas (p_saida OUT CLOB) IS
        c_proc CONSTANT VARCHAR2(30) := 'EXPORTAR_TODAS';
        v_cod  NUMBER;
        v_msg  VARCHAR2(2000);
        v_reg  BOOLEAN;
    BEGIN
        inicia_lob(p_saida);
        gera_array(NULL, p_saida);
    EXCEPTION
        WHEN OTHERS THEN
            v_cod := SQLCODE; v_msg := SQLERRM;
            libera_lob(p_saida);
            v_reg := log_seguro(c_proc, v_cod, SUBSTR(v_msg, 1, 1000), NULL);
            RAISE;
    END exportar_todas;

END PKG_COBRANCA;
/
SHOW ERRORS PACKAGE BODY PKG_COBRANCA

PROMPT === BLOCO 5: PKG_COBRANCA criado ===


-- #############################################################################
-- #  BLOCO 6 - PKG_AUDITORIA
-- #
-- #  Grava a linha de AUDITORIA_COBRANCA de uma operacao DML em COBRANCA. Quem a
-- #  chama e a TRG_AUDITORIA_COBRANCA (BLOCO 7).
-- #
-- #  *** NAO e transacao autonoma (de proposito, correcao B2-1 do G0). ***
-- #  O INSERT da auditoria fica NA TRANSACAO do DML auditado: se o DML sofre
-- #  ROLLBACK, a linha de auditoria some junto; se confirma, confirma junto. Com
-- #  PRAGMA AUTONOMOUS_TRANSACTION a auditoria sobreviveria a um ROLLBACK e
-- #  registraria uma operacao que nunca aconteceu. (O unico package autonomo
-- #  deste arquivo e o PKG_KURA_LOG.)
-- #
-- #  NAO LE COBRANCA: a trigger e FOR EACH ROW sobre COBRANCA, e ler a propria
-- #  tabela da trigger e ORA-04091 (tabela mutante). Por isso os valores
-- #  chegam como ESCALARES (:OLD / :NEW) e o JSON sai da PKG_COBRANCA.fn_cobranca_json,
-- #  que so consulta SERVICO_PRECO.
-- #
-- #  Falha de auditoria NAO e silenciada (sem WHEN OTHERS): se o INSERT em
-- #  AUDITORIA_COBRANCA falha, o DML auditado falha. Isso e proposital.
-- #  A protecao contra LOG invalido mora dentro da PKG_COBRANCA (log_seguro,
-- #  chamada dinamica do PKG_KURA_LOG).
-- #
-- #  Package SEM ESTADO e NAO SERIALLY_REUSABLE (a trigger o chama).
-- #############################################################################
PROMPT
PROMPT === BLOCO 6: PKG_AUDITORIA ===

CREATE OR REPLACE PACKAGE PKG_AUDITORIA AS
    -- Grava UMA linha em AUDITORIA_COBRANCA (usuario = USER, data = DEFAULT da coluna).
    --   p_operacao   - 'INSERT', 'UPDATE' ou 'DELETE' (a CHECK da tabela recusa outro valor)
    --   p_old_*      - os 8 escalares de :OLD (ignorados em INSERT; DS_VALORES_OLD fica nulo)
    --   p_new_*      - os 8 escalares de :NEW (ignorados em DELETE; DS_VALORES_NEW fica nulo)
    -- Na MESMA transacao do chamador (nao autonoma). Nao le COBRANCA.
    PROCEDURE registrar_cobranca (
        p_operacao        IN VARCHAR2,
        p_old_id_cobranca IN NUMBER,
        p_old_id_evento   IN NUMBER,
        p_old_id_clinica  IN NUMBER,
        p_old_id_servico  IN NUMBER,
        p_old_vl_cobrado  IN NUMBER,
        p_old_ds_forma    IN VARCHAR2,
        p_old_dt_cobranca IN TIMESTAMP,
        p_old_st_ativa    IN CHAR,
        p_new_id_cobranca IN NUMBER,
        p_new_id_evento   IN NUMBER,
        p_new_id_clinica  IN NUMBER,
        p_new_id_servico  IN NUMBER,
        p_new_vl_cobrado  IN NUMBER,
        p_new_ds_forma    IN VARCHAR2,
        p_new_dt_cobranca IN TIMESTAMP,
        p_new_st_ativa    IN CHAR
    );
END PKG_AUDITORIA;
/
SHOW ERRORS PACKAGE PKG_AUDITORIA

CREATE OR REPLACE PACKAGE BODY PKG_AUDITORIA AS

    PROCEDURE registrar_cobranca (
        p_operacao        IN VARCHAR2,
        p_old_id_cobranca IN NUMBER,
        p_old_id_evento   IN NUMBER,
        p_old_id_clinica  IN NUMBER,
        p_old_id_servico  IN NUMBER,
        p_old_vl_cobrado  IN NUMBER,
        p_old_ds_forma    IN VARCHAR2,
        p_old_dt_cobranca IN TIMESTAMP,
        p_old_st_ativa    IN CHAR,
        p_new_id_cobranca IN NUMBER,
        p_new_id_evento   IN NUMBER,
        p_new_id_clinica  IN NUMBER,
        p_new_id_servico  IN NUMBER,
        p_new_vl_cobrado  IN NUMBER,
        p_new_ds_forma    IN VARCHAR2,
        p_new_dt_cobranca IN TIMESTAMP,
        p_new_st_ativa    IN CHAR
    ) IS
        v_old VARCHAR2(4000);
        v_new VARCHAR2(4000);
        v_id  NUMBER;
    BEGIN
        -- :OLD nao existe em INSERT
        IF p_operacao IN ('UPDATE', 'DELETE') THEN
            v_old := PKG_COBRANCA.fn_cobranca_json(
                p_old_id_cobranca, p_old_id_evento, p_old_id_clinica, p_old_id_servico,
                p_old_vl_cobrado, p_old_ds_forma, p_old_dt_cobranca, p_old_st_ativa);
        END IF;

        -- :NEW nao existe em DELETE
        IF p_operacao IN ('INSERT', 'UPDATE') THEN
            v_new := PKG_COBRANCA.fn_cobranca_json(
                p_new_id_cobranca, p_new_id_evento, p_new_id_clinica, p_new_id_servico,
                p_new_vl_cobrado, p_new_ds_forma, p_new_dt_cobranca, p_new_st_ativa);
        END IF;

        -- PK do registro afetado (em DELETE so ha o lado OLD)
        v_id := NVL(p_new_id_cobranca, p_old_id_cobranca);

        -- ID_AUDITORIA e DT_OPERACAO vem dos DEFAULT da tabela
        INSERT INTO AUDITORIA_COBRANCA (NM_USUARIO, DS_OPERACAO, ID_COBRANCA, DS_VALORES_OLD, DS_VALORES_NEW)
        VALUES (USER, p_operacao, v_id, v_old, v_new);
    END registrar_cobranca;

END PKG_AUDITORIA;
/
SHOW ERRORS PACKAGE BODY PKG_AUDITORIA

PROMPT === BLOCO 6: PKG_AUDITORIA criado ===


-- #############################################################################
-- #  BLOCO 7 - TRG_AUDITORIA_COBRANCA FINA
-- #
-- #  Mesmo nome da trigger da Sprint 3, substituida por CREATE OR REPLACE (nunca
-- #  DROP): nao ha instante em que COBRANCA fique sem trigger ou com trigger
-- #  invalida (a da Sprint 3 chamava a FN_COBRANCA_JSON standalone, que o BLOCO 9
-- #  remove DEPOIS desta troca).
-- #
-- #  POR QUE A TRIGGER DELEGA: trigger NAO e membro de package no Oracle - e uma
-- #  unidade propria (CREATE TRIGGER). A lista do que um package contem (tipos,
-- #  variaveis, constantes, subprogramas, cursores, excecoes) nao inclui trigger:
-- #  https://docs.oracle.com/en/database/oracle/oracle-database/21/lnpls/plsql-packages.html
-- #  (secao "What is a Package?", acesso em 2026-10-28). E a propria Oracle
-- #  recomenda o padrao: "If the logic for your trigger requires much more than
-- #  60 lines of PL/SQL source text, then put most of the source text in a stored
-- #  subprogram and invoke the subprogram from the trigger"
-- #  (https://docs.oracle.com/en/database/oracle/oracle-database/21/lnpls/plsql-triggers.html).
-- #  Entao a trigger so identifica o DML (INSERTING/UPDATING/DELETING) e faz UMA
-- #  chamada ao PKG_AUDITORIA; a regra mora no package.
-- #
-- #  Sem bloco EXCEPTION, como na Sprint 3: falha de auditoria nao pode ser
-- #  silenciada. O package de LOG invalido (spec ou body) nao derruba o DML:
-- #  o log_seguro o chama por SQL dinamico (I-1 da G2; ver BLOCO 5).
-- #
-- #  RISCO CONHECIDO (documentado de proposito): se o PKG_AUDITORIA (ou o
-- #  PKG_COBRANCA) for REMOVIDO ou ficar INVALID e nao recompilar, todo DML em
-- #  COBRANCA falha com ORA-04098/ORA-04063 - e a aplicacao nao consegue lancar
-- #  cobranca. Saida de emergencia: 2TDSPF_2026_Packages_Remover.sql (derruba a
-- #  trigger primeiro).
-- #############################################################################
PROMPT
PROMPT === BLOCO 7: trigger de auditoria fina ===

CREATE OR REPLACE TRIGGER TRG_AUDITORIA_COBRANCA
AFTER INSERT OR UPDATE OR DELETE ON COBRANCA
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        PKG_AUDITORIA.registrar_cobranca('INSERT',
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            :NEW.ID_COBRANCA, :NEW.ID_EVENTO_CLINICO, :NEW.ID_CLINICA, :NEW.ID_SERVICO_PRECO,
            :NEW.VL_COBRADO, :NEW.DS_FORMA_PAGAMENTO, :NEW.DT_COBRANCA, :NEW.ST_ATIVA);
    ELSIF UPDATING THEN
        PKG_AUDITORIA.registrar_cobranca('UPDATE',
            :OLD.ID_COBRANCA, :OLD.ID_EVENTO_CLINICO, :OLD.ID_CLINICA, :OLD.ID_SERVICO_PRECO,
            :OLD.VL_COBRADO, :OLD.DS_FORMA_PAGAMENTO, :OLD.DT_COBRANCA, :OLD.ST_ATIVA,
            :NEW.ID_COBRANCA, :NEW.ID_EVENTO_CLINICO, :NEW.ID_CLINICA, :NEW.ID_SERVICO_PRECO,
            :NEW.VL_COBRADO, :NEW.DS_FORMA_PAGAMENTO, :NEW.DT_COBRANCA, :NEW.ST_ATIVA);
    ELSE
        PKG_AUDITORIA.registrar_cobranca('DELETE',
            :OLD.ID_COBRANCA, :OLD.ID_EVENTO_CLINICO, :OLD.ID_CLINICA, :OLD.ID_SERVICO_PRECO,
            :OLD.VL_COBRADO, :OLD.DS_FORMA_PAGAMENTO, :OLD.DT_COBRANCA, :OLD.ST_ATIVA,
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    END IF;
END TRG_AUDITORIA_COBRANCA;
/
SHOW ERRORS TRIGGER TRG_AUDITORIA_COBRANCA

PROMPT === BLOCO 7: TRG_AUDITORIA_COBRANCA criada ===


PROMPT
PROMPT === BLOCO 8: verificacao (recompila e confere objetos e DEPENDENTES) ===
-- Recompila os objetos deste arquivo e TODOS os que dependem deles (direta ou
-- transitivamente, via user_dependencies - a trigger de COBRANCA inclusive) e
-- exige que nenhum fique INVALID nem tenha erro de compilacao. Motivo (RE-I1 da
-- re-G2): CREATE OR REPLACE so preserva um dependente se a versao nova compilar;
-- e depois de reinstalar a versao correta o dependente podia continuar INVALID
-- (so seria recompilado no proximo uso - para uma trigger, no proximo INSERT em
-- COBRANCA, que falharia). Aqui ele e recompilado AGORA, e conferido.
-- Qualquer pendencia => ORA-20901 => o script para (EXIT=165) antes do BLOCO 9.
DECLARE
    v_lista  VARCHAR2(4000);
    v_falhas VARCHAR2(4000);
    v_qtd    PLS_INTEGER;
    v_ext    PLS_INTEGER := 0;

    -- objetos DESTE arquivo (nomes), para o ponto de partida da busca de dependentes
    CURSOR c_alvos IS
        SELECT DISTINCT name AS nome,
               CASE WHEN type LIKE 'PACKAGE%' THEN 'PACKAGE' ELSE type END AS tipo
          FROM (SELECT object_name AS name, object_type AS type
                  FROM user_objects
                 WHERE object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA',
                                       'TRG_AUDITORIA_COBRANCA')
                UNION
                SELECT d.name, d.type
                  FROM user_dependencies d
                 WHERE d.type IN ('PACKAGE', 'PACKAGE BODY', 'FUNCTION', 'PROCEDURE', 'TRIGGER', 'VIEW')
                 START WITH d.referenced_owner = USER
                        AND d.referenced_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA',
                                                  'PKG_AUDITORIA', 'AUDITORIA_COBRANCA',
                                                  'SEQ_AUDITORIA_COBRANCA')
                 CONNECT BY NOCYCLE d.referenced_owner = USER
                        AND d.referenced_name = PRIOR d.name
                        AND d.referenced_type = PRIOR d.type)
         WHERE type IN ('PACKAGE', 'PACKAGE BODY', 'FUNCTION', 'PROCEDURE', 'TRIGGER', 'VIEW');

    PROCEDURE compila (p_tipo IN VARCHAR2, p_nome IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'ALTER ' || p_tipo || ' "' || p_nome || '" COMPILE';
    EXCEPTION
        WHEN OTHERS THEN
            v_falhas := SUBSTR(v_falhas || CHR(10) || '  - ' || p_tipo || ' ' || p_nome || ': ' || SQLERRM, 1, 2000);
    END compila;
BEGIN
    -- 2 passadas: a ordem de compilacao entre dependentes nao precisa ser calculada
    FOR passada IN 1 .. 2 LOOP
        FOR a IN c_alvos LOOP
            compila(a.tipo, a.nome);
        END LOOP;
    END LOOP;

    FOR a IN c_alvos LOOP
        IF a.nome NOT IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA', 'TRG_AUDITORIA_COBRANCA') THEN
            v_ext := v_ext + 1;
            DBMS_OUTPUT.PUT_LINE('dependente externo verificado: ' || a.tipo || ' ' || a.nome);
        END IF;
    END LOOP;

    FOR r IN (SELECT o.object_name || ' (' || o.object_type || ') ' || o.status AS d
                FROM user_objects o
               WHERE o.status <> 'VALID'
                 AND (o.object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA',
                                        'TRG_AUDITORIA_COBRANCA', 'AUDITORIA_COBRANCA',
                                        'SEQ_AUDITORIA_COBRANCA', 'IDX_AUDITORIA_COB_DATA',
                                        'IDX_AUDITORIA_COB_REG')
                      OR o.object_name IN (SELECT nome FROM (
                              SELECT DISTINCT d.name AS nome
                                FROM user_dependencies d
                               START WITH d.referenced_owner = USER
                                      AND d.referenced_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA',
                                                                'PKG_AUDITORIA', 'AUDITORIA_COBRANCA',
                                                                'SEQ_AUDITORIA_COBRANCA')
                               CONNECT BY NOCYCLE d.referenced_owner = USER
                                      AND d.referenced_name = PRIOR d.name
                                      AND d.referenced_type = PRIOR d.type)))
              UNION ALL
              SELECT e.name || ' (' || e.type || ') erro na linha ' || e.line || ': '
                     || SUBSTR(REPLACE(e.text, CHR(10), ' '), 1, 160)
                FROM user_errors e
               WHERE e.attribute = 'ERROR'
                 AND (e.name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA',
                                 'TRG_AUDITORIA_COBRANCA')
                      OR e.name IN (SELECT nome FROM (
                              SELECT DISTINCT d.name AS nome
                                FROM user_dependencies d
                               START WITH d.referenced_owner = USER
                                      AND d.referenced_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA',
                                                                'PKG_AUDITORIA', 'AUDITORIA_COBRANCA',
                                                                'SEQ_AUDITORIA_COBRANCA')
                               CONNECT BY NOCYCLE d.referenced_owner = USER
                                      AND d.referenced_name = PRIOR d.name
                                      AND d.referenced_type = PRIOR d.type)))) LOOP
        v_lista := SUBSTR(v_lista || CHR(10) || '  - ' || r.d, 1, 3000);
    END LOOP;

    IF v_falhas IS NOT NULL THEN
        v_lista := SUBSTR(v_lista || CHR(10) || '  - o ALTER ... COMPILE falhou em:' || v_falhas, 1, 3500);
    END IF;

    SELECT COUNT(*) INTO v_qtd
      FROM user_objects
     WHERE object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA')
       AND object_type IN ('PACKAGE', 'PACKAGE BODY')
       AND status = 'VALID';
    IF v_qtd <> 8 THEN
        v_lista := v_lista || CHR(10) || '  - esperados 8 objetos de package VALID (4 specs + 4 bodies), encontrados ' || v_qtd;
    END IF;

    SELECT COUNT(*) INTO v_qtd
      FROM user_objects
     WHERE object_name = 'TRG_AUDITORIA_COBRANCA' AND object_type = 'TRIGGER' AND status = 'VALID';
    IF v_qtd <> 1 THEN
        v_lista := v_lista || CHR(10) || '  - esperada a TRG_AUDITORIA_COBRANCA VALID, encontradas ' || v_qtd;
    END IF;

    IF v_lista IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20901,
            SUBSTR('BLOCO 8: objeto(s) invalido(s) ou com erro de compilacao:' || v_lista, 1, 2000));
    END IF;
    DBMS_OUTPUT.PUT_LINE('verificacao OK: 4 packages (spec + body) e TRG_AUDITORIA_COBRANCA VALID, '
        || v_ext || ' dependente(s) externo(s) recompilado(s) e VALID, 0 erros de compilacao, AUDITORIA_COBRANCA VALID.');
END;
/

-- #############################################################################
-- #  BLOCO 9 - REMOVE AS STANDALONE DE COBRANCA DA SPRINT 3
-- #
-- #  So chega aqui se o BLOCO 8 passou: os packages e a trigger fina existem e
-- #  estao VALID, e a trigger ja NAO chama a FN_COBRANCA_JSON standalone. Remove
-- #  FN_COBRANCA_JSON, PRC_LISTAR_COBRANCAS_JSON e PRC_RELATORIO_COBRANCAS (as
-- #  versoes novas vivem no PKG_COBRANCA). O DROP ignora ORA-04043 (no schema do
-- #  aplicativo elas nunca existiram); qualquer outro erro e propagado.
-- #
-- #  GUARDA: se ALGUM objeto (fora as proprias 3) ainda depender da
-- #  FN_COBRANCA_JSON standalone, o script PARA (ORA-20903 -> EXIT=167) em vez de
-- #  invalidar esse objeto.
-- #############################################################################
PROMPT
PROMPT === BLOCO 9: remocao das standalone de cobranca da Sprint 3 ===
DECLARE
    v_dep VARCHAR2(2000);

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
    FOR r IN (SELECT name || ' (' || type || ')' AS d
                FROM user_dependencies
               WHERE referenced_owner = USER
                 AND referenced_name = 'FN_COBRANCA_JSON'
                 AND referenced_type = 'FUNCTION'
                 AND name NOT IN ('PRC_LISTAR_COBRANCAS_JSON', 'PRC_RELATORIO_COBRANCAS')) LOOP
        v_dep := SUBSTR(v_dep || CHR(10) || '  - ' || r.d, 1, 1500);
    END LOOP;
    IF v_dep IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20903,
            'BLOCO 9: ainda ha objeto(s) dependendo da FN_COBRANCA_JSON standalone; nada foi removido:' || v_dep);
    END IF;
    remove('PROCEDURE', 'PRC_LISTAR_COBRANCAS_JSON');
    remove('PROCEDURE', 'PRC_RELATORIO_COBRANCAS');
    remove('FUNCTION',  'FN_COBRANCA_JSON');
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
-- #  A demonstracao grava 6 linhas sinteticas em LOG_ERRO por execucao (sem dado
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

    -- (c2) RE-M1: 'a' + 1500 x c-cedilha (3001 bytes). SUBSTRB(..., 1, 2000) daria
    -- 'a' + 999 c-cedilha + UM ESPACO no lugar do caractere partido (2000 bytes,
    -- 1001 caracteres); corta_bytes recua ate o ultimo caractere inteiro (1999 bytes,
    -- 1000 caracteres). Um texto de so c-cedilha (caso c) nao distingue os dois.
    v_antes := n_log;
    v_texto := 'a' || RPAD(UNISTR('\00E7'), 1500, UNISTR('\00E7'));
    PKG_KURA_LOG.registrar_erro('DEMO_S4_TRUNCAMENTO', -20996, v_texto, 'len=1501');
    confere('D.2c2 linhas novas', '1', TO_CHAR(n_log - v_antes));
    r := ultima;
    confere('D.2c2 bytes da mensagem (1999: nao completa com espaco)', '1999', TO_CHAR(LENGTHB(r.DS_MENSAGEM_ERRO)));
    confere('D.2c2 caracteres da mensagem', '1000', TO_CHAR(LENGTH(r.DS_MENSAGEM_ERRO)));
    confere('D.2c2 nao termina em espaco', 'NAO', CASE WHEN SUBSTR(r.DS_MENSAGEM_ERRO, -1) = ' ' THEN 'SIM' ELSE 'NAO' END);

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
    confere('D.2 total de linhas ate aqui (a, b, c, c2)', '4', TO_CHAR(n_log));

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
    confere('D.3 o log autonomo sobrevive ao ROLLBACK (a, b, c, c2 + este)', '5', TO_CHAR(n_log));

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
    confere('D.6 linhas gravadas por esta execucao (a, b, c, c2, D.3, D.4)', '6', TO_CHAR(n_log));
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


-- #############################################################################
-- #  DEMONSTRACAO (S4-DB-03) - cobranca e auditoria
-- #
-- #  Mesmo padrao da demonstracao anterior: cada caso imprime "OK: <caso>" ou
-- #  "FALHOU: <caso> (esperado X, obtido Y)", o bloco termina com
-- #  "RESUMO: n OK, m FALHOU" e, se m > 0, o script encerra com erro (EXIT=166).
-- #  "PULADO" = pre-condicao de dado ausente neste schema (nao conta como OK).
-- #
-- #  NAO DEIXA DADO DE PRODUTO: todo DML em COBRANCA e SERVICO_PRECO e desfeito
-- #  por ROLLBACK (e a prova de que a auditoria acompanha a transacao do DML).
-- #  As unicas linhas que sobram sao as de LOG_ERRO (log autonomo, sinteticas,
-- #  sem dado pessoal). As sequences consomem valores. Premissa: nenhuma outra
-- #  sessao grava COBRANCA durante a demonstracao (as contagens comparam leituras
-- #  feitas em instantes proximos).
-- #############################################################################
PROMPT
PROMPT ###################  DEMO S4-DB-03: INICIO  ###################
DECLARE
    c_servico CONSTANT VARCHAR2(100) := 'Banho "Premium" \ DEMO S4-DB-03';
    c_esc     CONSTANT VARCHAR2(100) := 'Banho \"Premium\" \\ DEMO S4-DB-03';   -- como deve sair no JSON

    v_base    LOG_ERRO.ID_LOG%TYPE;
    v_ok      PLS_INTEGER := 0;
    v_falhou  PLS_INTEGER := 0;
    v_pulado  PLS_INTEGER := 0;
    v_clin    NUMBER;
    v_outra   NUMBER;
    v_vazia   NUMBER;
    v_evento  NUMBER;
    v_c       CLOB;
    v_c2      CLOB;
    v_c3      CLOB;
    v_c4      CLOB;
    v_n       NUMBER;
    v_n2      NUMBER;
    v_ref     NUMBER;
    v_s       VARCHAR2(4000);
    v_cod     VARCHAR2(60);
    v_antes   PLS_INTEGER;
    v_serv    NUMBER;
    v_id      NUMBER;
    v_id2     NUMBER;
    v_id3     NUMBER;
    v_cob_ant PLS_INTEGER;
    v_aud_ant PLS_INTEGER;
    v_srv_ant PLS_INTEGER;
    v_n_base  PLS_INTEGER;
    v_tx      VARCHAR2(200);
    v_terr    VARCHAR2(100);
    v_numch   VARCHAR2(10);
    v_fn_am   VARCHAR2(4000);
    v_old     VARCHAR2(4000);
    v_new     VARCHAR2(4000);
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

    PROCEDURE pula (p_caso IN VARCHAR2, p_motivo IN VARCHAR2) IS
    BEGIN
        v_pulado := v_pulado + 1;
        DBMS_OUTPUT.PUT_LINE('PULADO: ' || p_caso || ' (' || p_motivo || ')');
    END pula;

    FUNCTION sn (p_bool IN BOOLEAN) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN p_bool THEN 'SIM' ELSE 'NAO' END;
    END sn;

    -- linhas de LOG_ERRO gravadas por ESTA execucao pelo PKG_COBRANCA
    FUNCTION n_log RETURN PLS_INTEGER IS
        n PLS_INTEGER;
    BEGIN
        SELECT COUNT(*) INTO n FROM LOG_ERRO
         WHERE ID_LOG > v_base AND NM_USUARIO = USER AND NM_PROCEDURE LIKE 'PKG_COBRANCA.%';
        RETURN n;
    END n_log;

    FUNCTION ultima RETURN LOG_ERRO%ROWTYPE IS
        v LOG_ERRO%ROWTYPE;
    BEGIN
        SELECT * INTO v FROM LOG_ERRO
         WHERE ID_LOG = (SELECT MAX(ID_LOG) FROM LOG_ERRO
                          WHERE ID_LOG > v_base AND NM_USUARIO = USER AND NM_PROCEDURE LIKE 'PKG_COBRANCA.%');
        RETURN v;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN v;
    END ultima;

    -- ocorrencias de p_pad dentro do CLOB
    FUNCTION conta (p_lob IN CLOB, p_pad IN VARCHAR2) RETURN NUMBER IS
        n   NUMBER := 0;
        pos NUMBER := 1;
    BEGIN
        IF p_lob IS NULL THEN RETURN 0; END IF;
        LOOP
            pos := DBMS_LOB.INSTR(p_lob, p_pad, pos);
            EXIT WHEN pos = 0;
            n   := n + 1;
            pos := pos + LENGTH(p_pad);
        END LOOP;
        RETURN n;
    END conta;

    FUNCTION tem (p_lob IN CLOB, p_pad IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN p_lob IS NOT NULL AND DBMS_LOB.INSTR(p_lob, p_pad) > 0;
    END tem;

    PROCEDURE libera (p_lob IN OUT CLOB) IS
    BEGIN
        IF p_lob IS NOT NULL THEN
            IF DBMS_LOB.ISTEMPORARY(p_lob) = 1 THEN DBMS_LOB.FREETEMPORARY(p_lob); END IF;
        END IF;
        p_lob := NULL;
    END libera;

    -- chama uma rotina da aplicacao e devolve o SQLCODE (ou 'NAO PROPAGOU')
    FUNCTION cod_listar (p_clin IN NUMBER) RETURN VARCHAR2 IS
        c CLOB;
    BEGIN
        PKG_COBRANCA.listar_json(p_clin, c);
        libera(c);
        RETURN 'NAO PROPAGOU';
    EXCEPTION
        WHEN OTHERS THEN
            RETURN TO_CHAR(SQLCODE);
    END cod_listar;

    FUNCTION cod_relatorio (p_clin IN NUMBER) RETURN VARCHAR2 IS
        c CLOB;
    BEGIN
        PKG_COBRANCA.relatorio_json(p_clin, c);
        libera(c);
        RETURN 'NAO PROPAGOU';
    EXCEPTION
        WHEN OTHERS THEN
            RETURN TO_CHAR(SQLCODE);
    END cod_relatorio;

    FUNCTION fmt (p_num IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_num, 'FM9999999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''');
    END fmt;

    -- soma INDEPENDENTE (laco simples sobre as linhas da clinica, sem grupos)
    FUNCTION soma_clinica (p_clin IN NUMBER) RETURN NUMBER IS
        v NUMBER := 0;
    BEGIN
        FOR x IN (SELECT VL_COBRADO FROM COBRANCA WHERE ID_CLINICA = p_clin AND ST_ATIVA = 'S') LOOP
            v := v + x.VL_COBRADO;
        END LOOP;
        RETURN v;
    END soma_clinica;

    FUNCTION n_ativas (p_clin IN NUMBER) RETURN NUMBER IS
        n NUMBER;
    BEGIN
        SELECT COUNT(*) INTO n FROM COBRANCA WHERE ID_CLINICA = p_clin AND ST_ATIVA = 'S';
        RETURN n;
    END n_ativas;

    PROCEDURE restaura_nls IS
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_TERRITORY = ''' || v_terr || '''';
    END restaura_nls;
BEGIN
    SELECT NVL(MAX(ID_LOG), 0) INTO v_base FROM LOG_ERRO;
    DBMS_OUTPUT.PUT_LINE('LOG_ERRO: maior ID_LOG antes da demo = ' || v_base);

    -- Ancora: clinica + evento ja existentes (reaproveita um par de COBRANCA, que
    -- garante a FK; sem cobranca, tenta um evento e uma clinica quaisquer).
    BEGIN
        SELECT ID_CLINICA, ID_EVENTO_CLINICO INTO v_clin, v_evento
          FROM (SELECT ID_CLINICA, ID_EVENTO_CLINICO FROM COBRANCA WHERE ST_ATIVA = 'S' ORDER BY ID_COBRANCA)
         WHERE ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            SELECT MIN(ID_CLINICA) INTO v_clin FROM CLINICA WHERE ST_ATIVA = 'S';
            SELECT MIN(ID_EVENTO)  INTO v_evento FROM EVENTO_CLINICO;
    END;
    SELECT MIN(ID_CLINICA) INTO v_outra FROM CLINICA WHERE ST_ATIVA = 'S' AND ID_CLINICA <> NVL(v_clin, -1);
    SELECT MIN(cl.ID_CLINICA) INTO v_vazia FROM CLINICA cl
     WHERE cl.ST_ATIVA = 'S' AND NOT EXISTS (SELECT 1 FROM COBRANCA c WHERE c.ID_CLINICA = cl.ID_CLINICA);
    DBMS_OUTPUT.PUT_LINE('ancoras: clinica=' || NVL(TO_CHAR(v_clin), '(nenhuma)') || ' outra=' || NVL(TO_CHAR(v_outra), '(nenhuma)')
        || ' sem_cobranca=' || NVL(TO_CHAR(v_vazia), '(nenhuma)') || ' evento=' || NVL(TO_CHAR(v_evento), '(nenhum)'));

    -- ======================= E.1 fn_cobranca_json ============================
    DBMS_OUTPUT.PUT_LINE('---- E.1 fn_cobranca_json: caminho feliz, nulos, escape, excecoes ----');
    v_fn_am := PKG_COBRANCA.fn_cobranca_json(1, 2, 3, NULL, 12.5, 'PIX', TIMESTAMP '2026-10-28 10:11:12', 'S');
    confere('E.1a objeto completo (ponto decimal, ISO-8601, servico nulo)',
            '{"idCobranca":1,"idEvento":2,"idClinica":3,"idServico":null,"servico":null,"valor":12.50,"formaPagamento":"PIX","dataCobranca":"2026-10-28T10:11:12","ativa":true}',
            v_fn_am);
    confere('E.1b tudo nulo vira o literal null',
            '{"idCobranca":7,"idEvento":null,"idClinica":null,"idServico":null,"servico":null,"valor":0.00,"formaPagamento":null,"dataCobranca":null,"ativa":false}',
            PKG_COBRANCA.fn_cobranca_json(7, NULL, NULL, NULL, 0, NULL, NULL, 'N'));
    confere('E.1c escape: barra invertida antes da aspa',
            '{"idCobranca":8,"idEvento":null,"idClinica":null,"idServico":null,"servico":null,"valor":1.05,"formaPagamento":"a\"b\\c","dataCobranca":null,"ativa":true}',
            PKG_COBRANCA.fn_cobranca_json(8, NULL, NULL, NULL, 1.05, 'a"b\c', NULL, 'S'));
    v_antes := n_log;
    confere('E.1d servico inexistente => fallback NO_DATA_FOUND',
            '{"erro":"NO_DATA_FOUND","idCobranca":9,"detalhe":"servico inexistente"}',
            PKG_COBRANCA.fn_cobranca_json(9, NULL, NULL, -1, 1, 'PIX', NULL, 'S'));
    confere('E.1d linhas novas em LOG_ERRO', '1', TO_CHAR(n_log - v_antes));
    r := ultima;
    confere('E.1d NM_PROCEDURE', 'PKG_COBRANCA.FN_COBRANCA_JSON', r.NM_PROCEDURE);
    confere('E.1d NR_CODIGO_ERRO', '100', TO_CHAR(r.NR_CODIGO_ERRO));
    confere('E.1d DS_PARAMETROS (so ids)', 'idCobranca=9 idServico=-1', r.DS_PARAMETROS);
    v_antes := n_log;
    confere('E.1e buffer estourado => fallback VALUE_ERROR',
            '{"erro":"VALUE_ERROR","idCobranca":10}',
            PKG_COBRANCA.fn_cobranca_json(10, NULL, NULL, NULL, 1, RPAD('x', 4100, 'x'), NULL, 'S'));
    confere('E.1e linhas novas em LOG_ERRO', '1', TO_CHAR(n_log - v_antes));
    r := ultima;
    confere('E.1e NR_CODIGO_ERRO', '-6502', TO_CHAR(r.NR_CODIGO_ERRO));
    confere('E.1e DS_PARAMETROS', 'idCobranca=10', r.DS_PARAMETROS);

    IF v_clin IS NULL THEN
        pula('E.2 a E.5', 'nenhuma clinica ativa neste schema');
    ELSE
        -- ======================= E.2 listar_json (somente leitura) ===========
        DBMS_OUTPUT.PUT_LINE('---- E.2 listar_json / relatorio_json / exportar_todas (leitura) ----');
        PKG_COBRANCA.listar_json(v_clin, v_c);
        v_n := conta(v_c, '"idCobranca":');
        confere('E.2a elementos = cobrancas ativas da clinica ' || v_clin, TO_CHAR(n_ativas(v_clin)), TO_CHAR(v_n));
        confere('E.2b comeca com [ e termina com ]', 'SIM [ ]',
                sn(DBMS_LOB.SUBSTR(v_c, 1, 1) = '[') || ' ' || DBMS_LOB.SUBSTR(v_c, 1, 1) || ' ' || DBMS_LOB.SUBSTR(v_c, 1, DBMS_LOB.GETLENGTH(v_c)));
        confere('E.2c um elemento por linha (quebras = elementos - 1)', TO_CHAR(GREATEST(v_n - 1, 0)), TO_CHAR(conta(v_c, CHR(10))));
        confere('E.2d so a clinica pedida (idClinica igual em todos)', TO_CHAR(v_n), TO_CHAR(conta(v_c, '"idClinica":' || v_clin || ',')));
        v_n2 := 0; v_ref := 0;
        FOR x IN (SELECT * FROM (SELECT c.* FROM COBRANCA c WHERE c.ID_CLINICA = v_clin AND c.ST_ATIVA = 'S' ORDER BY c.ID_COBRANCA)
                   WHERE ROWNUM <= 20) LOOP
            v_s := PKG_COBRANCA.fn_cobranca_json(x.ID_COBRANCA, x.ID_EVENTO_CLINICO, x.ID_CLINICA, x.ID_SERVICO_PRECO,
                                                 x.VL_COBRADO, x.DS_FORMA_PAGAMENTO, x.DT_COBRANCA, x.ST_ATIVA);
            v_ref := v_ref + 1;
            IF tem(v_c, SUBSTR(v_s, 1, LENGTH(v_s) - 1) || ',"nmClinica":') THEN v_n2 := v_n2 + 1; END IF;
        END LOOP;
        confere('E.2e cada objeto = o da fn_cobranca_json + nmClinica (ate 20 linhas)', TO_CHAR(v_ref), TO_CHAR(v_n2));
        libera(v_c);

        IF v_vazia IS NULL THEN
            pula('E.2f clinica sem cobranca => []', 'todas as clinicas ativas tem cobranca');
            pula('E.2g relatorio_json de clinica sem cobranca', 'idem');
        ELSE
            PKG_COBRANCA.listar_json(v_vazia, v_c);
            confere('E.2f clinica sem cobranca => []', '[]', DBMS_LOB.SUBSTR(v_c, 100, 1));
            libera(v_c);
            PKG_COBRANCA.relatorio_json(v_vazia, v_c);
            confere('E.2g relatorio_json de clinica sem cobranca',
                    '{"idClinica":' || v_vazia || ',"grupos":[],"subTotal":0.00}', DBMS_LOB.SUBSTR(v_c, 200, 1));
            libera(v_c);
        END IF;

        v_antes := n_log;
        confere('E.2h listar_json(NULL) => ORA-20001', '-20001', cod_listar(NULL));
        confere('E.2h grava 1 linha em LOG_ERRO', '1', TO_CHAR(n_log - v_antes));
        r := ultima;
        confere('E.2h NM_PROCEDURE', 'PKG_COBRANCA.LISTAR_JSON', r.NM_PROCEDURE);
        confere('E.2h NR_CODIGO_ERRO', '-20001', TO_CHAR(r.NR_CODIGO_ERRO));
        confere('E.2h DS_PARAMETROS', 'p_id_clinica=null', r.DS_PARAMETROS);
        v_antes := n_log;
        confere('E.2i listar_json(clinica inexistente) => ORA-20002', '-20002', cod_listar(-999999));
        confere('E.2i grava 1 linha em LOG_ERRO', '1', TO_CHAR(n_log - v_antes));
        r := ultima;
        confere('E.2i DS_PARAMETROS', 'p_id_clinica=-999999', r.DS_PARAMETROS);
        v_antes := n_log;
        confere('E.2j relatorio_json(NULL) => ORA-20001', '-20001', cod_relatorio(NULL));
        confere('E.2k relatorio_json(clinica inexistente) => ORA-20002', '-20002', cod_relatorio(-999999));
        confere('E.2k grava 2 linhas em LOG_ERRO (j + k)', '2', TO_CHAR(n_log - v_antes));
        r := ultima;
        confere('E.2k NM_PROCEDURE', 'PKG_COBRANCA.RELATORIO_JSON', r.NM_PROCEDURE);

        PKG_COBRANCA.relatorio_json(v_clin, v_c);
        confere('E.2l relatorio_json: cabecalho', '{"idClinica":' || v_clin || ',"grupos":[', DBMS_LOB.SUBSTR(v_c, LENGTH('{"idClinica":' || v_clin || ',"grupos":['), 1));
        confere('E.2l relatorio_json: subTotal = soma independente da clinica', 'SIM',
                sn(tem(v_c, '],"subTotal":' || fmt(soma_clinica(v_clin)) || '}')));
        confere('E.2l relatorio_json: termina com }', '}', DBMS_LOB.SUBSTR(v_c, 1, DBMS_LOB.GETLENGTH(v_c)));
        -- gabarito da Sprint 3 (PRC_RELATORIO_COBRANCAS(NULL), medido no G0): so vale na carga da S3
        SELECT COUNT(*) INTO v_n FROM COBRANCA;
        IF v_clin = 1 AND v_n = 18 THEN
            confere('E.2m gabarito S3 clinica 1', '{"idClinica":1,"grupos":[' || CHR(10)
                || '{"forma":"BOLETO","total":386.75},' || CHR(10)
                || '{"forma":"CARTAO_CREDITO","total":404.30},' || CHR(10)
                || '{"forma":"CARTAO_DEBITO","total":324.35},' || CHR(10)
                || '{"forma":"DINHEIRO","total":240.15},' || CHR(10)
                || '{"forma":"PIX","total":209.55}' || CHR(10)
                || '],"subTotal":1565.10}', DBMS_LOB.SUBSTR(v_c, 1000, 1));
            libera(v_c);
            PKG_COBRANCA.relatorio_json(2, v_c);
            confere('E.2m gabarito S3 clinica 2', '{"idClinica":2,"grupos":[' || CHR(10)
                || '{"forma":"CARTAO_CREDITO","total":438.15},' || CHR(10)
                || '{"forma":"DINHEIRO","total":280.20},' || CHR(10)
                || '{"forma":"PIX","total":420.80},' || CHR(10)
                || '{"forma":"TRANSFERENCIA","total":322.90}' || CHR(10)
                || '],"subTotal":1462.05}', DBMS_LOB.SUBSTR(v_c, 1000, 1));
        ELSE
            pula('E.2m gabarito S3 (subtotais 1565.10 e 1462.05)', 'so vale na carga da Sprint 3 (clinica 1, 18 cobrancas)');
        END IF;
        libera(v_c);

        PKG_COBRANCA.exportar_todas(v_c);
        SELECT COUNT(*) INTO v_n FROM COBRANCA WHERE ST_ATIVA = 'S';
        confere('E.2n exportar_todas: elementos = cobrancas ativas de todas as clinicas', TO_CHAR(v_n), TO_CHAR(conta(v_c, '"idCobranca":')));
        confere('E.2n exportar_todas: todo elemento traz nmClinica', TO_CHAR(v_n), TO_CHAR(conta(v_c, ',"nmClinica":')));
        libera(v_c);

        -- rotinas da Sprint 3 (saida por DBMS_OUTPUT): nao propagam e registram o erro
        DBMS_OUTPUT.PUT_LINE('---- saida de prc_relatorio_cobrancas(' || v_clin || ') ----');
        -- Sem cobranca ativa na clinica a procedure so loga NO_DATA_FOUND (esperado, mas muda a conta do E.3j):
        -- por isso so e chamada quando ha dado; senao o caso vira PULADO e a conta de LOG_ERRO continua exata.
        IF n_ativas(v_clin) > 0 THEN
            PKG_COBRANCA.prc_relatorio_cobrancas(v_clin);
        ELSE
            pula('prc_relatorio_cobrancas(' || v_clin || ') com dados', 'schema sem cobranca ativa');
        END IF;
        v_antes := n_log;
        PKG_COBRANCA.prc_listar_cobrancas_json(-999999);
        PKG_COBRANCA.prc_relatorio_cobrancas(-999999);
        confere('E.2o prc_* com clinica inexistente: nao propagam e gravam 2 linhas', '2', TO_CHAR(n_log - v_antes));
        r := ultima;
        confere('E.2o NM_PROCEDURE', 'PKG_COBRANCA.PRC_RELATORIO_COBRANCAS', r.NM_PROCEDURE);
        confere('E.2o NR_CODIGO_ERRO', '100', TO_CHAR(r.NR_CODIGO_ERRO));

        -- ======================= E.3 trigger + DML desfeito ===================
        DBMS_OUTPUT.PUT_LINE('---- E.3 trigger fina: INSERT / UPDATE / DELETE e ROLLBACK (nenhum dado fica) ----');
        IF v_evento IS NULL OR v_outra IS NULL THEN
            pula('E.3 trigger e isolamento entre clinicas', 'falta evento clinico ou uma segunda clinica ativa para ancorar o DML');
        ELSE
            SELECT COUNT(*) INTO v_cob_ant FROM COBRANCA;
            SELECT COUNT(*) INTO v_aud_ant FROM AUDITORIA_COBRANCA;
            SELECT COUNT(*) INTO v_srv_ant FROM SERVICO_PRECO;
            v_n_base := n_ativas(v_clin);

            INSERT INTO SERVICO_PRECO (ID_CLINICA, NM_SERVICO, VL_PRECO)
            VALUES (v_clin, c_servico, 10) RETURNING ID_SERVICO_PRECO INTO v_serv;
            INSERT INTO COBRANCA (ID_EVENTO_CLINICO, ID_CLINICA, ID_SERVICO_PRECO, VL_COBRADO, DS_FORMA_PAGAMENTO, ST_ATIVA)
            VALUES (v_evento, v_clin, v_serv, 10, 'PIX', 'S') RETURNING ID_COBRANCA INTO v_id;
            v_tx := DBMS_TRANSACTION.LOCAL_TRANSACTION_ID;
            confere('E.3a ha transacao pendente', 'SIM', CASE WHEN v_tx IS NULL THEN 'NAO' ELSE 'SIM' END);

            SELECT COUNT(*) INTO v_n FROM AUDITORIA_COBRANCA WHERE ID_COBRANCA = v_id;
            confere('E.3a INSERT gera 1 linha de auditoria', '1', TO_CHAR(v_n));
            SELECT DS_OPERACAO, DS_VALORES_OLD, DS_VALORES_NEW INTO v_cod, v_old, v_new
              FROM AUDITORIA_COBRANCA WHERE ID_COBRANCA = v_id;
            confere('E.3a DS_OPERACAO', 'INSERT', v_cod);
            confere('E.3a OLD nulo no INSERT', NULL, v_old);
            confere('E.3a NEW traz id, servico escapado e valor', 'SIM',
                    sn(INSTR(v_new, '"idCobranca":' || v_id || ',') > 0
                       AND INSTR(v_new, '"servico":"' || c_esc || '"') > 0
                       AND INSTR(v_new, '"valor":10.00') > 0));

            INSERT INTO COBRANCA (ID_EVENTO_CLINICO, ID_CLINICA, ID_SERVICO_PRECO, VL_COBRADO, DS_FORMA_PAGAMENTO, ST_ATIVA)
            VALUES (v_evento, v_clin, NULL, 5, 'DINHEIRO', 'N') RETURNING ID_COBRANCA INTO v_id2;
            INSERT INTO COBRANCA (ID_EVENTO_CLINICO, ID_CLINICA, ID_SERVICO_PRECO, VL_COBRADO, DS_FORMA_PAGAMENTO, ST_ATIVA)
            VALUES (v_evento, v_outra, NULL, 99.99, 'DINHEIRO', 'S') RETURNING ID_COBRANCA INTO v_id3;

            PKG_COBRANCA.listar_json(v_clin, v_c);
            confere('E.3b listar_json ve a cobranca nova (nome com aspas e barra escapado)', TO_CHAR(v_n_base + 1), TO_CHAR(conta(v_c, '"idCobranca":')));
            confere('E.3b o nome sai escapado no JSON', 'SIM', sn(tem(v_c, '"servico":"' || c_esc || '"')));
            confere('E.3c cobranca INATIVA nao entra', 'NAO', sn(tem(v_c, '"idCobranca":' || v_id2 || ',')));
            confere('E.3d cobranca de OUTRA clinica nao entra', 'NAO', sn(tem(v_c, '"idCobranca":' || v_id3 || ',')));
            confere('E.3d nenhum idClinica de outra clinica', '0', TO_CHAR(conta(v_c, '"idClinica":' || v_outra || ',')));
            libera(v_c);
            PKG_COBRANCA.exportar_todas(v_c);
            confere('E.3d controle: exportar_todas (todas as clinicas) VE a cobranca da outra', 'SIM', sn(tem(v_c, '"idCobranca":' || v_id3 || ',')));
            libera(v_c);
            PKG_COBRANCA.relatorio_json(v_clin, v_c);
            confere('E.3e relatorio_json acompanha o DML (subTotal = soma independente)', 'SIM',
                    sn(tem(v_c, '],"subTotal":' || fmt(soma_clinica(v_clin)) || '}')));
            libera(v_c);

            UPDATE COBRANCA SET VL_COBRADO = 12.5 WHERE ID_COBRANCA = v_id;
            SELECT COUNT(*) INTO v_n FROM AUDITORIA_COBRANCA WHERE ID_COBRANCA = v_id;
            confere('E.3f UPDATE: agora 2 linhas de auditoria do registro', '2', TO_CHAR(v_n));
            SELECT DS_VALORES_OLD, DS_VALORES_NEW INTO v_old, v_new
              FROM AUDITORIA_COBRANCA WHERE ID_COBRANCA = v_id AND DS_OPERACAO = 'UPDATE';
            confere('E.3f OLD tem o valor antigo', 'SIM', sn(INSTR(v_old, '"valor":10.00') > 0 AND INSTR(v_old, '"idCobranca":' || v_id || ',') > 0));
            confere('E.3f NEW tem o valor novo', 'SIM', sn(INSTR(v_new, '"valor":12.50') > 0 AND INSTR(v_new, '"servico":"' || c_esc || '"') > 0));

            DELETE FROM COBRANCA WHERE ID_COBRANCA = v_id;
            SELECT COUNT(*) INTO v_n FROM AUDITORIA_COBRANCA WHERE ID_COBRANCA = v_id;
            confere('E.3g DELETE: 3 linhas de auditoria (INSERT, UPDATE, DELETE)', '3', TO_CHAR(v_n));
            SELECT COUNT(*) INTO v_n FROM AUDITORIA_COBRANCA WHERE ID_COBRANCA = v_id AND DS_OPERACAO IN ('INSERT', 'UPDATE', 'DELETE');
            confere('E.3g as 3 operacoes distintas', '3', TO_CHAR(v_n));
            SELECT DS_VALORES_OLD, DS_VALORES_NEW INTO v_old, v_new
              FROM AUDITORIA_COBRANCA WHERE ID_COBRANCA = v_id AND DS_OPERACAO = 'DELETE';
            confere('E.3g OLD do DELETE tem o valor 12.50', 'SIM', sn(INSTR(v_old, '"valor":12.50') > 0));
            confere('E.3g NEW nulo no DELETE', NULL, v_new);
            SELECT COUNT(*) INTO v_n FROM AUDITORIA_COBRANCA;
            confere('E.3h linhas de auditoria da transacao (3 + 1 + 1)', TO_CHAR(v_aud_ant + 5), TO_CHAR(v_n));

            ROLLBACK;
            SELECT COUNT(*) INTO v_n FROM AUDITORIA_COBRANCA WHERE ID_COBRANCA IN (v_id, v_id2, v_id3);
            confere('E.3i a auditoria SOME no ROLLBACK (mesma transacao do DML)', '0', TO_CHAR(v_n));
            SELECT COUNT(*) INTO v_n FROM AUDITORIA_COBRANCA;
            confere('E.3i AUDITORIA_COBRANCA volta ao total de antes', TO_CHAR(v_aud_ant), TO_CHAR(v_n));
            SELECT COUNT(*) INTO v_n FROM COBRANCA;
            confere('E.3i COBRANCA volta ao total de antes', TO_CHAR(v_cob_ant), TO_CHAR(v_n));
            SELECT COUNT(*) INTO v_n FROM SERVICO_PRECO;
            confere('E.3i SERVICO_PRECO volta ao total de antes', TO_CHAR(v_srv_ant), TO_CHAR(v_n));
            v_tx := DBMS_TRANSACTION.LOCAL_TRANSACTION_ID;
            confere('E.3i nenhuma transacao pendente depois do ROLLBACK', 'NAO', CASE WHEN v_tx IS NULL THEN 'NAO' ELSE 'SIM' END);
            confere('E.3j o log autonomo sobrevive: 8 linhas desta execucao ate aqui (E.1d, E.1e, E.2h, E.2i, E.2j, E.2k, E.2o x2)',
                    '8', TO_CHAR(n_log));
        END IF;

        -- ======================= E.4 NLS_TERRITORY = BRAZIL ===================
        DBMS_OUTPUT.PUT_LINE('---- E.4 mesma saida com NLS_TERRITORY=BRAZIL (separador decimal virgula) ----');
        SELECT value INTO v_terr FROM nls_session_parameters WHERE parameter = 'NLS_TERRITORY';
        PKG_COBRANCA.listar_json(v_clin, v_c);
        PKG_COBRANCA.relatorio_json(v_clin, v_c2);
        BEGIN
            EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_TERRITORY = ''BRAZIL''';
            SELECT value INTO v_numch FROM nls_session_parameters WHERE parameter = 'NLS_NUMERIC_CHARACTERS';
            confere('E.4a NLS_NUMERIC_CHARACTERS sob BRAZIL', ',.', v_numch);
            confere('E.4b fn_cobranca_json igual sob BRAZIL (valor 12.50 com ponto)', v_fn_am,
                    PKG_COBRANCA.fn_cobranca_json(1, 2, 3, NULL, 12.5, 'PIX', TIMESTAMP '2026-10-28 10:11:12', 'S'));
            PKG_COBRANCA.listar_json(v_clin, v_c3);
            confere('E.4c listar_json identico byte a byte sob BRAZIL', '0', TO_CHAR(DBMS_LOB.COMPARE(v_c, v_c3)));
            PKG_COBRANCA.relatorio_json(v_clin, v_c4);
            confere('E.4d relatorio_json identico byte a byte sob BRAZIL', '0', TO_CHAR(DBMS_LOB.COMPARE(v_c2, v_c4)));
            confere('E.4e nenhum numero com virgula decimal (listar_json e relatorio_json sob BRAZIL)', '0',
                    TO_CHAR(REGEXP_INSTR(v_c3, '[0-9],[0-9][0-9][,}]') + REGEXP_INSTR(v_c4, '[0-9],[0-9][0-9][,}]')));
        EXCEPTION
            WHEN OTHERS THEN
                restaura_nls;
                RAISE;
        END;
        restaura_nls;
        libera(v_c); libera(v_c2); libera(v_c3); libera(v_c4);
    END IF;

    DBMS_OUTPUT.PUT_LINE('---- E.5 contagens ----');
    SELECT COUNT(*) INTO v_cob_ant FROM COBRANCA;
    SELECT COUNT(*) INTO v_aud_ant FROM AUDITORIA_COBRANCA;
    DBMS_OUTPUT.PUT_LINE('COBRANCA = ' || v_cob_ant || ' | AUDITORIA_COBRANCA = ' || v_aud_ant
                         || ' (iguais as de antes da demonstracao: todo DML foi desfeito)');
    DBMS_OUTPUT.PUT_LINE('PULADOS: ' || v_pulado);
    DBMS_OUTPUT.PUT_LINE('RESUMO: ' || v_ok || ' OK, ' || v_falhou || ' FALHOU');
    IF v_falhou > 0 THEN
        RAISE_APPLICATION_ERROR(-20902, 'DEMO S4-DB-03: ' || v_falhou || ' caso(s) FALHOU - ver as linhas FALHOU acima');
    END IF;
END;
/
PROMPT ###################  DEMO S4-DB-03: FIM  ###################

-- BLOCO 8 de novo: as demonstracoes nao deixaram nada invalido. (Copia literal do
-- BLOCO 8 de cima, de proposito: o script e SQL*Plus puro, sem include; mover o
-- bloco para um procedimento criaria um objeto a mais no schema so para isto.)
PROMPT
PROMPT === BLOCO 8: verificacao (recompila e confere objetos e DEPENDENTES) ===
-- Recompila os objetos deste arquivo e TODOS os que dependem deles (direta ou
-- transitivamente, via user_dependencies - a trigger de COBRANCA inclusive) e
-- exige que nenhum fique INVALID nem tenha erro de compilacao. Motivo (RE-I1 da
-- re-G2): CREATE OR REPLACE so preserva um dependente se a versao nova compilar;
-- e depois de reinstalar a versao correta o dependente podia continuar INVALID
-- (so seria recompilado no proximo uso - para uma trigger, no proximo INSERT em
-- COBRANCA, que falharia). Aqui ele e recompilado AGORA, e conferido.
-- Qualquer pendencia => ORA-20901 => o script para (EXIT=165) antes do BLOCO 9.
DECLARE
    v_lista  VARCHAR2(4000);
    v_falhas VARCHAR2(4000);
    v_qtd    PLS_INTEGER;
    v_ext    PLS_INTEGER := 0;

    -- objetos DESTE arquivo (nomes), para o ponto de partida da busca de dependentes
    CURSOR c_alvos IS
        SELECT DISTINCT name AS nome,
               CASE WHEN type LIKE 'PACKAGE%' THEN 'PACKAGE' ELSE type END AS tipo
          FROM (SELECT object_name AS name, object_type AS type
                  FROM user_objects
                 WHERE object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA',
                                       'TRG_AUDITORIA_COBRANCA')
                UNION
                SELECT d.name, d.type
                  FROM user_dependencies d
                 WHERE d.type IN ('PACKAGE', 'PACKAGE BODY', 'FUNCTION', 'PROCEDURE', 'TRIGGER', 'VIEW')
                 START WITH d.referenced_owner = USER
                        AND d.referenced_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA',
                                                  'PKG_AUDITORIA', 'AUDITORIA_COBRANCA',
                                                  'SEQ_AUDITORIA_COBRANCA')
                 CONNECT BY NOCYCLE d.referenced_owner = USER
                        AND d.referenced_name = PRIOR d.name
                        AND d.referenced_type = PRIOR d.type)
         WHERE type IN ('PACKAGE', 'PACKAGE BODY', 'FUNCTION', 'PROCEDURE', 'TRIGGER', 'VIEW');

    PROCEDURE compila (p_tipo IN VARCHAR2, p_nome IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'ALTER ' || p_tipo || ' "' || p_nome || '" COMPILE';
    EXCEPTION
        WHEN OTHERS THEN
            v_falhas := SUBSTR(v_falhas || CHR(10) || '  - ' || p_tipo || ' ' || p_nome || ': ' || SQLERRM, 1, 2000);
    END compila;
BEGIN
    -- 2 passadas: a ordem de compilacao entre dependentes nao precisa ser calculada
    FOR passada IN 1 .. 2 LOOP
        FOR a IN c_alvos LOOP
            compila(a.tipo, a.nome);
        END LOOP;
    END LOOP;

    FOR a IN c_alvos LOOP
        IF a.nome NOT IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA', 'TRG_AUDITORIA_COBRANCA') THEN
            v_ext := v_ext + 1;
            DBMS_OUTPUT.PUT_LINE('dependente externo verificado: ' || a.tipo || ' ' || a.nome);
        END IF;
    END LOOP;

    FOR r IN (SELECT o.object_name || ' (' || o.object_type || ') ' || o.status AS d
                FROM user_objects o
               WHERE o.status <> 'VALID'
                 AND (o.object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA',
                                        'TRG_AUDITORIA_COBRANCA', 'AUDITORIA_COBRANCA',
                                        'SEQ_AUDITORIA_COBRANCA', 'IDX_AUDITORIA_COB_DATA',
                                        'IDX_AUDITORIA_COB_REG')
                      OR o.object_name IN (SELECT nome FROM (
                              SELECT DISTINCT d.name AS nome
                                FROM user_dependencies d
                               START WITH d.referenced_owner = USER
                                      AND d.referenced_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA',
                                                                'PKG_AUDITORIA', 'AUDITORIA_COBRANCA',
                                                                'SEQ_AUDITORIA_COBRANCA')
                               CONNECT BY NOCYCLE d.referenced_owner = USER
                                      AND d.referenced_name = PRIOR d.name
                                      AND d.referenced_type = PRIOR d.type)))
              UNION ALL
              SELECT e.name || ' (' || e.type || ') erro na linha ' || e.line || ': '
                     || SUBSTR(REPLACE(e.text, CHR(10), ' '), 1, 160)
                FROM user_errors e
               WHERE e.attribute = 'ERROR'
                 AND (e.name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA',
                                 'TRG_AUDITORIA_COBRANCA')
                      OR e.name IN (SELECT nome FROM (
                              SELECT DISTINCT d.name AS nome
                                FROM user_dependencies d
                               START WITH d.referenced_owner = USER
                                      AND d.referenced_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA',
                                                                'PKG_AUDITORIA', 'AUDITORIA_COBRANCA',
                                                                'SEQ_AUDITORIA_COBRANCA')
                               CONNECT BY NOCYCLE d.referenced_owner = USER
                                      AND d.referenced_name = PRIOR d.name
                                      AND d.referenced_type = PRIOR d.type)))) LOOP
        v_lista := SUBSTR(v_lista || CHR(10) || '  - ' || r.d, 1, 3000);
    END LOOP;

    IF v_falhas IS NOT NULL THEN
        v_lista := SUBSTR(v_lista || CHR(10) || '  - o ALTER ... COMPILE falhou em:' || v_falhas, 1, 3500);
    END IF;

    SELECT COUNT(*) INTO v_qtd
      FROM user_objects
     WHERE object_name IN ('PKG_KURA_LOG', 'PKG_TRIAGEM', 'PKG_COBRANCA', 'PKG_AUDITORIA')
       AND object_type IN ('PACKAGE', 'PACKAGE BODY')
       AND status = 'VALID';
    IF v_qtd <> 8 THEN
        v_lista := v_lista || CHR(10) || '  - esperados 8 objetos de package VALID (4 specs + 4 bodies), encontrados ' || v_qtd;
    END IF;

    SELECT COUNT(*) INTO v_qtd
      FROM user_objects
     WHERE object_name = 'TRG_AUDITORIA_COBRANCA' AND object_type = 'TRIGGER' AND status = 'VALID';
    IF v_qtd <> 1 THEN
        v_lista := v_lista || CHR(10) || '  - esperada a TRG_AUDITORIA_COBRANCA VALID, encontradas ' || v_qtd;
    END IF;

    IF v_lista IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20901,
            SUBSTR('BLOCO 8: objeto(s) invalido(s) ou com erro de compilacao:' || v_lista, 1, 2000));
    END IF;
    DBMS_OUTPUT.PUT_LINE('verificacao OK: 4 packages (spec + body) e TRG_AUDITORIA_COBRANCA VALID, '
        || v_ext || ' dependente(s) externo(s) recompilado(s) e VALID, 0 erros de compilacao, AUDITORIA_COBRANCA VALID.');
END;
/
PROMPT
PROMPT === FIM DO ARQUIVO 2TDSPF_2026_Packages_Integrantes.sql ===

EXIT
