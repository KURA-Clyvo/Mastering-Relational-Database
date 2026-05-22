-- ============================================================================
-- KURA — Sistema de Gestão Veterinária | Clyvo Vet / FIAP Challenge 2026
-- DISCIPLINA: Mastering Relational and Non-Relational Database
-- REQUISITO 4: 4 Blocos Anônimos com Cursor Explícito + IF/CASE (20 pts)
--
-- BLOCO I   — Clínicas: Sub-Total e Total Geral de Veterinários por Clínica
--             (OBRIGATÓRIO: Sub-Total + Total Geral — rubrica FIAP)
-- BLOCO II  — Pets: Classificação por Porte e Idade com tomada de decisão
-- BLOCO III — Agendamentos: Status atual + decisão de criticidade
-- BLOCO IV  — Temperatura: Alertas de leitura com classificação por faixa
-- ============================================================================

-- ============================================================================
-- BLOCO I — Sub-Total e Total Geral de Veterinários por Clínica (OBRIGATÓRIO)
-- Estrutura: Clínica A → Sub-Total → Clínica B → Sub-Total → Total Geral
-- Tomada de decisão: classifica a clínica pelo volume de veterinários
-- ============================================================================
DECLARE
    CURSOR c_vet_clinica IS
        SELECT
            c.ID_CLINICA,
            c.NM_CLINICA,
            v.ID_VETERINARIO,
            v.NM_VETERINARIO,
            v.NR_CRMV,
            v.ST_ATIVO
        FROM   CLINICA    c
        JOIN   VETERINARIO v ON v.ID_CLINICA = c.ID_CLINICA
        WHERE  c.ST_ATIVA  = 'S'
        ORDER BY c.NM_CLINICA, v.NM_VETERINARIO;

    v_id_clinica         CLINICA.ID_CLINICA%TYPE;
    v_nm_clinica         CLINICA.NM_CLINICA%TYPE;
    v_id_vet             VETERINARIO.ID_VETERINARIO%TYPE;
    v_nm_vet             VETERINARIO.NM_VETERINARIO%TYPE;
    v_nr_crmv            VETERINARIO.NR_CRMV%TYPE;
    v_st_ativo           VETERINARIO.ST_ATIVO%TYPE;

    -- Controle de grupo
    v_clinica_anterior   CLINICA.ID_CLINICA%TYPE := -1;
    v_nm_clinica_ant     CLINICA.NM_CLINICA%TYPE := '***';
    v_subtotal_ativos    NUMBER := 0;
    v_subtotal_inativos  NUMBER := 0;
    v_subtotal_total     NUMBER := 0;
    v_total_geral        NUMBER := 0;
    v_classificacao      VARCHAR2(30);
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('████████████████████████████████████████████████████████████████████████');
    DBMS_OUTPUT.PUT_LINE(' RELATÓRIO I — VETERINÁRIOS POR CLÍNICA (SUB-TOTAL / TOTAL GERAL)');
    DBMS_OUTPUT.PUT_LINE('████████████████████████████████████████████████████████████████████████');

    OPEN c_vet_clinica;
    LOOP
        FETCH c_vet_clinica INTO
            v_id_clinica, v_nm_clinica, v_id_vet,
            v_nm_vet, v_nr_crmv, v_st_ativo;
        EXIT WHEN c_vet_clinica%NOTFOUND;

        -- Quebra de grupo: nova clínica detectada
        IF v_id_clinica != v_clinica_anterior THEN

            -- Imprime Sub-Total da clínica anterior (exceto na 1ª iteração)
            IF v_clinica_anterior != -1 THEN
                -- TOMADA DE DECISÃO: classifica a clínica pelo total de vets
                IF    v_subtotal_total >= 5 THEN v_classificacao := 'Grande Porte';
                ELSIF v_subtotal_total >= 3 THEN v_classificacao := 'Médio Porte';
                ELSE                             v_classificacao := 'Pequeno Porte';
                END IF;

                DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '┌───────────────────────────────────┐');
                DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│ Sub-Total [' || v_nm_clinica_ant || ']');
                DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│   Ativos   : ' || v_subtotal_ativos);
                DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│   Inativos : ' || v_subtotal_inativos);
                DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│   Total    : ' || v_subtotal_total);
                DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│   Porte    : ' || v_classificacao);
                DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '└───────────────────────────────────┘');
                DBMS_OUTPUT.PUT_LINE('');

                -- Acumula no total geral
                v_total_geral := v_total_geral + v_subtotal_total;
            END IF;

            -- Reset dos contadores de sub-grupo
            v_subtotal_ativos   := 0;
            v_subtotal_inativos := 0;
            v_subtotal_total    := 0;
            v_clinica_anterior  := v_id_clinica;
            v_nm_clinica_ant    := v_nm_clinica;

            -- Cabeçalho da nova clínica
            DBMS_OUTPUT.PUT_LINE('┌── Clínica: ' || v_nm_clinica || ' (ID=' || v_id_clinica || ')');
            DBMS_OUTPUT.PUT_LINE(RPAD('   VETERINÁRIO', 35)
                || RPAD('CRMV', 15) || 'STATUS');
            DBMS_OUTPUT.PUT_LINE(RPAD('   ' || RPAD('-', 32, '-'), 35)
                || RPAD('-----------', 15) || '--------');
        END IF;

        -- Impressão da linha do veterinário
        DBMS_OUTPUT.PUT_LINE(
            '   ' || RPAD(v_nm_vet, 32)
            || RPAD(NVL(v_nr_crmv, 'N/I'), 15)
            || CASE v_st_ativo WHEN 'S' THEN 'Ativo' ELSE '(Inativo)' END
        );

        -- Acumula contadores por status
        IF v_st_ativo = 'S' THEN
            v_subtotal_ativos   := v_subtotal_ativos   + 1;
        ELSE
            v_subtotal_inativos := v_subtotal_inativos + 1;
        END IF;
        v_subtotal_total := v_subtotal_total + 1;

    END LOOP;
    CLOSE c_vet_clinica;

    -- Sub-Total da última clínica
    IF v_clinica_anterior != -1 THEN
        IF    v_subtotal_total >= 5 THEN v_classificacao := 'Grande Porte';
        ELSIF v_subtotal_total >= 3 THEN v_classificacao := 'Médio Porte';
        ELSE                             v_classificacao := 'Pequeno Porte';
        END IF;

        DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '┌───────────────────────────────────┐');
        DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│ Sub-Total [' || v_nm_clinica_ant || ']');
        DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│   Ativos   : ' || v_subtotal_ativos);
        DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│   Inativos : ' || v_subtotal_inativos);
        DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│   Total    : ' || v_subtotal_total);
        DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '│   Porte    : ' || v_classificacao);
        DBMS_OUTPUT.PUT_LINE(RPAD(' ', 40) || '└───────────────────────────────────┘');
        v_total_geral := v_total_geral + v_subtotal_total;
    END IF;

    -- TOTAL GERAL — exigência explícita da rubrica FIAP
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('╔══════════════════════════════════════════════════╗');
    DBMS_OUTPUT.PUT_LINE('║        TOTAL GERAL DE VETERINÁRIOS: '
        || RPAD(v_total_geral, 13) || '║');
    DBMS_OUTPUT.PUT_LINE('╚══════════════════════════════════════════════════╝');
    DBMS_OUTPUT.PUT_LINE('');
