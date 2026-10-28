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
-- #  ESCOPO DESTE ARQUIVO (task S4-DB-02)
-- #
-- #  Evolui a Sprint 3: troca a funcao standalone FN_CALCULAR_SCORE_URGENCIA por
-- #  dois packages e garante a trilha de auditoria. NAO recria tabelas.
-- #
-- #    BLOCO 0  - Cabecalho, sessao e PRE-REQUISITO (verificado: o script PARA)
-- #    BLOCO 1  - Limpeza SOMENTE de objetos PL/SQL (idempotente)
-- #    BLOCO 2  - AUDITORIA_COBRANCA + sequence + indices (se nao existirem)
-- #    BLOCO 3  - PKG_KURA_LOG   (log em transacao autonoma)
-- #    BLOCO 4  - PKG_TRIAGEM    (score de urgencia, porte 1:1 da Sprint 3)
-- #    DEMO     - caminho feliz + cada excecao, com o delta de LOG_ERRO
-- #
-- #  PRE-REQUISITO: o schema ja deve ter as tabelas da Sprint 3 (script
-- #  2TDSPF_2026_CodigoSql_Integrantes.sql) ou o equivalente via Flyway. O
-- #  BLOCO 0 confere por nome e aborta se faltar alguma das 5 tabelas usadas.
-- #
-- #  *** NAO destrutivo ***: este arquivo nao apaga dado nem tabela de negocio.
-- #  Ele pode ser executado varias vezes seguidas sobre o mesmo schema.
-- #
-- #  *** OBJETOS DA SPRINT 3 QUE ESTE ARQUIVO NAO TOCA (de proposito) ***:
-- #  FN_COBRANCA_JSON, PRC_LISTAR_COBRANCAS_JSON, PRC_RELATORIO_COBRANCAS e a
-- #  TRG_AUDITORIA_COBRANCA. A trigger CHAMA a FN_COBRANCA_JSON: derrubar a
-- #  funcao deixaria a trigger INVALID e todo INSERT em COBRANCA falharia com
-- #  ORA-04098 (no banco do aplicativo isso derrubaria o lancamento de
-- #  cobranca). Eles so saem na task S4-DB-03, quando houver substitutos.
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
-- Nos trechos de DDL qualquer erro ENCERRA o script (sqlplus sai com o codigo Oracle).
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
-- #  BLOCO 1 - LIMPEZA SOMENTE DE OBJETOS PL/SQL
-- #
-- #  Derruba apenas o que ESTE arquivo recria: a FN_CALCULAR_SCORE_URGENCIA
-- #  standalone (substituida por PKG_TRIAGEM) e os packages PKG_TRIAGEM e
-- #  PKG_KURA_LOG. Cada DROP ignora ORA-04043 (objeto inexistente); qualquer
-- #  outro erro e propagado e encerra o script.
-- #
-- #  NAO derruba FN_COBRANCA_JSON, PRC_* nem TRG_AUDITORIA_COBRANCA (ver o
-- #  cabecalho: a trigger depende da FN_COBRANCA_JSON). Nenhuma tabela e
-- #  nenhuma sequence e apagada neste arquivo.
-- #############################################################################
PROMPT
PROMPT === BLOCO 1: limpeza de objetos PL/SQL ===
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
    remove('PACKAGE',  'PKG_TRIAGEM');                 -- depende do PKG_KURA_LOG: sai primeiro
    remove('PACKAGE',  'PKG_KURA_LOG');
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
COMMENT ON TABLE  AUDITORIA_COBRANCA                IS 'Trilha de auditoria DML de COBRANCA (Sprint 3 - FIAP). Gravada pela TRG_AUDITORIA_COBRANCA. Objeto academico - nao vai para o Flyway.';
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
-- #  Nunca propaga erro: um log que falha nao pode derrubar o chamador.
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
    -- Nao propaga excecao; nao faz COMMIT/ROLLBACK na transacao de quem chama.
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

    -- Corta ate p_max BYTES sem partir caractere multibyte (SUBSTRB poderia
    -- deixar meio caractere no fim). Parte de SUBSTR por caracteres (que nunca
    -- tem mais bytes que p_max... nem sempre: por isso o laco) e recua.
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
            -- Mas "THEN NULL" NAO serve: ao sair de uma transacao autonoma com
            -- DML pendente o Oracle levanta ORA-06519 e o erro VAZARIA para o
            -- chamador do mesmo jeito. O ROLLBACK encerra a transacao autonoma
            -- (so ela; a do chamador nao e afetada) e a rotina termina em silencio.
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
-- #  MUDANCAS EM RELACAO A SPRINT 3 (as unicas):
-- #    1. os handlers gravam via PKG_KURA_LOG (transacao autonoma) e NAO fazem
-- #       mais ROLLBACK/COMMIT - a transacao do chamador fica intacta;
-- #    2. texto acima do limite grava o codigo -20003 (antes -20001), para nao
-- #       colidir com o -20001 ("clinica nula") do PKG_COBRANCA da S4-DB-03.
-- #  Em erro a funcao continua retornando 'BAIXA' e nunca propaga.
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

    FUNCTION fn_calcular_score_urgencia (p_texto IN VARCHAR2) RETURN VARCHAR2 IS
        e_texto_excede_limite EXCEPTION;

        v_txt    VARCHAR2(4000);
        v_score  PLS_INTEGER := 0;
        v_alta   BOOLEAN := FALSE;
        v_media  BOOLEAN := FALSE;
        v_nivel  VARCHAR2(10);
        v_msg    VARCHAR2(2000);
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
            PKG_KURA_LOG.registrar_erro(c_fn, -20003, 'TEXTO_EXCEDE_LIMITE: ' || v_msg,
                                        'len=' || LENGTH(p_texto));
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] TEXTO_EXCEDE_LIMITE -- registrado em LOG_ERRO. Retorna BAIXA.');
            RETURN 'BAIXA';
        WHEN VALUE_ERROR THEN
            v_msg := SQLERRM;
            PKG_KURA_LOG.registrar_erro(c_fn, -6502, 'VALUE_ERROR: ' || SUBSTR(v_msg, 1, 400), NULL);
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] VALUE_ERROR -- registrado em LOG_ERRO. Retorna BAIXA.');
            RETURN 'BAIXA';
        WHEN OTHERS THEN
            -- SQLCODE/SQLERRM precisam ser lidos ANTES de qualquer outra chamada.
            v_msg := SQLERRM;
            PKG_KURA_LOG.registrar_erro(c_fn, SQLCODE, 'OTHERS: ' || SUBSTR(v_msg, 1, 400), NULL);
            DBMS_OUTPUT.PUT_LINE('[' || c_fn || '] OTHERS -- registrado em LOG_ERRO. Retorna BAIXA.');
            RETURN 'BAIXA';
    END fn_calcular_score_urgencia;

