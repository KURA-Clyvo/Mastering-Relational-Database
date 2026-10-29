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
// indices createIndex sao no-op se iguais, $merge faz replace por idCobranca) e
// o export ESPELHA o staging: o que sumiu do staging e apagado do export (secao 5).
//
// A DEMO CONFERE (secao 7): cada conferencia imprime "CONFERE: caso" ou
// "DIVERGE: caso (esperado X, obtido Y)"; no fim, "RESUMO: n CONFERE, m DIVERGE"
// e, se m > 0, o script lanca erro e o mongosh sai com EXIT diferente de 0.
// =============================================================================

// 1. Database -----------------------------------------------------------------
db = db.getSiblingDB("kura_disciplina");

// 2. Staging ------------------------------------------------------------------
// cobrancas_raw recebe o mongoimport CRU, sem validacao: o mongoimport nao
// converte data (fica string) nem decimal (numero vira double). A conversao de
// tipos acontece no pipeline da secao 5.

// 3. Colecao final com $jsonSchema estrito --------------------------------------
// Modelagem (embedding x referencia):
//  - clinica {nome}: SNAPSHOT embutido, obrigatorio. A consulta (b) LE o nome
//    junto da cobranca ($first: "$clinica.nome"), sem segundo acesso. A clinica
//    continua REFERENCIADA por idClinica e nao embutida inteira: cobranca cresce
//    sem limite (N por clinica), e o cadastro da clinica muda por conta propria;
//    duplica-lo inteiro em cada cobranca geraria anomalia de atualizacao.
//  - servico {id, nome}: snapshot embutido, lido pela consulta (a). ATENCAO: e o
//    nome do servico NO MOMENTO DA EXPORTACAO, nao o da data da cobranca: o
//    PKG_COBRANCA faz JOIN com o NM_SERVICO ATUAL e o Oracle nao guarda historico.
//    E null (nunca {}) quando a cobranca nao tem servico; com objeto, id e nome
//    sao obrigatorios.
//  - idEvento e obrigatorio e nao nulo: ID_EVENTO_CLINICO e NOT NULL no Oracle.
//  - additionalProperties: false no documento e nos subdocumentos. Schema
//    fechado = campo com nome errado (ex.: "valro") e recusado em vez de gravado
//    em silencio. O _id e liberado explicitamente (o MongoDB o cria).
const validador = {
  $jsonSchema: {
    bsonType: "object",
    additionalProperties: false,
    required: ["idCobranca", "idEvento", "idClinica", "clinica", "valor", "dtCobranca", "ativa"],
    properties: {
      _id:        {},
      idCobranca: { bsonType: ["int", "long"], description: "PK vinda do Oracle" },
      idEvento:   { bsonType: ["int", "long"], description: "NOT NULL no Oracle" },
      idClinica:  { bsonType: ["int", "long"], description: "referencia a clinica" },
      clinica: {
        bsonType: "object", additionalProperties: false, required: ["nome"],
        properties: { nome: { bsonType: "string" } }
      },
      servico: {
        bsonType: ["object", "null"], additionalProperties: false, required: ["id", "nome"],
        properties: { id: { bsonType: ["int", "long"] }, nome: { bsonType: "string" } }
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
//   primeiro": find({idClinica: X, dtCobranca: {$gte: A, $lte: B}}).sort({dtCobranca: -1}).
//   Igualdade em idClinica + faixa/ordenacao em dtCobranca (regra ESR); a direcao
//   -1 entrega a ordenacao sem etapa de SORT em memoria.
db.cobrancas_export.createIndex({ idClinica: 1, dtCobranca: -1 }, { name: "ix_clinica_data" });

// 5. Pipeline raw -> export ----------------------------------------------------
// servico: $ifNull cobre idServico null E ausente (com $eq: [campo, null] o campo
// ausente nao igualaria null e sairia servico: {}).
const servicoExpr = { $cond: [{ $eq: [{ $ifNull: ["$idServico", null] }, null] }, null, { id: "$idServico", nome: "$servico" }] };
db.cobrancas_raw.aggregate([
  { $project: {
      _id: 0,
      idCobranca: 1, idEvento: 1, idClinica: 1, formaPagamento: 1, ativa: 1,
      clinica: { nome: "$nmClinica" },
      servico: servicoExpr,
      // $toString antes: o double 235.9 vira Decimal128 235.9, nao 235.900000000000
      valor: { $toDecimal: { $toString: "$valor" } },
      // A string vem sem "Z" e e lida como UTC. Por que UTC: a carga da S3 grava
      // SYSTIMESTAMP numa coluna TIMESTAMP (sem fuso), isto e, a hora do relogio do
      // servidor Oracle, que no container esta em +00:00 (medido). Em producao a
      // .NET grava DateTime.UtcNow. RISCO: um Oracle com hora de Sao Paulo
      // deslocaria todas as datas em 3 h.
      dtCobranca: { $dateFromString: { dateString: "$dataCobranca", format: "%Y-%m-%dT%H:%M:%S", timezone: "UTC" } }
  } },
  { $merge: { into: "cobrancas_export", on: "idCobranca", whenMatched: "replace", whenNotMatched: "insert" } }
]);
print("[pipeline] cobrancas_raw -> cobrancas_export concluido");
// O $merge so insere/atualiza. O staging e a FOTOGRAFIA ATUAL do Oracle e o export
// espelha essa fotografia: cobranca que saiu do staging (desativada/apagada no
// Oracle) e apagada do export, senao o relatorio somaria cobranca que nao existe.
const idsRaw = db.cobrancas_raw.distinct("idCobranca");
const orfaos = db.cobrancas_export.deleteMany({ idCobranca: { $nin: idsRaw } });
print("[espelho] orfaos removidos do export: " + orfaos.deletedCount);

// 6. Consultas de demonstracao ---------------------------------------------------
// Periodo derivado dos DADOS (a carga da S3 gera datas relativas a SYSTIMESTAMP):
// os 4 dias terminando na cobranca mais recente da clinica escolhida abaixo.
// A clinica e derivada dos dados: a que tem mais cobrancas no export (empate: menor idClinica).
const topClinica = db.cobrancas_export.aggregate([{ $group: { _id: "$idClinica", n: { $sum: 1 } } }, { $sort: { n: -1, _id: 1 } }, { $limit: 1 }]).toArray()[0];
const clinicaA = topClinica ? topClinica._id : 1;
const maisRecente = db.cobrancas_export.find({ idClinica: clinicaA }).sort({ dtCobranca: -1 }).limit(1).toArray()[0];
const fimA = maisRecente ? maisRecente.dtCobranca : new Date(0);
const iniA = new Date(fimA.getTime() - 4 * 24 * 3600 * 1000);
print("\n=== (a) cobrancas da clinica " + clinicaA + " entre " + iniA.toISOString() + " e " + fimA.toISOString() + " (inclusive) ===");
const filtroA = { idClinica: clinicaA, dtCobranca: { $gte: iniA, $lte: fimA } };
const docsA = db.cobrancas_export.find(filtroA, { _id: 0, idCobranca: 1, valor: 1, formaPagamento: 1, dtCobranca: 1, "servico.nome": 1 }).sort({ dtCobranca: -1 }).toArray();
docsA.forEach(d => printjson(d));
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
// o nome da clinica e LIDO do documento embutido ($first: "$clinica.nome")
const subs = db.cobrancas_export.aggregate([
  { $match: { ativa: true } },
  { $group: { _id: "$idClinica", nome: { $first: "$clinica.nome" }, sub: { $sum: "$valor" } } },
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
  print("Clinica " + s._id + " - " + s.nome);
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

// 7. Conferencias --------------------------------------------------------------
print("\n=== (d) conferencias ===");
let nOk = 0, nBad = 0;
function confere(caso, esperado, obtido) {
  if (String(esperado) === String(obtido)) { nOk++; print("CONFERE: " + caso); }
  else { nBad++; print("DIVERGE: " + caso + " (esperado " + esperado + ", obtido " + obtido + ")"); }
}
const centavos = x => Math.round(parseFloat(x.toString()) * 100);
const rawDocs = db.cobrancas_raw.find().toArray();
const expDocs = db.cobrancas_export.find().toArray();

// export == raw: contagem e conjunto de idCobranca
confere("export == raw (contagem)", rawDocs.length, expDocs.length);
const ids = a => a.map(d => d.idCobranca).sort((x, y) => x - y).join(",");
confere("export == raw (conjunto de idCobranca)", ids(rawDocs), ids(expDocs));

// validador da colecao: strict/error, lidos de listCollections
const optsCol = db.getCollectionInfos({ name: "cobrancas_export" })[0].options;
confere("validationLevel da colecao", "strict", optsCol.validationLevel);
confere("validationAction da colecao", "error", optsCol.validationAction);
// todo documento satisfaz o validador VIVO da colecao (nao o da constante acima)
confere("documentos que NAO casam com o $jsonSchema", 0, db.cobrancas_export.countDocuments({ $nor: [optsCol.validator] }));
confere("documentos com valor que nao e decimal", 0, db.cobrancas_export.countDocuments({ valor: { $not: { $type: "decimal" } } }));

// datas: dtCobranca == string original do raw + ".000Z"
const rawPorId = {}; rawDocs.forEach(d => { rawPorId[d.idCobranca] = d; });
const datasRuins = expDocs.filter(d => !rawPorId[d.idCobranca] || d.dtCobranca.toISOString() !== rawPorId[d.idCobranca].dataCobranca + ".000Z");
confere("datas == string do raw + .000Z (documentos diferentes)", 0, datasRuins.length);

// controles do schema, numa colecao descartavel com o MESMO validador vivo
db.ctl_validacao.drop();
db.createCollection("ctl_validacao", { validator: optsCol.validator, validationLevel: "strict", validationAction: "error" });
const docOk = () => ({ idCobranca: NumberInt(9001), idEvento: NumberInt(1), idClinica: NumberInt(1), clinica: { nome: "X" },
  servico: { id: NumberInt(1), nome: "S" }, valor: NumberDecimal("10.10"), formaPagamento: "PIX", dtCobranca: ISODate("2026-10-20T10:00:00Z"), ativa: true });
function aceita(mut) { const d = docOk(); mut(d); try { db.ctl_validacao.insertOne(d); db.ctl_validacao.deleteMany({}); return "aceito"; } catch (e) { return "recusado"; } }
confere("controle: documento valido e aceito", "aceito", aceita(() => {}));
confere("controle: sem idEvento e recusado", "recusado", aceita(d => { delete d.idEvento; }));
confere("controle: sem clinica e recusado", "recusado", aceita(d => { delete d.clinica; }));
confere("controle: servico {} e recusado", "recusado", aceita(d => { d.servico = {}; }));
confere("controle: servico null e aceito", "aceito", aceita(d => { d.servico = null; }));
db.ctl_validacao.drop();
// idServico AUSENTE no pipeline => servico null (nao {})
const semServ = db.aggregate([{ $documents: [{ x: 1 }] }, { $project: { _id: 0, servico: servicoExpr } }]).toArray()[0];
confere("controle: idServico ausente => servico null", "null", semServ.servico === null ? "null" : JSON.stringify(semServ.servico));

// independente do relatorio (b): soma por clinica via $group direto no export, e soma dos doubles do raw
const direto = {}; db.cobrancas_export.aggregate([{ $group: { _id: "$idClinica", s: { $sum: "$valor" } } }]).forEach(g => { direto[g._id] = centavos(g.s); });
const doRaw = {}; rawDocs.forEach(d => { doRaw[d.idClinica] = (doRaw[d.idClinica] || 0) + Math.round(d.valor * 100); });
subs.forEach(s => {
  confere("soma da clinica " + s._id + ": (b) == $group direto no export", direto[s._id], centavos(s.sub));
  confere("soma da clinica " + s._id + ": (b) == soma dos doubles do raw", doRaw[s._id], centavos(s.sub));
});
confere("Total Geral == soma de todo o raw (centavos)", Object.values(doRaw).reduce((a, b) => a + b, 0), centavos(tot.total));

// (a) usa o indice e devolve algo
confere("(a) usa IXSCAN em ix_clinica_data", true, estagios.indexOf("IXSCAN(ix_clinica_data)") >= 0);
confere("(a) devolveu mais de 0 documentos", true, docsA.length > 0);

// Gabarito da S3. Origem: Oracle, procedure PRC_RELATORIO_COBRANCAS, medido em
// 2026-10-29 (implementacao e G2 da S4-DB-05). So vale para o dataset da S3:
// idCobranca 1..18. Com outro dataset imprime PULADO em vez de DIVERGE.
const GABARITO = { "1|BOLETO": "386.75", "1|CARTAO_CREDITO": "404.30", "1|CARTAO_DEBITO": "324.35", "1|DINHEIRO": "240.15", "1|PIX": "209.55",
  "2|CARTAO_CREDITO": "438.15", "2|DINHEIRO": "280.20", "2|PIX": "420.80", "2|TRANSFERENCIA": "322.90" };
const GAB_SUB = { 1: "1565.10", 2: "1462.05" };
const GAB_TOTAL = "3027.15";
// O gabarito e das clinicas 1 e 2 da S3: o mesmo idCobranca 1..18 com outras clinicas tambem e "dataset diferente".
const clinicasRaw = [...new Set(rawDocs.map(d => d.idClinica))].sort((x, y) => x - y).join(",");
if (ids(rawDocs) !== "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18" || clinicasRaw !== "1,2") {
  print("PULADO: gabarito (dataset diferente)");
} else {
  const txt = d => { let t = d.toString(); if (t.indexOf(".") < 0) t += ".00"; else t = t.padEnd(t.indexOf(".") + 3, "0"); return t; };
  Object.keys(GABARITO).forEach(k => {
    const l = linhas.find(x => x._id.c + "|" + x._id.f === k);
    confere("gabarito S3 linha " + k, GABARITO[k], l ? txt(l.total) : "(ausente)");
  });
  confere("gabarito S3 numero de linhas clinica x forma", Object.keys(GABARITO).length, linhas.length);
  Object.keys(GAB_SUB).forEach(c => {
    const s = subs.find(x => String(x._id) === c);
    confere("gabarito S3 Sub Total clinica " + c, GAB_SUB[c], s ? txt(s.sub) : "(ausente)");
  });
  confere("gabarito S3 Total Geral", GAB_TOTAL, txt(tot.total));
  confere("gabarito S3 lancamentos", 18, tot.n);
}

print("\nRESUMO: " + nOk + " CONFERE, " + nBad + " DIVERGE");
if (nBad > 0) { throw new Error("RESUMO: " + nOk + " CONFERE, " + nBad + " DIVERGE"); }