END;
/

-- ============================================================================
-- BLOCO II — Pets: Classificação por Porte + Cálculo de Idade
-- Tomada de decisão: IF sobre porte → prioridade vacinal preventiva
-- ============================================================================
DECLARE
    CURSOR c_pets IS
        SELECT
            p.ID_PET,
            p.NM_PET,
            p.SG_SEXO,
            p.SG_PORTE,
            p.DT_NASCIMENTO,
            e.NM_ESPECIE,
            c.NM_CLINICA,
            MONTHS_BETWEEN(SYSDATE, p.DT_NASCIMENTO) AS MESES_VIDA
        FROM   PET     p
        JOIN   ESPECIE e ON e.ID_ESPECIE = p.ID_ESPECIE
        JOIN   CLINICA c ON c.ID_CLINICA = p.ID_CLINICA
        WHERE  p.ST_ATIVO = 'S'
        ORDER BY c.NM_CLINICA, p.SG_PORTE, p.NM_PET;

    v_id_pet        PET.ID_PET%TYPE;
    v_nm_pet        PET.NM_PET%TYPE;
    v_sg_sexo       PET.SG_SEXO%TYPE;
    v_sg_porte      PET.SG_PORTE%TYPE;
    v_dt_nascim     PET.DT_NASCIMENTO%TYPE;
    v_nm_especie    ESPECIE.NM_ESPECIE%TYPE;
    v_nm_clinica    CLINICA.NM_CLINICA%TYPE;
    v_meses_vida    NUMBER;

    v_ds_porte      VARCHAR2(15);
    v_ds_fase_vida  VARCHAR2(20);
    v_ds_prioridade VARCHAR2(30);
    v_anos          NUMBER;
    v_total_pets    NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('████████████████████████████████████████████████████████████████████████');
    DBMS_OUTPUT.PUT_LINE(' RELATÓRIO II — CLASSIFICAÇÃO DE PETS (PORTE / IDADE / PRIORIDADE)');
    DBMS_OUTPUT.PUT_LINE('████████████████████████████████████████████████████████████████████████');
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 6)      || RPAD('NOME', 12)  || RPAD('ESPÉCIE', 8)
        || RPAD('PORTE', 10) || RPAD('SEXO', 6)  || RPAD('ANOS', 6)
        || RPAD('FASE', 12) || 'PRIORIDADE PREVENTIVO'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 85, '-'));

    OPEN c_pets;
    LOOP
        FETCH c_pets INTO
            v_id_pet, v_nm_pet, v_sg_sexo, v_sg_porte,
            v_dt_nascim, v_nm_especie, v_nm_clinica, v_meses_vida;
        EXIT WHEN c_pets%NOTFOUND;

        v_anos := TRUNC(v_meses_vida / 12);

        -- TOMADA DE DECISÃO 1: rótulo de porte
        v_ds_porte := CASE v_sg_porte
            WHEN 'P' THEN 'Pequeno'
            WHEN 'M' THEN 'Médio'
            WHEN 'G' THEN 'Grande'
            ELSE          'N/I'
        END;

        -- TOMADA DE DECISÃO 2: fase de vida pelo número de meses
        IF    v_meses_vida IS NULL THEN
            v_ds_fase_vida := 'Sem Informação';
        ELSIF v_meses_vida < 6 THEN
            v_ds_fase_vida := 'Filhote';
        ELSIF v_meses_vida < 18 THEN
            v_ds_fase_vida := 'Jovem';
        ELSIF v_meses_vida < 84 THEN
            v_ds_fase_vida := 'Adulto';
        ELSE
            v_ds_fase_vida := 'Sênior';
        END IF;

        -- TOMADA DE DECISÃO 3: prioridade de check-up preventivo
        v_ds_prioridade := CASE
            WHEN v_ds_fase_vida IN ('Filhote', 'Sênior') THEN '*** ALTA PRIORIDADE ***'
            WHEN v_ds_fase_vida = 'Jovem'                THEN '! Média Prioridade'
            ELSE                                              'Rotina Anual'
        END;

        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_id_pet,    6)  || RPAD(v_nm_pet,      12) || RPAD(v_nm_especie, 8)
            || RPAD(v_ds_porte, 10) || RPAD(v_sg_sexo,   6)  || RPAD(NVL(v_anos,0), 6)
            || RPAD(v_ds_fase_vida, 12) || v_ds_prioridade
        );

        v_total_pets := v_total_pets + 1;
    END LOOP;
    CLOSE c_pets;

    DBMS_OUTPUT.PUT_LINE(RPAD('═', 85, '═'));
    DBMS_OUTPUT.PUT_LINE('Total de pets ativos listados: ' || v_total_pets);
    DBMS_OUTPUT.PUT_LINE('');
