-- ============================================================================
-- KURA — Sistema de Gestão Veterinária | Clyvo Vet / FIAP Challenge 2026
-- DISCIPLINA: Mastering Relational and Non-Relational Database
-- REQUISITO 1: Procedures de Carga de Dados Parametrizadas (20 pts)
--
-- Regras atendidas:
--   [R1.1] Carga via passagem de parâmetro — SEM hard-code
--   [R1.2] EXCEPTION WHEN OTHERS em todos os blocos
--   [R1.3] + 2 exceções específicas por procedure
--   [R1.4] Log gravado em LOG_ERRO (nome proc, usuário, data, SQLCODE, SQLERRM)
--
-- Tabelas cobertas: CLINICA · ESPECIE · VETERINARIO · TUTOR · PET
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PROCEDURE 1 — PRC_INSERT_CLINICA
-- Insere uma nova clínica veterinária na tabela CLINICA.
-- Exceções específicas: DUP_VAL_ON_INDEX (CNPJ/e-mail duplicado),
--                       VALUE_ERROR (campo fora do tamanho permitido)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PRC_INSERT_CLINICA (
    p_nm_clinica       IN CLINICA.NM_CLINICA%TYPE,
    p_nr_cnpj          IN CLINICA.NR_CNPJ%TYPE,
    p_nm_razao_social  IN CLINICA.NM_RAZAO_SOCIAL%TYPE,
    p_ds_endereco      IN CLINICA.DS_ENDERECO%TYPE,
    p_nm_cidade        IN CLINICA.NM_CIDADE%TYPE,
    p_sg_uf            IN CLINICA.SG_UF%TYPE,
    p_nr_cep           IN CLINICA.NR_CEP%TYPE,
    p_ds_telefone      IN CLINICA.DS_TELEFONE%TYPE,
    p_ds_email         IN CLINICA.DS_EMAIL%TYPE,
    p_ds_email_acesso  IN CLINICA.DS_EMAIL_ACESSO%TYPE,
    p_ds_senha_hash    IN CLINICA.DS_SENHA_HASH%TYPE
) AS
    -- Constante com o nome desta procedure para rastreabilidade no log
    c_proc CONSTANT VARCHAR2(120) := 'PRC_INSERT_CLINICA';
BEGIN
    INSERT INTO CLINICA (
        ID_CLINICA, NM_CLINICA, NR_CNPJ, NM_RAZAO_SOCIAL,
        DS_ENDERECO, NM_CIDADE, SG_UF, NR_CEP,
        DS_TELEFONE, DS_EMAIL, DS_EMAIL_ACESSO, DS_SENHA_HASH,
        DT_CADASTRO, ST_ATIVA
    ) VALUES (
        SEQ_CLINICA.NEXTVAL,
        p_nm_clinica, p_nr_cnpj, p_nm_razao_social,
        p_ds_endereco, p_nm_cidade, p_sg_uf, p_nr_cep,
        p_ds_telefone, p_ds_email, p_ds_email_acesso, p_ds_senha_hash,
        SYSTIMESTAMP, 'S'
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Clínica inserida: ' || p_nm_clinica);

EXCEPTION
    -- Exceção específica 1: violação de UNIQUE (CNPJ ou e-mail já cadastrado)
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'DUP_VAL_ON_INDEX: CNPJ ou e-mail já cadastrado. ' || SQLERRM,
                'NM_CLINICA=' || p_nm_clinica || ' | NR_CNPJ=' || p_nr_cnpj);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Clínica duplicada — log gravado.');

    -- Exceção específica 2: valor fora do tamanho do campo
    WHEN VALUE_ERROR THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'VALUE_ERROR: Campo com tamanho/tipo inválido. ' || SQLERRM,
                'NM_CLINICA=' || p_nm_clinica);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Valor inválido — log gravado.');

    -- Exceção genérica: qualquer outro erro Oracle
    WHEN OTHERS THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'OTHERS: ' || SQLERRM,
                'NM_CLINICA=' || p_nm_clinica || ' | NR_CNPJ=' || p_nr_cnpj);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Erro inesperado — log gravado.');
END PRC_INSERT_CLINICA;
/

-- ----------------------------------------------------------------------------
-- PROCEDURE 2 — PRC_INSERT_ESPECIE
-- Insere uma nova espécie animal (ex: Cão, Gato, Ave).
-- Exceções específicas: DUP_VAL_ON_INDEX (nome duplicado),
--                       VALUE_ERROR (tamanho de campo inválido)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PRC_INSERT_ESPECIE (
    p_nm_especie IN ESPECIE.NM_ESPECIE%TYPE
) AS
    c_proc CONSTANT VARCHAR2(120) := 'PRC_INSERT_ESPECIE';
