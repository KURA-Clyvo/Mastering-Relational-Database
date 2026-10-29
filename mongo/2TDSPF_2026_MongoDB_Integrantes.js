// =============================================================================
// KURA - Sprint 4 - Entregavel 4 - Estrutura MongoDB (mongo:7 / mongosh)
// Arquivo : mongo/2TDSPF_2026_MongoDB_Integrantes.js
// Entrada : data/2TDSPF_2026_Dataset_Cobrancas.json (exportado do Oracle pelo
//           PKG_COBRANCA.exportar_todas; 18 elementos, so cobrancas ST_ATIVA='S')
//
// COMO RODAR (nenhuma credencial neste arquivo; o script NAO importa o JSON):
//   1) staging - o --drop e obrigatorio: sem ele cada importacao DUPLICA o staging
//      mongoimport --db kura_disciplina --collection cobrancas_raw \
//                  --jsonArray --drop --file 2TDSPF_2026_Dataset_Cobrancas.json
//   2) mongosh --quiet --file 2TDSPF_2026_MongoDB_Integrantes.js
//
// IDEMPOTENTE: rodar N vezes nao duplica nada (colecao e validador reaplicados,
// indices createIndex sao no-op se iguais, $merge faz replace por idCobranca).
// =============================================================================

// 1. Database -----------------------------------------------------------------
db = db.getSiblingDB("kura_disciplina");

// 2. Staging ------------------------------------------------------------------
// cobrancas_raw recebe o mongoimport CRU, sem validacao: o mongoimport nao
// converte data (fica string) nem decimal (numero vira double). A conversao de
// tipos acontece no pipeline da secao 5.

// 3. Colecao final com $jsonSchema estrito --------------------------------------
// Modelagem (embedding x referencia):
//  - clinica {nome}: SNAPSHOT embutido. O relatorio le o nome junto da cobranca,
//    sem segundo acesso. A clinica continua REFERENCIADA por idClinica e nao
//    embutida inteira: cobranca cresce sem limite (N por clinica), e o cadastro
//    da clinica muda por conta propria; duplica-lo inteiro em cada cobranca
//    geraria anomalia de atualizacao.
//  - servico {id, nome}: snapshot embutido (nome do servico NA data da cobranca,
//    que e o que o recibo mostra); null quando a cobranca nao tem servico.
//  - additionalProperties: false no documento e nos subdocumentos. Schema
//    fechado = campo com nome errado (ex.: "valro") e recusado em vez de gravado
//    em silencio. O _id e liberado explicitamente (o MongoDB o cria).
const validador = {
  $jsonSchema: {
    bsonType: "object",
    additionalProperties: false,
    required: ["idCobranca", "idClinica", "valor", "dtCobranca", "ativa"],
    properties: {
      _id:        {},
      idCobranca: { bsonType: ["int", "long"], description: "PK vinda do Oracle" },
      idEvento:   { bsonType: ["int", "long", "null"] },
      idClinica:  { bsonType: ["int", "long"], description: "referencia a clinica" },
      clinica: {
        bsonType: ["object", "null"], additionalProperties: false,
        properties: { nome: { bsonType: ["string", "null"] } }
      },
      servico: {
        bsonType: ["object", "null"], additionalProperties: false,
        properties: { id: { bsonType: ["int", "long", "null"] }, nome: { bsonType: ["string", "null"] } }
      },
      valor:          { bsonType: "decimal", description: "Decimal128: dinheiro nao usa double" },
      formaPagamento: { bsonType: ["string", "null"] },
      dtCobranca:     { bsonType: "date", description: "UTC" },
      ativa:          { bsonType: "bool" }
    }
  }
};
const opcoes = { validator: validador, validationLevel: "strict", validationAction: "error" };
if (db.getCollectionInfos({ name: "cobrancas_export" }).length === 0) {
  db.createCollection("cobrancas_export", opcoes);
  print("[colecao] cobrancas_export criada com $jsonSchema strict/error");
} else {
  db.runCommand(Object.assign({ collMod: "cobrancas_export" }, opcoes));
  print("[colecao] cobrancas_export ja existia: validador reaplicado com collMod");
}

// 4. Indices (ANTES do $merge) -------------------------------------------------
// ux_cobranca_id: o $merge "on: idCobranca" EXIGE indice unico nesse campo
//   (sem ele: erro 51183). Tambem serve a busca por PK: find({idCobranca: N}).
db.cobrancas_export.createIndex({ idCobranca: 1 }, { unique: true, name: "ux_cobranca_id" });
// ix_clinica_data: consulta "cobrancas da clinica X num periodo, mais recentes
//   primeiro": find({idClinica: X, dtCobranca: {$gte: A, $lt: B}}).sort({dtCobranca: -1}).
//   Igualdade em idClinica + faixa/ordenacao em dtCobranca (regra ESR); a direcao
//   -1 entrega a ordenacao sem etapa de SORT em memoria.
db.cobrancas_export.createIndex({ idClinica: 1, dtCobranca: -1 }, { name: "ix_clinica_data" });