END;
/

-- ============================================================================
-- BLOCO III — Agendamentos: Criticidade e SLA por Status
-- Tomada de decisão: CASE sobre ST_STATUS → ação recomendada
-- ============================================================================
DECLARE
    CURSOR c_agend IS
        SELECT
            a.ID_AGENDAMENTO,
            a.ST_STATUS,
            a.DS_TIPO,
            a.DT_AGENDAMENTO,
            a.NM_PACIENTE,
            v.NM_VETERINARIO,
            c.NM_CLINICA,
            -- Atraso em horas: positivo = agendamento no passado (pode ter atrasado)
            ROUND((SYSTIMESTAMP - a.DT_AGENDAMENTO) * 24, 1) AS HORAS_DIFF
        FROM   AGENDAMENTO  a
        JOIN   CLINICA      c ON c.ID_CLINICA     = a.ID_CLINICA
        LEFT JOIN VETERINARIO v ON v.ID_VETERINARIO = a.ID_VETERINARIO
        WHERE  a.ST_STATUS NOT IN ('REALIZADO', 'CANCELADO')
        ORDER BY a.DT_AGENDAMENTO;

    v_id_ag       AGENDAMENTO.ID_AGENDAMENTO%TYPE;
    v_st_status   AGENDAMENTO.ST_STATUS%TYPE;
    v_ds_tipo     AGENDAMENTO.DS_TIPO%TYPE;
    v_dt_ag       AGENDAMENTO.DT_AGENDAMENTO%TYPE;
    v_nm_pac      AGENDAMENTO.NM_PACIENTE%TYPE;
    v_nm_vet      VETERINARIO.NM_VETERINARIO%TYPE;
    v_nm_clinica  CLINICA.NM_CLINICA%TYPE;
    v_horas_diff  NUMBER;
    v_acao        VARCHAR2(40);
    v_total       NUMBER := 0;
    v_criticos    NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('████████████████████████████████████████████████████████████████████████');
    DBMS_OUTPUT.PUT_LINE(' RELATÓRIO III — AGENDAMENTOS PENDENTES E AÇÃO RECOMENDADA');
    DBMS_OUTPUT.PUT_LINE('████████████████████████████████████████████████████████████████████████');
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 8) || RPAD('STATUS', 16) || RPAD('TIPO', 14)
        || RPAD('PACIENTE', 14) || RPAD('VET', 22) || 'AÇÃO'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 100, '-'));

    OPEN c_agend;
    LOOP
        FETCH c_agend INTO
            v_id_ag, v_st_status, v_ds_tipo, v_dt_ag,
            v_nm_pac, v_nm_vet, v_nm_clinica, v_horas_diff;
        EXIT WHEN c_agend%NOTFOUND;

        -- TOMADA DE DECISÃO: ação recomendada baseada em status + atraso
        CASE
            WHEN v_st_status = 'INTENCAO' THEN
                v_acao := 'Converter em Agendamento';

            WHEN v_st_status = 'AGENDADO' AND v_horas_diff > 2 THEN
                v_acao := '*** CONFIRMAR URGENTE ***';
                v_criticos := v_criticos + 1;

            WHEN v_st_status = 'AGENDADO' THEN
                v_acao := 'Aguardar Confirmação';

            WHEN v_st_status = 'CONFIRMADO' AND v_horas_diff > 0 THEN
                v_acao := '! Iniciar Atendimento';

            WHEN v_st_status = 'CONFIRMADO' THEN
                v_acao := 'Confirmado — OK';

            WHEN v_st_status = 'NAO_COMPARECEU' THEN
                v_acao := 'Reagendar / Notificar';
                v_criticos := v_criticos + 1;

            ELSE
                v_acao := 'Verificar Manualmente';
        END CASE;

        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_id_ag,    8) || RPAD(v_st_status,  16) || RPAD(NVL(v_ds_tipo, 'N/I'), 14)
            || RPAD(NVL(v_nm_pac, 'N/I'), 14)
            || RPAD(NVL(v_nm_vet, 'Sem vet'), 22)
            || v_acao
        );

        v_total := v_total + 1;
    END LOOP;
    CLOSE c_agend;

    DBMS_OUTPUT.PUT_LINE(RPAD('═', 100, '═'));
    DBMS_OUTPUT.PUT_LINE('Agendamentos pendentes : ' || v_total);
    DBMS_OUTPUT.PUT_LINE('Casos críticos         : ' || v_criticos);
    DBMS_OUTPUT.PUT_LINE('');