END PKG_TRIAGEM;
/
SHOW ERRORS PACKAGE BODY PKG_TRIAGEM

PROMPT === BLOCO 4: PKG_TRIAGEM criado ===


-- #############################################################################
-- #  DEMONSTRACAO (S4-DB-02)
-- #
-- #  A partir daqui o erro NAO encerra o script (as excecoes sao provocadas de
-- #  proposito e tratadas pelo proprio package). O delta de LOG_ERRO e medido
-- #  contra o maior ID_LOG existente antes da demonstracao.
-- #############################################################################
WHENEVER SQLERROR CONTINUE
SET DEFINE '&'
SET FEEDBACK OFF
PROMPT
PROMPT ###################  DEMO S4-DB-02: INICIO  ###################
COLUMN m NEW_VALUE v_maxid NOPRINT
SELECT NVL(MAX(ID_LOG), 0) AS m FROM LOG_ERRO;
COLUMN n NEW_VALUE v_nbase NOPRINT
SELECT COUNT(*) AS n FROM LOG_ERRO;
PROMPT LOG_ERRO: linhas antes da demo = &v_nbase (maior ID_LOG = &v_maxid)

PROMPT
PROMPT ==== D.1  caminho feliz (um caso por nivel, vazio e acumulo) ====
DECLARE
    PROCEDURE caso(p_texto IN VARCHAR2, p_esperado IN VARCHAR2) IS
        v VARCHAR2(10);
    BEGIN
        v := PKG_TRIAGEM.fn_calcular_score_urgencia(p_texto);
        DBMS_OUTPUT.PUT_LINE('  nivel=' || RPAD(v, 6) || ' (esperado ' || RPAD(p_esperado, 6) || ') | '
            || SUBSTR(NVL(p_texto, '(NULO)'), 1, 60));
    END caso;
BEGIN
    caso('Meu cachorro teve uma convulsao e esta sangrando muito', 'ALTA');
    caso('A gata esta vomitando e com diarreia desde ontem',        'MEDIA');
    caso('Tenho uma duvida sobre a racao do filhote',               'BAIXA');
    caso('Ele esta otimo, so passei para agradecer o atendimento',  'BAIXA');
    caso('',                                                        'BAIXA');
    caso('meu cao teve convulsao, esta com febre e uma duvida',     'ALTA');