// 5. Pipeline raw -> export ----------------------------------------------------
db.cobrancas_raw.aggregate([
  { $project: {
      _id: 0,
      idCobranca: 1, idEvento: 1, idClinica: 1, formaPagamento: 1, ativa: 1,
      clinica: { nome: "$nmClinica" },
      servico: { $cond: [{ $eq: ["$idServico", null] }, null, { id: "$idServico", nome: "$servico" }] },
      // $toString antes: o double 235.9 vira Decimal128 235.9, nao 235.900000000000
      valor: { $toDecimal: { $toString: "$valor" } },
      // a string vem sem "Z" mas representa UTC (a .NET grava DT_COBRANCA em UTC)
      dtCobranca: { $dateFromString: { dateString: "$dataCobranca", format: "%Y-%m-%dT%H:%M:%S", timezone: "UTC" } }
  } },
  { $merge: { into: "cobrancas_export", on: "idCobranca", whenMatched: "replace", whenNotMatched: "insert" } }
]);
print("[pipeline] cobrancas_raw -> cobrancas_export concluido");

// 6. Consultas de demonstracao ---------------------------------------------------
print("\n=== (a) cobrancas da clinica 1 entre 2026-10-12 e 2026-10-16 (exclusive) ===");
const filtroA = { idClinica: 1, dtCobranca: { $gte: ISODate("2026-10-12T00:00:00Z"), $lt: ISODate("2026-10-16T00:00:00Z") } };
db.cobrancas_export.find(filtroA, { _id: 0, idCobranca: 1, valor: 1, formaPagamento: 1, dtCobranca: 1 }).sort({ dtCobranca: -1 }).forEach(d => printjson(d));
const plano = db.cobrancas_export.find(filtroA).sort({ dtCobranca: -1 }).explain("executionStats");
const estagios = [];
(function percorre(n) { if (!n) return; estagios.push(n.stage + (n.indexName ? "(" + n.indexName + ")" : "")); percorre(n.inputStage); })(plano.queryPlanner.winningPlan);
print("explain: estagios = " + estagios.join(" <- ") +
      " | nReturned=" + plano.executionStats.nReturned +
      " docsExaminados=" + plano.executionStats.totalDocsExamined +
      " chavesExaminadas=" + plano.executionStats.totalKeysExamined);

print("\n=== (b) relatorio da S3 como agregacao: clinica x forma, subtotal, total geral ===");
// forma nula => "(nao informado)", como no Oracle. Sort explicito e estavel.
const linhas = db.cobrancas_export.aggregate([
  { $match: { ativa: true } },
  { $group: { _id: { c: "$idClinica", f: { $ifNull: ["$formaPagamento", "(nao informado)"] } }, total: { $sum: "$valor" }, n: { $sum: 1 } } },
  { $sort: { "_id.c": 1, "_id.f": 1 } }
]).toArray();
const subs = db.cobrancas_export.aggregate([
  { $match: { ativa: true } },
  { $group: { _id: "$idClinica", sub: { $sum: "$valor" } } },
  { $sort: { _id: 1 } }
]).toArray();
const tot = db.cobrancas_export.aggregate([
  { $match: { ativa: true } },
  { $group: { _id: null, total: { $sum: "$valor" }, n: { $sum: 1 } } }
]).toArray()[0];
print("Clinica  Forma               Valor");
print("-------  ------------------  ----------");
// formata a partir do TEXTO do Decimal128 (sem passar por double), sempre com 2 casas
const fmt = d => { let t = d.toString(); if (t.indexOf(".") < 0) t += ".00"; else t = t.padEnd(t.indexOf(".") + 3, "0"); return t.padStart(10); };
subs.forEach(s => {
  linhas.filter(l => l._id.c === s._id).forEach(l =>
    print(String(l._id.c).padEnd(9) + l._id.f.padEnd(20) + fmt(l.total)));
  print("Sub Total".padEnd(29) + fmt(s.sub));
});
print("Total Geral".padEnd(29) + fmt(tot.total));
print("==== " + tot.n + " lancamento(s) totalizado(s) ====");
print("tipo do total geral: " + tot.total.constructor.name);

print("\n=== (c) contagens ===");
print("cobrancas_raw    : " + db.cobrancas_raw.countDocuments());
print("cobrancas_export : " + db.cobrancas_export.countDocuments());