END;
/

-- ============================================================================
-- BLOCO IV — Temperatura IoT: Faixa de Operação + Contagem de Alertas
-- Tomada de decisão: IF em cascata sobre VL_TEMPERATURA
-- ============================================================================
DECLARE
    CURSOR c_temp IS
        SELECT
            lt.ID_LEITURA,
            d.CD_DISPOSITIVO,
            d.DS_LOCALIZACAO,
            lt.VL_TEMPERATURA,
            lt.VL_UMIDADE,
            TO_CHAR(lt.DT_LEITURA, 'DD/MM/YYYY HH24:MI') AS DT_FMT
        FROM   LEITURA_TEMPERATURA lt
        JOIN   DISPOSITIVO_IOT     d ON d.ID_DISPOSITIVO = lt.ID_DISPOSITIVO_IOT
        ORDER BY lt.ID_DISPOSITIVO_IOT, lt.DT_LEITURA;

    v_id_leit       LEITURA_TEMPERATURA.ID_LEITURA%TYPE;
    v_cd_disp       DISPOSITIVO_IOT.CD_DISPOSITIVO%TYPE;
    v_ds_local      DISPOSITIVO_IOT.DS_LOCALIZACAO%TYPE;
    v_vl_temp       LEITURA_TEMPERATURA.VL_TEMPERATURA%TYPE;
    v_vl_umid       LEITURA_TEMPERATURA.VL_UMIDADE%TYPE;
    v_dt_fmt        VARCHAR2(20);
    v_faixa         VARCHAR2(25);
    v_ct_critica    NUMBER := 0;
    v_ct_alta       NUMBER := 0;
    v_ct_normal     NUMBER := 0;
    v_ct_baixa      NUMBER := 0;
    v_total         NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('████████████████████████████████████████████████████████████████████████');
    DBMS_OUTPUT.PUT_LINE(' RELATÓRIO IV — CLASSIFICAÇÃO DAS LEITURAS DE TEMPERATURA IoT');
    DBMS_OUTPUT.PUT_LINE(' Faixas: < 15°C = Baixa | 15-24°C = Normal | 24-27°C = Alta | ≥27°C = Crítica');
    DBMS_OUTPUT.PUT_LINE('████████████████████████████████████████████████████████████████████████');
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 8) || RPAD('DATA/HORA', 18) || RPAD('DISPOSITIVO', 18)
        || RPAD('TEMP(°C)', 10) || RPAD('UMID(%)', 9) || 'FAIXA'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));

    OPEN c_temp;
    LOOP
        FETCH c_temp INTO
            v_id_leit, v_cd_disp, v_ds_local,
            v_vl_temp, v_vl_umid, v_dt_fmt;
        EXIT WHEN c_temp%NOTFOUND;

        -- TOMADA DE DECISÃO: IF em cascata — classificação por faixa de temperatura
        IF    v_vl_temp >= 27 THEN
            v_faixa      := '*** CRÍTICA ***';
            v_ct_critica := v_ct_critica + 1;
        ELSIF v_vl_temp >= 24 THEN
            v_faixa   := '! Alta';
            v_ct_alta := v_ct_alta + 1;
        ELSIF v_vl_temp >= 15 THEN
            v_faixa     := 'Normal';
            v_ct_normal := v_ct_normal + 1;
        ELSE
            v_faixa    := '* Baixa';
            v_ct_baixa := v_ct_baixa + 1;
        END IF;

        DBMS_OUTPUT.PUT_LINE(
            RPAD(v_id_leit, 8) || RPAD(v_dt_fmt, 18) || RPAD(v_cd_disp, 18)
            || RPAD(v_vl_temp, 10)
            || RPAD(NVL(TO_CHAR(v_vl_umid), 'N/D'), 9)
            || v_faixa
        );

        v_total := v_total + 1;
    END LOOP;
    CLOSE c_temp;

    DBMS_OUTPUT.PUT_LINE(RPAD('═', 80, '═'));
    DBMS_OUTPUT.PUT_LINE('RESUMO POR FAIXA:');
    DBMS_OUTPUT.PUT_LINE('   Normal       : ' || v_ct_normal);
    DBMS_OUTPUT.PUT_LINE('   Alta (risco) : ' || v_ct_alta);
    DBMS_OUTPUT.PUT_LINE('   Crítica      : ' || v_ct_critica);
    DBMS_OUTPUT.PUT_LINE('   Baixa        : ' || v_ct_baixa);
    DBMS_OUTPUT.PUT_LINE('   TOTAL        : ' || v_total);
    DBMS_OUTPUT.PUT_LINE('');
END;
/