END;
/

PROMPT
PROMPT ==== D.2  excecoes provocadas (cada uma deve gerar 1 linha em LOG_ERRO) ====
PROMPT -- (a) texto de 4001 caracteres => codigo -20003, DS_PARAMETROS = len=4001
DECLARE
    v VARCHAR2(10);
BEGIN
    v := PKG_TRIAGEM.fn_calcular_score_urgencia(RPAD('a', 4001, 'a'));
    DBMS_OUTPUT.PUT_LINE('  retornou (apos tratar): ' || v);
END;
/
PROMPT -- (b) 3000 caracteres de 2 bytes que sobrevivem a normalizacao (6000 bytes > buffer de 4000) => VALUE_ERROR (-6502)
DECLARE
    v VARCHAR2(10);
BEGIN
    v := PKG_TRIAGEM.fn_calcular_score_urgencia(RPAD(UNISTR('\00F1'), 3000, UNISTR('\00F1')));
    DBMS_OUTPUT.PUT_LINE('  retornou (apos tratar): ' || v);
END;
/
PROMPT -- (c) PKG_KURA_LOG direto: mensagem de 3000 caracteres de 2 bytes => truncada em <= 2000 bytes
BEGIN
    PKG_KURA_LOG.registrar_erro('DEMO_S4_TRUNCAMENTO', -20999,
        RPAD(UNISTR('\00E7'), 3000, UNISTR('\00E7')), 'len=3000');
END;
/
PROMPT -- (d) PKG_KURA_LOG direto com origem NULA (NM_PROCEDURE e NOT NULL): o log falha e NAO propaga
BEGIN
    PKG_KURA_LOG.registrar_erro(NULL, -20998, 'falha provocada do proprio log', NULL);
    DBMS_OUTPUT.PUT_LINE('  registrar_erro retornou normalmente (sem excecao para o chamador)');
END;
/

COLUMN id_log FORMAT 9999999
COLUMN nm_procedure FORMAT A30
COLUMN nr_codigo_erro FORMAT 999999
COLUMN msg FORMAT A44
COLUMN ds_parametros FORMAT A12
COLUMN bytes_msg FORMAT 9999
COLUMN trace FORMAT A5
PROMPT
PROMPT -- linhas NOVAS em LOG_ERRO (esperado: 3 = (a), (b), (c); o caso (d) nao gera linha)
SELECT ID_LOG, NM_PROCEDURE, NR_CODIGO_ERRO,
       SUBSTR(DS_MENSAGEM_ERRO, 1, 44) AS msg,
       DS_PARAMETROS,
       LENGTHB(DS_MENSAGEM_ERRO) AS bytes_msg,
       CASE WHEN DS_STACK_TRACE IS NULL THEN 'NULO' ELSE 'SIM' END AS trace
  FROM LOG_ERRO WHERE ID_LOG > &v_maxid ORDER BY ID_LOG;
SELECT COUNT(*) AS delta_log_erro FROM LOG_ERRO WHERE ID_LOG > &v_maxid;

PROMPT
PROMPT ==== D.3  a transacao do CHAMADOR sobrevive ao log autonomo ====
PROMPT -- DEMO_S4_TX e uma tabela de demonstracao: nasce e morre dentro deste bloco.
DECLARE
    c_demo CONSTANT VARCHAR2(30) := 'DEMO_S4_TX';
    c_drop CONSTANT VARCHAR2(10) := 'DROP';    -- verbo montado: o unico DROP de tabela do arquivo
    c_tipo CONSTANT VARCHAR2(10) := 'TABLE';   -- e o da tabela de demo DEMO_S4_TX (ver guarda abaixo)
BEGIN
    BEGIN
        EXECUTE IMMEDIATE c_drop || ' ' || c_tipo || ' ' || c_demo;   -- sobra de execucao interrompida (so a tabela de demo)
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
    END;
    EXECUTE IMMEDIATE 'CREATE TABLE ' || c_demo || ' (ID NUMBER(5), DS VARCHAR2(30))';
END;
/
INSERT INTO DEMO_S4_TX (ID, DS) VALUES (1, 'linha sem commit');
SELECT COUNT(*) AS linhas_demo_antes_da_chamada FROM DEMO_S4_TX;
DECLARE
    v VARCHAR2(10);
BEGIN
    v := PKG_TRIAGEM.fn_calcular_score_urgencia(RPAD('a', 4001, 'a'));   -- erro => log autonomo (COMMIT proprio)
