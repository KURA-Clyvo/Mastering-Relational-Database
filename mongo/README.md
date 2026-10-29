# KURA · Estrutura MongoDB (Sprint 4 · Entregável 4)

Recebe o JSON exportado do Oracle (`data/2TDSPF_2026_Dataset_Cobrancas.json`, 18 cobranças ativas), valida com `$jsonSchema`, cria índices justificados e reproduz o relatório `PRC_RELATORIO_COBRANCAS` da Sprint 3 como agregação.

## Pré-requisitos

- Docker (ou um MongoDB 7 qualquer) com `mongosh` e `mongoimport` (ambos já vêm dentro da imagem `mongo:7`).
- Nenhuma credencial: o MongoDB local roda sem autenticação, só para a disciplina.

## Passo a passo

```bash
# 1. subir o MongoDB 7 local
docker run -d --name kura-mongo --memory 600m mongo:7 --wiredTigerCacheSizeGB 0.25

# 2. copiar o JSON e o script para dentro do container
MSYS_NO_PATHCONV=1 docker exec kura-mongo mkdir -p /work
docker cp data/2TDSPF_2026_Dataset_Cobrancas.json kura-mongo:/work/
docker cp mongo/2TDSPF_2026_MongoDB_Integrantes.js kura-mongo:/work/

# 3. staging: importar o JSON cru. O --drop é obrigatório (sem ele cada importação duplica o staging)
MSYS_NO_PATHCONV=1 docker exec kura-mongo mongoimport --db kura_disciplina --collection cobrancas_raw \
    --jsonArray --drop --file /work/2TDSPF_2026_Dataset_Cobrancas.json

# 4. estrutura + conversão + consultas (pode rodar quantas vezes quiser)
MSYS_NO_PATHCONV=1 docker exec -w /work kura-mongo mongosh --quiet --file /work/2TDSPF_2026_MongoDB_Integrantes.js
```

O prefixo `MSYS_NO_PATHCONV=1` está em **todos** os `docker exec` com caminho `/…`. No Git Bash do Windows ele é necessário: sem ele o shell converte `/work` em caminho do Windows, o `mkdir` sai com `EXIT=0` criando o diretório errado e só o `docker cp` seguinte falha. No Linux/macOS o prefixo é inofensivo. A demo termina com `RESUMO: n CONFERE, 0 DIVERGE` e `EXIT=0`; qualquer divergência faz o `mongosh` sair com `EXIT` diferente de 0.

## O que o script faz

| Seção | O que faz |
|---|---|
| `cobrancas_raw` | Staging sem validação. O `mongoimport` deixa a data como string e o valor como `double`. |
| `cobrancas_export` | Coleção final com `$jsonSchema` estrito (`strict` + `error`, `additionalProperties: false`). Reaplicada por `collMod` se já existir. |
| Índices | `ux_cobranca_id` (único; exigido pelo `$merge`) e `ix_clinica_data` (`idClinica`, `dtCobranca` desc; atende "cobranças de uma clínica num período"). |
| Pipeline | `$dateFromString` em UTC, `$toDecimal` sobre `$toString` (sem cauda binária), monta `clinica` e `servico` (`null`, nunca `{}`, sem serviço), `$merge` por `idCobranca`. Depois do `$merge`, apaga do export o que não está mais no staging: o staging é a fotografia atual do Oracle e o export a espelha. |
| (a) | Cobranças da clínica 1 nos 4 dias que terminam na cobrança mais recente (período derivado dos dados), com `servico.nome` e `explain`: `IXSCAN` em `ix_clinica_data`. |
| (b) | O relatório da S3: total por (clínica, forma), subtotal por clínica (com o nome da clínica lido do documento embutido) e total geral (3027.15), em `Decimal128`. |
| (c) | `countDocuments` do staging e da coleção final (18 e 18). |
| (d) | Conferências `CONFERE`/`DIVERGE`: export = staging, validador `strict`/`error` e 0 documentos fora do schema, `valor` sempre `decimal`, datas, `IXSCAN`, somas independentes e o gabarito da S3 (`PRC_RELATORIO_COBRANCAS`, Oracle, 2026-10-29; com outro dataset imprime `PULADO`). Fecha com `RESUMO` e `throw` se houver divergência. |

## Modelagem

- **Referência:** a clínica continua referenciada por `idClinica`; cobrança cresce sem limite e o cadastro da clínica muda sozinho.
- **Snapshot embutido:** `clinica.nome` e `servico {id, nome}` são copiados para o relatório ler tudo num documento só. `servico.nome` é o nome **no momento da exportação** (o `PKG_COBRANCA` junta com o `NM_SERVICO` atual; o Oracle não guarda histórico), não o da data da cobrança.
- **Datas em UTC:** a carga da S3 grava `SYSTIMESTAMP` em coluna `TIMESTAMP` (hora do servidor Oracle, `+00:00` no container) e a .NET grava `DateTime.UtcNow`. Um Oracle com hora de São Paulo deslocaria as datas em 3 h.
