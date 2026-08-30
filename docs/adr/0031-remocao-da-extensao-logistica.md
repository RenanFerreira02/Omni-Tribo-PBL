# 0031 — Remoção da extensão logística

**Data:** 2026-08-30
**Status:** Aceito

---

## Contexto

O produto respondia a três eixos do Challenge, e `docs/ENTREGA-FASE5.md` os listava lado a lado:
**Sociedade 5.0** (missões de vizinhança, tribo, economia do cuidado), **sistema inteligente de
apoio à decisão** (a regressão logística que previa falha de entrega) e **AI Logistics Extension**
(o webhook de transportadora que convertia entrega falida em missão de retirada).

A decisão de produto passou a ser outra: manter **apenas o eixo social**. Vizinho ajuda vizinho, o
bairro remunera esse cuidado em XP e token, e o token é resgatado em benefício de parceiro local.

Isso não é uma limpeza de código morto. O eixo removido era ~8.100 linhas em `logistica/`, estava
integrado a seis módulos e sustentava três coisas que o resto do sistema usava sem saber:

1. **a única entrada de token no ciclo de missões** — o pote da missão de retirada era financiado
   pelo patrocinador na própria conversão, e o aporte que o abastecia (`APORTE_PATROCINADOR`,
   ADR 0024) é o único ponto de emissão do sistema;
2. **o único produtor do fan-out de notificação** — o alerta "missão nova perto de você" era
   disparado por `EntregaFalidaConvertida`, e por nada mais;
3. **dois insumos da fórmula de recompensa** — o multiplicador de risco (ADR 0022) e
   `tokens-por-real-ofertado` (fórmula versão 2).

Remover a extensão sem decidir sobre os três deixaria, respectivamente: uma economia só com
sumidouro, um módulo de notificações sem gatilho, e uma fórmula com dois parâmetros que nenhum
caminho preenche.

---

## Decisão

**Removemos o eixo logístico inteiro** — webhook de entrada e de confirmação, `EntregaFalida`,
`PontoCustodia`, o modelo de previsão de risco com seu treino e dataset sintético, o endpoint
`POST /logistica/previsao-falha` e o painel `GET /admin/impacto`, que era o funil daquele ciclo.

E resolvemos os três pontos acima assim:

**1. O patrocinador vira APOIADOR DO BAIRRO, e ganha um caminho para o pote.** A tabela
`patrocinador` sobrevive com `transportadora_slug` renomeada para `slug`. O aporte ADMIN continua
intacto: idempotente, auditado, único ponto de emissão. O que é novo — e é o único acréscimo deste
trabalho — é **`POST /api/v1/admin/missoes/{missaoId}/financiamento-apoiador`**, por onde o ADMIN põe
token do apoiador no pote de uma missão comunitária. O débito reusa
`FinanciamentoMissao.debitarPatrocinador`, que já gravava `FINANCIAMENTO_PATROCINADOR` — motivo que
`LancamentoRepository.buscarFinanciamentosDaMissao` já enxerga, então **o estorno de missão
cancelada ou expirada continua correto sem nenhuma alteração**.

**Por que ADMIN, e não um desvio na rota de tribo.** A primeira versão desta decisão pôs o desvio
dentro de `POST /tribos/{triboId}/financiamentos`, que tira a identidade do JWT. Mas a conta do
apoiador nasce com status INATIVO — é o que garante que ela nunca autentica —, então ela não tem JWT
e jamais alcançaria aquela rota: era **código inalcançável**. Quem pegou isso foi a verificação ponta
a ponta contra o servidor de pé, não a suíte de testes, que exercitava o serviço por baixo da borda
HTTP. O caminho ADMIN também é o coerente: cadastro, aporte e encerramento do apoiador já são todos
ADMIN. `FinanciamentoApoiadorAdminTest.apoiadorNaoAutentica` trava a premissa.

**2. O fan-out passa a ouvir `MissaoPublicada`.** O anúncio de bairro deixa de ser privilégio da
missão de retirada e passa a valer para toda missão publicada, que é o comportamento que o produto
social sempre descreveu. Os três filtros — consentimento, nível mínimo e teto por hora — ficam como
estavam. Some o carve-out de prioridade ALTA, porque o produtor da faixa de risco saiu.

**3. A fórmula perde os dois insumos e sobe para a versão 4.** Missão criada por gente sempre passou
nulo nos dois, então **nenhum valor calculado muda** — `CalculadoraDeRecompensaTest.v4ReproduzV1`
prova isso. O que mudou foi a FORMA da fórmula, e é por isso que a versão sobe mesmo assim: sem o
incremento, uma missão antiga passaria a ser explicada por uma calibração que não a produziu.

O schema sai por `V28__remover_extensao_logistica.sql`, **migration nova em vez de reescrita das
V6/V21/V22/V23**: aquelas já foram aplicadas em todo banco existente, e editá-las daria checksum
divergente em máquina antiga enquanto passa em clone novo — a divergência que o CI nunca reproduz.