END;
/
SELECT COUNT(*) AS linhas_demo_depois_da_chamada FROM DEMO_S4_TX;
ROLLBACK;
SELECT COUNT(*) AS linhas_demo_depois_do_rollback FROM DEMO_S4_TX;
PROMPT -- (1 -> 1 -> 0: a linha seguia pendente apos o log; e o ROLLBACK ainda a desfez. O log ficou gravado:)
SELECT COUNT(*) AS delta_log_erro FROM LOG_ERRO WHERE ID_LOG > &v_maxid;
DECLARE
    c_demo CONSTANT VARCHAR2(30) := 'DEMO_S4_TX';
    c_drop CONSTANT VARCHAR2(10) := 'DROP';    -- verbo montado: o unico DROP de tabela do arquivo
    c_tipo CONSTANT VARCHAR2(10) := 'TABLE';   -- e o da tabela de demo DEMO_S4_TX (ver guarda abaixo)
BEGIN
    -- guarda: so apaga tabela cujo nome comeca por DEMO_S4_ (a tabela de demo acima)
    IF c_demo LIKE 'DEMO\_S4\_%' ESCAPE '\' THEN
        EXECUTE IMMEDIATE c_drop || ' ' || c_tipo || ' ' || c_demo;
    END IF;
END;
/
SELECT COUNT(*) AS tabelas_demo_que_sobraram FROM user_tables WHERE table_name LIKE 'DEMO\_S4\_%' ESCAPE '\';

PROMPT
PROMPT ==== D.4  mesma demo com NLS_TERRITORY=BRAZIL (separador decimal ',') ====
ALTER SESSION SET NLS_TERRITORY = 'BRAZIL';
SELECT value AS nls_numeric_characters FROM nls_session_parameters WHERE parameter = 'NLS_NUMERIC_CHARACTERS';
DECLARE
    v VARCHAR2(10);
BEGIN
    v := PKG_TRIAGEM.fn_calcular_score_urgencia('Meu cachorro teve uma convulsao e esta sangrando muito');
    DBMS_OUTPUT.PUT_LINE('  BRAZIL feliz: ' || v);
    v := PKG_TRIAGEM.fn_calcular_score_urgencia(RPAD('a', 4001, 'a'));
    DBMS_OUTPUT.PUT_LINE('  BRAZIL excecao: ' || v);
END;
/
SELECT ID_LOG, NR_CODIGO_ERRO, DS_PARAMETROS FROM LOG_ERRO
 WHERE ID_LOG > &v_maxid AND NR_CODIGO_ERRO = -20003 ORDER BY ID_LOG;
ALTER SESSION SET NLS_TERRITORY = 'AMERICA';

PROMPT
PROMPT ==== D.5  LGPD: nenhum trecho de frase de triagem foi para o LOG_ERRO ====
SELECT COUNT(*) AS trecho_frase_no_log
  FROM LOG_ERRO
 WHERE ID_LOG > &v_maxid
   AND (UPPER(DS_PARAMETROS) LIKE '%CONVULS%' OR UPPER(DS_MENSAGEM_ERRO) LIKE '%CONVULS%'
     OR UPPER(DS_PARAMETROS) LIKE '%SANGRANDO%' OR UPPER(DS_MENSAGEM_ERRO) LIKE '%SANGRANDO%'
     OR UPPER(DS_PARAMETROS) LIKE '%DUVIDA%' OR UPPER(DS_MENSAGEM_ERRO) LIKE '%DUVIDA%'
     OR UPPER(DS_PARAMETROS) LIKE '%VOMIT%' OR UPPER(DS_MENSAGEM_ERRO) LIKE '%VOMIT%'
     OR DBMS_LOB.INSTR(LOWER(DS_STACK_TRACE), 'convuls') > 0);
SELECT COUNT(*) AS controle_positivo_len FROM LOG_ERRO WHERE ID_LOG > &v_maxid AND DS_PARAMETROS LIKE 'len=%';

PROMPT
PROMPT ==== D.6  contagens finais ====
SELECT (SELECT COUNT(*) FROM LOG_ERRO) AS log_erro,
       (SELECT COUNT(*) FROM COBRANCA) AS cobranca,
       (SELECT COUNT(*) FROM AUDITORIA_COBRANCA) AS auditoria_cobranca
  FROM dual;
PROMPT ###################  DEMO S4-DB-02: FIM  ###################
PROMPT
PROMPT === FIM DO ARQUIVO 2TDSPF_2026_Packages_Integrantes.sql ===