BEGIN
    INSERT INTO ESPECIE (ID_ESPECIE, NM_ESPECIE, DT_CRIACAO)
    VALUES (SEQ_ESPECIE.NEXTVAL, p_nm_especie, SYSTIMESTAMP);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Espécie inserida: ' || p_nm_especie);

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'DUP_VAL_ON_INDEX: Espécie já cadastrada. ' || SQLERRM,
                'NM_ESPECIE=' || p_nm_especie);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Espécie duplicada — log gravado.');

    WHEN VALUE_ERROR THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'VALUE_ERROR: Nome da espécie inválido. ' || SQLERRM,
                'NM_ESPECIE=' || p_nm_especie);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Valor inválido — log gravado.');

    WHEN OTHERS THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'OTHERS: ' || SQLERRM,
                'NM_ESPECIE=' || p_nm_especie);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Erro inesperado — log gravado.');
END PRC_INSERT_ESPECIE;
/

-- ----------------------------------------------------------------------------
-- PROCEDURE 3 — PRC_INSERT_VETERINARIO
-- Insere um veterinário vinculado a uma clínica.
-- Exceções específicas: DUP_VAL_ON_INDEX (CRMV ou e-mail duplicado),
--                       NO_DATA_FOUND (clínica não encontrada — validação prévia)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PRC_INSERT_VETERINARIO (
    p_id_clinica      IN VETERINARIO.ID_CLINICA%TYPE,
    p_nm_veterinario  IN VETERINARIO.NM_VETERINARIO%TYPE,
    p_nr_crmv         IN VETERINARIO.NR_CRMV%TYPE,
    p_ds_email        IN VETERINARIO.DS_EMAIL%TYPE,
    p_nr_telefone     IN VETERINARIO.NR_TELEFONE%TYPE
) AS
    c_proc CONSTANT VARCHAR2(120) := 'PRC_INSERT_VETERINARIO';
    v_id_clinica_chk  NUMBER(10);
BEGIN
    -- Validação explícita da FK antes do insert
    -- (gera NO_DATA_FOUND se a clínica não existir)
    SELECT ID_CLINICA INTO v_id_clinica_chk
    FROM   CLINICA
    WHERE  ID_CLINICA = p_id_clinica
      AND  ST_ATIVA   = 'S';

    INSERT INTO VETERINARIO (
        ID_VETERINARIO, ID_CLINICA, NM_VETERINARIO,
        NR_CRMV, DS_EMAIL, NR_TELEFONE, ST_ATIVO, DT_CRIACAO
    ) VALUES (
        SEQ_VETERINARIO.NEXTVAL, p_id_clinica, p_nm_veterinario,
        p_nr_crmv, p_ds_email, p_nr_telefone, 'S', SYSTIMESTAMP
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Veterinário inserido: ' || p_nm_veterinario || ' CRMV: ' || p_nr_crmv);

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'DUP_VAL_ON_INDEX: CRMV ou e-mail já cadastrado. ' || SQLERRM,
                'NR_CRMV=' || p_nr_crmv || ' | DS_EMAIL=' || p_ds_email);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Veterinário duplicado — log gravado.');

    -- Exceção específica 2: clínica inexistente ou inativa
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'NO_DATA_FOUND: Clínica inexistente ou inativa. ' || SQLERRM,
                'ID_CLINICA=' || p_id_clinica);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Clínica não encontrada — log gravado.');

    WHEN OTHERS THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'OTHERS: ' || SQLERRM,
                'NM_VETERINARIO=' || p_nm_veterinario || ' | ID_CLINICA=' || p_id_clinica);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Erro inesperado — log gravado.');
END PRC_INSERT_VETERINARIO;
/

-- ----------------------------------------------------------------------------
-- PROCEDURE 4 — PRC_INSERT_TUTOR
-- Insere um tutor (responsável pelo pet) vinculado a uma clínica.
-- Exceções específicas: DUP_VAL_ON_INDEX (CPF ou e-mail duplicado),
--                       VALUE_ERROR (formato/tamanho de campo inválido)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PRC_INSERT_TUTOR (
    p_id_clinica   IN TUTOR.ID_CLINICA%TYPE,
    p_nm_tutor     IN TUTOR.NM_TUTOR%TYPE,
    p_nr_cpf       IN TUTOR.NR_CPF%TYPE,
    p_ds_email     IN TUTOR.DS_EMAIL%TYPE,
    p_ds_telefone  IN TUTOR.DS_TELEFONE%TYPE,
    p_ds_whatsapp  IN TUTOR.DS_WHATSAPP%TYPE,
    p_nm_cidade    IN TUTOR.NM_CIDADE%TYPE,
    p_sg_uf        IN TUTOR.SG_UF%TYPE
) AS
    c_proc CONSTANT VARCHAR2(120) := 'PRC_INSERT_TUTOR';
