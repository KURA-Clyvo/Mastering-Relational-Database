-- ============================================================================
-- KURA — Sistema de Gestão Veterinária | Clyvo Vet / FIAP Challenge 2026
-- DISCIPLINA: Mastering Relational and Non-Relational Database
-- REQUISITO 2: Blocos Anônimos com JOINs (≥3 tabelas), GROUP BY e ORDER BY (20pts)
--
-- BLOCO A: Distribuição de Pets por Espécie e Clínica
--           Tabelas: PET ⟶ ESPECIE ⟶ CLINICA
-- BLOCO B: Resumo de Agendamentos por Status e Veterinário
--           Tabelas: AGENDAMENTO ⟶ VETERINARIO ⟶ CLINICA
-- ============================================================================

-- ============================================================================
-- BLOCO A — Distribuição de Pets por Espécie e Clínica
-- Tabelas unidas: PET · ESPECIE · CLINICA (3 JOINs)
-- Agrupamento: por clínica e espécie
-- Ordenação: clínica ascendente, total descrescente
-- ============================================================================
DECLARE
    -- Cursor com a query analítica
    CURSOR c_pets_especie IS
        SELECT
            c.NM_CLINICA,
            e.NM_ESPECIE,
            COUNT(p.ID_PET)        AS QT_PETS,
            SUM(CASE WHEN p.SG_SEXO = 'M' THEN 1 ELSE 0 END) AS QT_MACHOS,
            SUM(CASE WHEN p.SG_SEXO = 'F' THEN 1 ELSE 0 END) AS QT_FEMEAS,
            SUM(CASE WHEN p.SG_PORTE = 'P' THEN 1 ELSE 0 END) AS QT_PEQUENO,
            SUM(CASE WHEN p.SG_PORTE = 'M' THEN 1 ELSE 0 END) AS QT_MEDIO,
            SUM(CASE WHEN p.SG_PORTE = 'G' THEN 1 ELSE 0 END) AS QT_GRANDE
        FROM   PET     p
        JOIN   ESPECIE e ON e.ID_ESPECIE = p.ID_ESPECIE   -- JOIN 1
        JOIN   CLINICA c ON c.ID_CLINICA = p.ID_CLINICA   -- JOIN 2
        WHERE  p.ST_ATIVO = 'S'
        GROUP BY c.NM_CLINICA, e.NM_ESPECIE               -- GROUP BY
        ORDER BY c.NM_CLINICA ASC, QT_PETS DESC;          -- ORDER BY

    -- Variáveis de recepção do cursor
    v_nm_clinica  CLINICA.NM_CLINICA%TYPE;
    v_nm_especie  ESPECIE.NM_ESPECIE%TYPE;
    v_qt_pets     NUMBER;
    v_qt_machos   NUMBER;
    v_qt_femeas   NUMBER;
    v_qt_peq      NUMBER;
    v_qt_med      NUMBER;
    v_qt_grd      NUMBER;

    -- Controle de clínica anterior (para imprimir separador entre clínicas)
    v_clinica_anterior VARCHAR2(120) := '***NENHUMA***';
    v_total_geral      NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('════════════════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE(' RELATÓRIO A — DISTRIBUIÇÃO DE PETS POR ESPÉCIE E CLÍNICA');
    DBMS_OUTPUT.PUT_LINE('════════════════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE(RPAD('CLÍNICA', 30) || RPAD('ESPÉCIE', 10)
        || RPAD('TOTAL', 7) || RPAD('MACHOS', 8) || RPAD('FÊMEAS', 8)
        || RPAD('PEQ.', 6)  || RPAD('MÉD.', 6)  || 'GRD.');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));

    OPEN c_pets_especie;
    LOOP
        FETCH c_pets_especie INTO
            v_nm_clinica, v_nm_especie, v_qt_pets,
            v_qt_machos, v_qt_femeas, v_qt_peq, v_qt_med, v_qt_grd;
        EXIT WHEN c_pets_especie%NOTFOUND;

        -- Separador visual entre clínicas distintas
        IF v_nm_clinica != v_clinica_anterior THEN
            IF v_clinica_anterior != '***NENHUMA***' THEN
                DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
            END IF;
            v_clinica_anterior := v_nm_clinica;
        END IF;

        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_nm_clinica, 30) || RPAD(v_nm_especie, 10)
            || RPAD(v_qt_pets,    7) || RPAD(v_qt_machos,  8)
            || RPAD(v_qt_femeas,  8) || RPAD(v_qt_peq,     6)
            || RPAD(v_qt_med,     6) || v_qt_grd
        );

        v_total_geral := v_total_geral + v_qt_pets;
    END LOOP;
    CLOSE c_pets_especie;

    DBMS_OUTPUT.PUT_LINE(RPAD('═', 80, '═'));
    DBMS_OUTPUT.PUT_LINE(RPAD('TOTAL GERAL DE PETS ATIVOS:', 50) || v_total_geral);
    DBMS_OUTPUT.PUT_LINE('');
END;
/

