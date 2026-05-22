-- ============================================================================
-- KURA — Sistema de Gestão Veterinária | Clyvo Vet / FIAP Challenge 2026
-- DISCIPLINA: Mastering Relational and Non-Relational Database
-- REQUISITO 3: Relatório Analítico com LAG e LEAD (20 pts)
--
-- Tabela usada: LEITURA_TEMPERATURA (time-series dos sensores IoT)
-- Colunas exibidas:
--   ID_LEITURA    — identificador da leitura
--   DT_LEITURA    — momento da coleta
--   VL_ANTERIOR   — temperatura da leitura anterior (LAG)  ou 'Vazio'
--   VL_ATUAL      — temperatura desta leitura
--   VL_PROXIMO    — temperatura da próxima leitura (LEAD) ou 'Vazio'
--   VL_UMIDADE    — umidade registrada (quando disponível)
--
-- Função analítica LAG:  acessa a linha ANTERIOR dentro da partição
-- Função analítica LEAD: acessa a próxima linha dentro da partição
-- Particionado por ID_DISPOSITIVO_IOT, ordenado por DT_LEITURA
-- ============================================================================

-- ============================================================================
-- BLOCO DE CARGA DE DEMONSTRAÇÃO (execute antes do relatório)
-- Insere um dispositivo e pelo menos 7 leituras para garantir ≥ 5 linhas
-- com valores anterior E próximo não-nulos (posições 2 a 6).
-- ============================================================================
DECLARE
    v_id_disp   NUMBER(10);
    v_id_clinica NUMBER(10);
BEGIN
    -- Usa a primeira clínica já carregada
    SELECT MIN(ID_CLINICA) INTO v_id_clinica FROM CLINICA;

    -- Insere dispositivo IoT (sensor de temperatura da sala de recuperação)
    INSERT INTO DISPOSITIVO_IOT (
        ID_DISPOSITIVO, ID_CLINICA, CD_DISPOSITIVO,
        DS_DESCRICAO, DS_LOCALIZACAO, DT_CRIACAO
    ) VALUES (
        SEQ_DISPOSITIVO_IOT.NEXTVAL, v_id_clinica, 'ESP32-KURA-01',
        'Sensor DHT22 — Sala de Recuperação', 'Sala 3 / Prateleira B',
        SYSTIMESTAMP
    ) RETURNING ID_DISPOSITIVO INTO v_id_disp;

    -- Insere 7 leituras espaçadas em 1 minuto (simula série temporal real)
    INSERT INTO LEITURA_TEMPERATURA (ID_LEITURA, ID_DISPOSITIVO_IOT, VL_TEMPERATURA, VL_UMIDADE, DT_LEITURA)
    VALUES (SEQ_LEITURA_TEMP.NEXTVAL, v_id_disp, 21.50, 65.0, SYSTIMESTAMP - INTERVAL '6' MINUTE);

    INSERT INTO LEITURA_TEMPERATURA (ID_LEITURA, ID_DISPOSITIVO_IOT, VL_TEMPERATURA, VL_UMIDADE, DT_LEITURA)
    VALUES (SEQ_LEITURA_TEMP.NEXTVAL, v_id_disp, 22.10, 64.5, SYSTIMESTAMP - INTERVAL '5' MINUTE);

    INSERT INTO LEITURA_TEMPERATURA (ID_LEITURA, ID_DISPOSITIVO_IOT, VL_TEMPERATURA, VL_UMIDADE, DT_LEITURA)
    VALUES (SEQ_LEITURA_TEMP.NEXTVAL, v_id_disp, 23.80, 63.0, SYSTIMESTAMP - INTERVAL '4' MINUTE);

    INSERT INTO LEITURA_TEMPERATURA (ID_LEITURA, ID_DISPOSITIVO_IOT, VL_TEMPERATURA, VL_UMIDADE, DT_LEITURA)
    VALUES (SEQ_LEITURA_TEMP.NEXTVAL, v_id_disp, 27.40, 60.2, SYSTIMESTAMP - INTERVAL '3' MINUTE);  -- pico

    INSERT INTO LEITURA_TEMPERATURA (ID_LEITURA, ID_DISPOSITIVO_IOT, VL_TEMPERATURA, VL_UMIDADE, DT_LEITURA)
    VALUES (SEQ_LEITURA_TEMP.NEXTVAL, v_id_disp, 26.90, 61.0, SYSTIMESTAMP - INTERVAL '2' MINUTE);

    INSERT INTO LEITURA_TEMPERATURA (ID_LEITURA, ID_DISPOSITIVO_IOT, VL_TEMPERATURA, VL_UMIDADE, DT_LEITURA)
    VALUES (SEQ_LEITURA_TEMP.NEXTVAL, v_id_disp, 25.20, 62.5, SYSTIMESTAMP - INTERVAL '1' MINUTE);

    INSERT INTO LEITURA_TEMPERATURA (ID_LEITURA, ID_DISPOSITIVO_IOT, VL_TEMPERATURA, VL_UMIDADE, DT_LEITURA)
    VALUES (SEQ_LEITURA_TEMP.NEXTVAL, v_id_disp, 24.00, 63.8, SYSTIMESTAMP);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Dispositivo e leituras inseridos. ID_DISP=' || v_id_disp);
END;
/