BEGIN
    INSERT INTO TUTOR (
        ID_TUTOR, ID_CLINICA, NM_TUTOR, NR_CPF,
        DS_EMAIL, DS_TELEFONE, DS_WHATSAPP,
        NM_CIDADE, SG_UF,
        DT_CADASTRO, ST_ATIVO, ST_AVISO_PRIVACIDADE
    ) VALUES (
        SEQ_TUTOR.NEXTVAL, p_id_clinica, p_nm_tutor, p_nr_cpf,
        p_ds_email, p_ds_telefone, p_ds_whatsapp,
        p_nm_cidade, p_sg_uf,
        SYSTIMESTAMP, 'S', 'N'
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Tutor inserido: ' || p_nm_tutor || ' CPF: ' || p_nr_cpf);

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'DUP_VAL_ON_INDEX: CPF ou e-mail já cadastrado. ' || SQLERRM,
                'NR_CPF=' || p_nr_cpf || ' | DS_EMAIL=' || p_ds_email);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Tutor duplicado — log gravado.');

    WHEN VALUE_ERROR THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'VALUE_ERROR: Dado com tipo ou tamanho inválido. ' || SQLERRM,
                'NM_TUTOR=' || p_nm_tutor || ' | SG_UF=' || p_sg_uf);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Valor inválido — log gravado.');

    WHEN OTHERS THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'OTHERS: ' || SQLERRM,
                'NM_TUTOR=' || p_nm_tutor || ' | ID_CLINICA=' || p_id_clinica);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Erro inesperado — log gravado.');
END PRC_INSERT_TUTOR;
/

-- ----------------------------------------------------------------------------
-- PROCEDURE 5 — PRC_INSERT_PET
-- Insere um pet vinculado a uma clínica e espécie.
-- Exceções específicas: NO_DATA_FOUND (espécie não encontrada),
--                       VALUE_ERROR (sexo ou porte fora dos domínios M/F e P/M/G)
--
-- NOTA: O CHECK CONSTRAINT do banco (CK_PET_SEXO, CK_PET_PORTE) é a barreira
-- final, mas validamos antes para dar mensagem semântica no log.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PRC_INSERT_PET (
    p_id_clinica   IN PET.ID_CLINICA%TYPE,
    p_id_especie   IN PET.ID_ESPECIE%TYPE,
    p_id_raca      IN PET.ID_RACA%TYPE,
    p_nm_pet       IN PET.NM_PET%TYPE,
    p_dt_nascim    IN PET.DT_NASCIMENTO%TYPE,
    p_sg_sexo      IN PET.SG_SEXO%TYPE,
    p_sg_porte     IN PET.SG_PORTE%TYPE
) AS
    c_proc CONSTANT VARCHAR2(120) := 'PRC_INSERT_PET';
    v_id_especie_chk NUMBER(10);
BEGIN
    -- Validação semântica de sexo e porte antes de tentar o INSERT
    -- (evita ORA-02290 do CHECK e gera log mais legível)
    IF p_sg_sexo NOT IN ('M', 'F') OR p_sg_porte NOT IN ('P', 'M', 'G') THEN
        -- Lançamos VALUE_ERROR explicitamente para cair no handler abaixo
        RAISE VALUE_ERROR;
    END IF;

    -- Validação da espécie (gera NO_DATA_FOUND se inexistente)
    SELECT ID_ESPECIE INTO v_id_especie_chk
    FROM   ESPECIE
    WHERE  ID_ESPECIE = p_id_especie;

    INSERT INTO PET (
        ID_PET, ID_CLINICA, ID_ESPECIE, ID_RACA,
        NM_PET, DT_NASCIMENTO, SG_SEXO, SG_PORTE,
        ST_ATIVO, DT_CRIACAO
    ) VALUES (
        SEQ_PET.NEXTVAL, p_id_clinica, p_id_especie, p_id_raca,
        p_nm_pet, p_dt_nascim, p_sg_sexo, p_sg_porte,
        'S', SYSTIMESTAMP
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Pet inserido: ' || p_nm_pet
                         || ' | Sexo: ' || p_sg_sexo
                         || ' | Porte: ' || p_sg_porte);