-- ============================================================================
-- BLOCO B — Resumo de Agendamentos por Status, Veterinário e Clínica
-- Tabelas unidas: AGENDAMENTO · VETERINARIO · CLINICA (3 JOINs)
-- Agrupamento: por clínica, veterinário e status
-- Ordenação: clínica, veterinário, total desc
-- ============================================================================
DECLARE
    CURSOR c_agendamentos IS
        SELECT
            c.NM_CLINICA,
            v.NM_VETERINARIO,
            a.ST_STATUS,
            COUNT(a.ID_AGENDAMENTO)  AS QT_AGEND,
            MIN(a.DT_AGENDAMENTO)    AS DT_MAIS_ANTIGO,
            MAX(a.DT_AGENDAMENTO)    AS DT_MAIS_RECENTE
        FROM   AGENDAMENTO  a
        JOIN   VETERINARIO  v ON v.ID_VETERINARIO = a.ID_VETERINARIO  -- JOIN 1
        JOIN   CLINICA      c ON c.ID_CLINICA     = a.ID_CLINICA       -- JOIN 2
        WHERE  a.DT_AGENDAMENTO >= ADD_MONTHS(SYSTIMESTAMP, -12)       -- último ano
        GROUP BY c.NM_CLINICA, v.NM_VETERINARIO, a.ST_STATUS          -- GROUP BY
        ORDER BY c.NM_CLINICA, v.NM_VETERINARIO, QT_AGEND DESC;       -- ORDER BY

    v_nm_clinica     CLINICA.NM_CLINICA%TYPE;
    v_nm_vet         VETERINARIO.NM_VETERINARIO%TYPE;
    v_st_status      AGENDAMENTO.ST_STATUS%TYPE;
    v_qt_agend       NUMBER;
    v_dt_antigo      TIMESTAMP;
    v_dt_recente     TIMESTAMP;
    v_vet_anterior   VARCHAR2(200) := '***NENHUM***';
    v_total_geral    NUMBER := 0;
    v_subtotal_vet   NUMBER := 0;
    v_label_status   VARCHAR2(30);
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('════════════════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE(' RELATÓRIO B — AGENDAMENTOS POR STATUS / VETERINÁRIO / CLÍNICA');
    DBMS_OUTPUT.PUT_LINE(' Período: últimos 12 meses');
    DBMS_OUTPUT.PUT_LINE('════════════════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE(RPAD('CLÍNICA', 28) || RPAD('VETERINÁRIO', 25)
        || RPAD('STATUS', 18) || RPAD('QTD', 6)
        || RPAD('MAIS ANTIGO', 22) || 'MAIS RECENTE');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 105, '-'));

    OPEN c_agendamentos;
    LOOP
        FETCH c_agendamentos INTO
            v_nm_clinica, v_nm_vet, v_st_status,
            v_qt_agend, v_dt_antigo, v_dt_recente;
        EXIT WHEN c_agendamentos%NOTFOUND;

        -- Subtotal por veterinário ao trocar
        IF v_nm_vet != v_vet_anterior THEN
            IF v_vet_anterior != '***NENHUM***' THEN
                DBMS_OUTPUT.PUT_LINE(RPAD(' ', 53) || RPAD('Sub-Total Vet:', 18)
                    || v_subtotal_vet);
                DBMS_OUTPUT.PUT_LINE(RPAD('-', 105, '-'));
            END IF;
            v_vet_anterior := v_nm_vet;
            v_subtotal_vet := 0;
        END IF;

        -- Tradução semântica do status para o relatório
        v_label_status := CASE v_st_status
            WHEN 'AGENDADO'       THEN 'Agendado'
            WHEN 'CONFIRMADO'     THEN 'Confirmado'
            WHEN 'REALIZADO'      THEN 'Realizado'
            WHEN 'CANCELADO'      THEN '*** Cancelado'
            WHEN 'NAO_COMPARECEU' THEN '** Não Compareceu'
            WHEN 'INTENCAO'       THEN 'Intenção'
            ELSE v_st_status
        END;

        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_nm_clinica, 28) || RPAD(v_nm_vet, 25)
            || RPAD(v_label_status, 18) || RPAD(v_qt_agend, 6)
            || RPAD(TO_CHAR(v_dt_antigo,  'DD/MM/YYYY'), 22)
            || TO_CHAR(v_dt_recente, 'DD/MM/YYYY')
        );

        v_subtotal_vet := v_subtotal_vet + v_qt_agend;
        v_total_geral  := v_total_geral  + v_qt_agend;
    END LOOP;

    -- Subtotal do último veterinário
    IF v_vet_anterior != '***NENHUM***' THEN
        DBMS_OUTPUT.PUT_LINE(RPAD(' ', 53) || RPAD('Sub-Total Vet:', 18)
            || v_subtotal_vet);
    END IF;

    CLOSE c_agendamentos;

    DBMS_OUTPUT.PUT_LINE(RPAD('═', 105, '═'));
    DBMS_OUTPUT.PUT_LINE(RPAD('TOTAL GERAL DE AGENDAMENTOS (12 meses):', 71) || v_total_geral);
    DBMS_OUTPUT.PUT_LINE('');
END;
/