-- ============================================================================
-- BLOCO ANALÍTICO — LAG e LEAD sobre LEITURA_TEMPERATURA
-- ============================================================================
DECLARE
    -- Cursor que usa funções de janela (analíticas) Oracle:
    --   LAG()  → valor da linha ANTERIOR na partição ordenada por DT_LEITURA
    --   LEAD() → valor da PRÓXIMA linha na partição
    -- DEFAULT NULL → quando não há linha anterior/próxima, retorna NULL
    -- Depois tratamos NULL como 'Vazio' no relatório.
    CURSOR c_analise IS
        SELECT
            lt.ID_LEITURA,
            lt.ID_DISPOSITIVO_IOT,
            d.CD_DISPOSITIVO,
            TO_CHAR(lt.DT_LEITURA, 'DD/MM/YYYY HH24:MI:SS')   AS DT_LEITURA_FMT,
            lt.VL_TEMPERATURA                                   AS VL_ATUAL,
            lt.VL_UMIDADE,
            -- LAG: temperatura da leitura anterior (NULL se primeira linha)
            LAG(lt.VL_TEMPERATURA, 1, NULL)
                OVER (PARTITION BY lt.ID_DISPOSITIVO_IOT
                      ORDER BY lt.DT_LEITURA)                   AS VL_ANTERIOR,
            -- LEAD: temperatura da próxima leitura (NULL se última linha)
            LEAD(lt.VL_TEMPERATURA, 1, NULL)
                OVER (PARTITION BY lt.ID_DISPOSITIVO_IOT
                      ORDER BY lt.DT_LEITURA)                   AS VL_PROXIMO
        FROM   LEITURA_TEMPERATURA lt
        JOIN   DISPOSITIVO_IOT     d  ON d.ID_DISPOSITIVO = lt.ID_DISPOSITIVO_IOT
        ORDER  BY lt.ID_DISPOSITIVO_IOT, lt.DT_LEITURA;

    -- Variáveis de fetch
    v_id_leitura    LEITURA_TEMPERATURA.ID_LEITURA%TYPE;
    v_id_disp       DISPOSITIVO_IOT.ID_DISPOSITIVO%TYPE;
    v_cd_disp       DISPOSITIVO_IOT.CD_DISPOSITIVO%TYPE;
    v_dt_leitura    VARCHAR2(25);
    v_vl_atual      NUMBER(5,2);
    v_vl_umidade    NUMBER(5,2);
    v_vl_anterior   NUMBER(5,2);
    v_vl_proximo    NUMBER(5,2);

    -- Strings formatadas para exibição (converte NULL → 'Vazio')
    v_str_anterior  VARCHAR2(10);
    v_str_proximo   VARCHAR2(10);
    v_str_umidade   VARCHAR2(10);

    -- Alerta visual de pico de temperatura (>= 27 °C)
    v_alerta        VARCHAR2(20);
    v_disp_anterior NUMBER(10) := -1;
    v_linha_count   NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('════════════════════════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE(' RELATÓRIO C — SÉRIE TEMPORAL DE TEMPERATURA (LAG / LEAD)');
    DBMS_OUTPUT.PUT_LINE(' Sensor: IoT Sala de Recuperação | Kura Vet / Clyvo');
    DBMS_OUTPUT.PUT_LINE('════════════════════════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 8)     ||
        RPAD('DATA/HORA',           22) ||
        RPAD('ANTERIOR (°C)', 15)   ||
        RPAD('ATUAL (°C)',    12)   ||
        RPAD('PRÓXIMO (°C)', 14)   ||
        RPAD('UMIDADE %',   10)    ||
        'ALERTA'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));

    OPEN c_analise;
    LOOP
        FETCH c_analise INTO
            v_id_leitura, v_id_disp, v_cd_disp, v_dt_leitura,
            v_vl_atual, v_vl_umidade, v_vl_anterior, v_vl_proximo;
        EXIT WHEN c_analise%NOTFOUND;

        -- Cabeçalho por dispositivo (suporte multi-dispositivo)
        IF v_id_disp != v_disp_anterior THEN
            DBMS_OUTPUT.PUT_LINE('>> Dispositivo: ' || v_cd_disp
                || ' (ID=' || v_id_disp || ')');
            DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));
            v_disp_anterior := v_id_disp;
        END IF;

        -- Trata NULL como 'Vazio' conforme enunciado FIAP
        v_str_anterior := CASE WHEN v_vl_anterior IS NULL THEN 'Vazio'
                               ELSE TO_CHAR(v_vl_anterior, 'FM999.99') END;

        v_str_proximo  := CASE WHEN v_vl_proximo  IS NULL THEN 'Vazio'
                               ELSE TO_CHAR(v_vl_proximo,  'FM999.99') END;

        v_str_umidade  := CASE WHEN v_vl_umidade  IS NULL THEN 'N/D'
                               ELSE TO_CHAR(v_vl_umidade,  'FM999.99') || '%' END;

        -- Decisão de alerta: pico >= 27 °C dispara ALERTA_ALTA
        v_alerta := CASE
            WHEN v_vl_atual >= 27 THEN '*** ALTA ***'
            WHEN v_vl_atual >= 25 THEN '! Atenção'
            ELSE 'Normal'
        END;

        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_id_leitura, 8)    ||
            RPAD(v_dt_leitura, 22)   ||
            RPAD(v_str_anterior, 15) ||
            RPAD(v_vl_atual, 12)     ||
            RPAD(v_str_proximo, 14)  ||
            RPAD(v_str_umidade, 10)  ||
            v_alerta
        );

        v_linha_count := v_linha_count + 1;
    END LOOP;
    CLOSE c_analise;

    DBMS_OUTPUT.PUT_LINE(RPAD('═', 90, '═'));
    DBMS_OUTPUT.PUT_LINE('Total de leituras exibidas: ' || v_linha_count);
    DBMS_OUTPUT.PUT_LINE('Legenda: Anterior/Próximo = "Vazio" quando não existe linha adjacente.');
    DBMS_OUTPUT.PUT_LINE('');
END;
/