EXCEPTION
    -- Espécie não encontrada
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'NO_DATA_FOUND: Espécie não encontrada. ' || SQLERRM,
                'ID_ESPECIE=' || p_id_especie || ' | NM_PET=' || p_nm_pet);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Espécie inválida — log gravado.');

    -- Sexo ou porte inválido (lançado manualmente acima ou pelo CHECK)
    WHEN VALUE_ERROR THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                -6502, 'VALUE_ERROR: SG_SEXO deve ser M/F; SG_PORTE deve ser P/M/G.',
                'NM_PET=' || p_nm_pet || ' | SG_SEXO=' || p_sg_sexo
                || ' | SG_PORTE=' || p_sg_porte);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Sexo ou porte inválido — log gravado.');

    WHEN OTHERS THEN
        ROLLBACK;
        INSERT INTO LOG_ERRO (ID_LOG, NM_PROCEDURE, NM_USUARIO, DT_ERRO,
                              NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS)
        VALUES (SEQ_LOG_ERRO.NEXTVAL, c_proc, USER, SYSTIMESTAMP,
                SQLCODE, 'OTHERS: ' || SQLERRM,
                'NM_PET=' || p_nm_pet || ' | ID_CLINICA=' || p_id_clinica);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[ERRO] Erro inesperado — log gravado.');
END PRC_INSERT_PET;
/

-- ============================================================================
-- BLOCO DE CHAMADA — Carga de dados de demonstração
-- Execute após criar as procedures acima.
-- ============================================================================
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== CARGA KURA — Início ===');

    -- Clínicas
    PRC_INSERT_CLINICA('Clínica VetCare SP',   '12.345.678/0001-01',
        'VetCare Ltda', 'Av. Paulista, 1000', 'São Paulo', 'SP', '01310-100',
        '(11)3001-0001', 'contato@vetcare.com.br',
        'admin@vetcare.com.br', '$2b$12$HASHCLINICA01');

    PRC_INSERT_CLINICA('Pet Saúde Vila Mariana','98.765.432/0001-02',
        'Pet Saúde SS Ltda', 'Rua Domingos de Morais, 500', 'São Paulo', 'SP', '04010-020',
        '(11)3002-0002', 'contato@petsaude.com.br',
        'admin@petsaude.com.br', '$2b$12$HASHCLINICA02');

    -- Espécies
    PRC_INSERT_ESPECIE('Cão');
    PRC_INSERT_ESPECIE('Gato');
    PRC_INSERT_ESPECIE('Ave');

    DBMS_OUTPUT.PUT_LINE('=== CARGA KURA — Clínicas e Espécies OK ===');

    -- Veterinários (assumindo ID_CLINICA = 1 gerado pela SEQ)
    PRC_INSERT_VETERINARIO(1, 'Dr. Marcos Andrade',   'SP-12345', 'marcos@vetcare.com.br',   '(11)99001-0001');
    PRC_INSERT_VETERINARIO(1, 'Dra. Ana Lima',        'SP-67890', 'ana@vetcare.com.br',       '(11)99001-0002');
    PRC_INSERT_VETERINARIO(2, 'Dr. Carlos Mendonça',  'SP-11223', 'carlos@petsaude.com.br',  '(11)99002-0001');

    -- Tutores
    PRC_INSERT_TUTOR(1, 'Felipe Ferrete',  '12345678901', 'felipe@email.com',  '(11)98000-0001', '(11)98000-0001', 'São Paulo', 'SP');
    PRC_INSERT_TUTOR(1, 'Bosak Gustavo',   '23456789012', 'bosak@email.com',   '(11)98000-0002', '(11)98000-0002', 'São Paulo', 'SP');
    PRC_INSERT_TUTOR(2, 'Nikolas Brisola', '34567890123', 'nikolas@email.com', '(11)98000-0003', '(11)98000-0003', 'Campinas',  'SP');

    DBMS_OUTPUT.PUT_LINE('=== CARGA KURA — Veterinários e Tutores OK ===');

    -- Pets (espécie 1=Cão, 2=Gato, SEM raça — p_id_raca=NULL ok pela DDL)
    PRC_INSERT_PET(1, 1, NULL, 'Thor',   DATE '2020-03-15', 'M', 'G');
    PRC_INSERT_PET(1, 2, NULL, 'Mia',    DATE '2021-07-22', 'F', 'P');
    PRC_INSERT_PET(2, 1, NULL, 'Rex',    DATE '2019-11-05', 'M', 'M');
    PRC_INSERT_PET(2, 2, NULL, 'Luna',   DATE '2022-01-30', 'F', 'P');
    PRC_INSERT_PET(1, 1, NULL, 'Hulk',   DATE '2018-06-10', 'M', 'G');

    DBMS_OUTPUT.PUT_LINE('=== CARGA KURA — Pets OK ===');
    DBMS_OUTPUT.PUT_LINE('=== CARGA KURA — Concluída ===');
END;
/