---

## Consequências

**Positivas:**

- O produto passa a ter **uma tese só**, e o app inteiro a serve. Não há mais um caminho de escrita
  sem JWT, nem um ator externo capaz de criar missão.
- **A Pendência #3 do `CLAUDE.md` desaparece com a causa.** O alerta de ponto lotado — 631 linhas
  idênticas em 3 minutos, medidas no teste de carga — não existe mais para ser deduplicado.
- O anúncio de missão nova, que só rodava para entrega falida, passa a rodar para o bairro inteiro:
  uma máquina bem testada que servia a 1 dos 4 tipos de missão agora serve aos 4.
- Some a superfície mais arriscada do sistema: HMAC sobre corpo bruto, idempotência por rastreio,
  ocupação física sob lock e um provedor de clima no caminho de escrita.

**Negativas / trade-offs:**

- **O eixo "sistema inteligente de apoio à decisão" fica sem implementação.** O modelo previa falha
  de ENTREGA e não tem outro consumidor; mantê-lo vivo sem quem o chame seria pior que removê-lo.
  `docs/qualidade/modelo-previsao.md` sai junto. Quem quiser reabrir o eixo começa de um dataset
  novo, não deste.
- **A economia perde a entrada automática.** Antes, cada entrega falida trazia token de fora do
  bairro sem ninguém decidir nada; agora todo token novo entra por um ato ADMIN explícito. É mais
  auditável e menos automático — e, sem aporte, a circulação só decresce pelo resgate.
- **Duas colunas viram histórico inerte**, e isso está declarado no schema:
  `missao.multiplicador_risco` (explica a recompensa de missões de retirada já creditadas) e o valor
  `PATROCINADOR` de `missao.fonte_pote`. Nenhum código as escreve; apagá-las apagaria a explicação
  de dado que já existe.
- `missao.nivel_minimo` fica sem escritor. A coluna e o gate em
  `MissaoService.validarNivelParaAceitar` permanecem porque exigir reputação é regra de produto, não
  da extensão que a usava — mas hoje **nenhuma missão exige nível**, e o javadoc diz isso.
- As evidências datadas (`docs/evidencias/f21-carga.md`, `f13-*`, `f6-explain-analyze.md`,
  `impacto-conferido-por-sql.md`) e as auditorias F0–F7 descrevem um sistema que tinha o eixo.
  **Não foram reescritas**: são registro do que foi medido naquela data, e falsificá-las
  retroativamente seria pior que a divergência.

---

## Alternativas descartadas

**Manter o modelo de risco sem consumidor, como demonstração.** Ficaria código treinado no `verify`,
com endpoint público, sem ninguém para consumir o score. É exatamente o formato de órfão que a
varredura de 2026-08-20 removeu do projeto: código vivo que faz uma lacuna parecer coberta.

**Remover o patrocinador junto e voltar a cunhar token na conclusão.** Era o estado anterior ao
ADR 0024: emissão implícita, por missão, invisível para a reconciliação. Reintroduzi-la desfaria a
correção mais cara da F8 para economizar um endpoint ADMIN.

**Tornar a conta do apoiador autenticável, para ele mesmo financiar.** Resolveria o problema do JWT
e criaria outro: uma conta de serviço com senha, que ninguém troca e que autentica contra a mesma
superfície do usuário comum. O status INATIVO do titular é o que garante que aquela carteira só é
movida por caminho auditado — e é a mesma disciplina do usuário-sistema.

**Remover o patrocinador sem substituto.** Honesto, e deixa a economia sem entrada: o resgate queima
e nada emite, então `SUM(carteiras) + SUM(potes)` cai monotonicamente até zero. A conservação do
ADR 0027 é um CICLO com duas pontas; remover uma delas não simplifica o ciclo, quebra-o.

**Apagar as migrations da extensão em vez de escrever a V28.** Deixaria o histórico limpo e todo
banco de dev quebrado com "Migration checksum mismatch" ou "detected applied migration not resolved
locally" — sintoma que só aparece em máquina de quem já rodou o projeto, nunca no CI.

---

## Referências

- Revoga: [0021](./0021-verificacao-de-webhook-de-transportadora.md),
  [0022](./0022-previsao-de-risco-de-entrega.md),
  [0026](./0026-confirmacao-de-retirada-por-webhook.md),
  [0029](./0029-painel-de-impacto-e-a-premissa-declarada.md)
- Retifica: [0020](./0020-ponto-de-custodia-comercial-e-proximidade-por-tribo.md) (cai a parte de
  ponto de custódia; a proximidade por distância mínima continua valendo),
  [0024](./0024-carteira-de-patrocinador.md) (o aporte fica, o vínculo com transportadora sai),
  [0027](./0027-resgate-queima-token.md) (a ponta de emissão continua sendo o aporte, agora do
  apoiador)
- Migration: `V28__remover_extensao_logistica.sql`; seed: `V907__seed_apoiadores.sql`
