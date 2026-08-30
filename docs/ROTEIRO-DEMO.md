# Roteiro de demonstração — 10 minutos

**Regra número um: nada é instalado, clonado ou compilado durante a demonstração.** Tudo abaixo
pressupõe o preparo da seção final já feito. Se o tempo apertar, corte o bloco 7 — ele é o único
opcional.

**O único bloco que depende de rede externa é o 5.** Todos os outros rodam contra `localhost`. Cada
bloco tem plano B.

O fio condutor é **um ciclo econômico completo, com uma pessoa só**: o apoiador aporta → um vizinho
pede ajuda e a missão nasce → outro vizinho financia o pote → o executor aceita e faz o check-in → o
criador confirma e ele é creditado → ele resgata um benefício no bairro, e o token é queimado. Tudo
na zona leste, tribo Cidade Líder, com `renan@omnitribo.dev`.

---

## Antes de entrar na sala (15 min)

```bash
cd Omni-Tribo
bash tools/gerar-chaves-dev.sh          # idempotente: não faz nada se as chaves existem
make reset                              # banco limpo, seed reconstruído no boot

# terminal 1 — deixe rodando
cd services/api && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev

# terminal 2 — deixe rodando
cd apps/mobile && npm start

# confirme, e só entre na sala depois de ver o pong:
curl -s http://localhost:8080/api/v1/ping
```

Guarde o token de ADMIN no terceiro terminal — os blocos 2 e 7 usam:

```bash
ADMIN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@omnitribo.dev","senha":"Senha@123"}' | jq -r .accessToken)

RENAN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"renan@omnitribo.dev","senha":"Senha@123"}' | jq -r .accessToken)
```

**Deixe abertos:** os dois terminais, um terceiro terminal livre na raiz do projeto, o navegador em
`http://localhost:8080/swagger-ui.html`, e o app já **logado como `renan@omnitribo.dev`**
(senha `Senha@123`).

> **Não faça login na frente da banca sem necessidade.** O bloqueio antifraude é de 5 tentativas por
> minuto: um erro de digitação no telefone custa 60 segundos de silêncio constrangedor.

---

## 0:00–1:00 · O problema

Sem tela. Duas frases:

> "O cuidado de vizinhança já acontece e não é reconhecido. Quem monta o móvel do vizinho, puxa o
> mutirão da rua ou tira os recicláveis do prédio faz trabalho real e recebe zero — e quem precisa
> não tem como pedir sem parecer que está pedindo favor."
>
> "A tese do projeto é dar a esse trabalho três coisas que ele não tem: um **registro**, uma
> **prova** — o check-in geolocalizado — e uma **retribuição** que circula no próprio bairro."

**Plano B:** nenhum. Não depende de nada.

---

## 1:00–2:00 · De onde o token vem — o aporte

Comece pela ponta que quase nenhum projeto mostra: **a emissão**.

```bash
curl -s -X POST http://localhost:8080/api/v1/admin/patrocinadores/77777777-0000-0000-0000-000000000950/aportes \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: demo-$(date +%s)" \
  -d '{"tokens":500}' | jq
```

```json
{ "patrocinadorId": "77777777-0000-0000-0000-000000000950",
  "lancamentoId": "37581294-8280-41da-b1fd-fe4398300cd6",
  "saldoTokens": 5500, "replay": false }
```

> "Este é o **único ponto de emissão de token do sistema inteiro**. Endpoint de ADMIN, auditado,
> idempotente. Antes ele não existia: a recompensa de ENTREGA e AJUDA era cunhada na conclusão, uma
> missão por vez, e ninguém conseguia somar quanto tinha sido emitido. A cunhagem não desapareceu —
> ela mudou de lugar, e é isso que a torna defensável."

**Plano B:** se o `curl` falhar, o backend caiu — é local. Suba de novo. Se o `Idempotency-Key`
repetir, a resposta vem com `"replay": true` e **nada é emitido**: mostre isso, é a idempotência
funcionando.

---

## 2:00–4:00 · O ciclo da missão, do pedido ao crédito

O coração do projeto. Use o app (Expo Go) para criar e aceitar, e o terminal para mostrar o que o
servidor decidiu.

**1. Prévia da recompensa, ANTES de criar.** É o servidor calculando — o app nunca duplica a fórmula:

```bash
curl -s -X POST http://localhost:8080/api/v1/missoes/previa-recompensa \
  -H "Authorization: Bearer $ALICE" -H 'Content-Type: application/json' \
  -d '{"categoria":"AJUDA","complexidade":"MEDIA","origemLat":-23.5640,"origemLon":-46.6934,
       "cep":"05422030","logradouro":"Rua dos Pinheiros, 500","bairro":"Pinheiros",
       "cidade":"São Paulo","uf":"SP","raioCheckinM":50,"valorBrl":0,
       "janelaInicio":"2026-09-01T12:00:00Z","janelaFim":"2026-09-02T12:00:00Z"}' | jq
```

> "A recompensa é **calculada pelo servidor e congelada na criação**, junto com a `versaoFormula`. O
> DTO de criação não tem campo de recompensa — mandá-lo seria silenciosamente ignorado, e o criador
> veria um número na tela e outro na missão publicada."

**2. Publicar exige pote.** Crie a missão pelo app, tente publicar, e mostre o 422:

> "Missão que paga do pote só é publicável com o pote já cobrindo a recompensa. Sem essa guarda, ela
> chegaria em AGUARDANDO_CONFIRMACAO sem poder ser concluída — e o executor teria feito o trabalho
> para receber um erro."

**3. Quem financia não é quem cria.** Use o apoiador do bloco anterior — é o token que você acabou
de emitir entrando no ciclo:

```bash
curl -s -X POST "http://localhost:8080/api/v1/admin/missoes/$MISSAO/financiamento-apoiador" \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: demo-fin-$(date +%s)" \
  -d "{\"patrocinadorId\":\"$APOIADOR\",\"tokens\":30}" | jq
```

> "Quem cria a missão **não paga** — essa é a premissa do produto. O pote é formado por outros:
> membros da tribo, pelo app, ou o apoiador do bairro, que é quem recebeu o aporte de um minuto
> atrás. Repare que a soma em circulação **não muda aqui**: o aporte emitiu, este passo só move o
> token para o pote."

Se quiser mostrar o caminho do vizinho, financie pelo app com um segundo usuário da MESMA tribo —
`POST /tribos/{id}/financiamentos`, com a identidade vindo do JWT. Vale dizer por que são duas rotas:

> "O apoiador é uma conta que **nunca autentica** — nasce inativa de propósito, para que aquela
> carteira só seja movida por caminho auditado. Por isso o financiamento dele é ADMIN: uma rota que
> lesse o JWT dele seria código que nunca roda."

**4. Aceitar → iniciar → check-in → confirmar.** Faça no app, com o GPS. O check-in é o momento:

> "A distância é medida pelo **PostGIS no servidor**, contra a origem da missão. O app manda
> coordenada, nunca distância — se mandasse, seria o cliente decidindo se esteve lá."

E o fecho, no terminal:

```bash
curl -s http://localhost:8080/api/v1/carteira -H "Authorization: Bearer $BOB" | jq .saldoTokens
```

> "`CONCLUIDA` é o **único** estado que credita: aceitar não credita, que era exatamente o que o
> protótipo descartado fazia errado."

**Plano B:** se o GPS do aparelho não colaborar, faça o check-in por `curl` com as coordenadas da
origem da missão — o servidor não distingue, e é justamente esse o ponto: quem valida é ele.

---

## 4:00–5:00 · Onde o token morre — o resgate

A outra ponta. Primeiro a vitrine:

```bash
curl -s "http://localhost:8080/api/v1/beneficios?triboId=aaaaaaaa-0000-0000-0000-000000000901" \
  -H "Authorization: Bearer $RENAN" | jq -r '.conteudo[] | "\(.custoTokens) tokens · \(.titulo) (\(.parceiroNome))"'
```

```
10 tokens · Um remendo de câmara de ar (Bicicletaria do Zé)
15 tokens · Um café coado e um pão na chapa (Padaria Pão da Praça)
25 tokens · Uma fornada de pão francês (500 g) (Padaria Pão da Praça)
30 tokens · 15% de desconto na feira da semana (Mercearia Dona Neusa)
40 tokens · 20% de desconto na revisão da bicicleta (Bicicletaria do Zé)
```

> "Nenhum benefício se anuncia em reais, e isso é barrado em duas camadas — a borda responde 400 e o
> banco tem `CHECK`. Preço em moeda corrente publicaria uma cotação token→real, que o ADR 0009 recusa
> explicitamente: token conversível *é* dinheiro, com KYC junto."

E o resgate:

```bash
curl -s -X POST http://localhost:8080/api/v1/resgates \
  -H "Authorization: Bearer $RENAN" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: demo-resgate-$(date +%s)" \
  -d '{"beneficioId":"33333333-0000-0000-0000-000000000960"}' | jq
```

```json
{ "custoTokens": 15, "codigoRetirada": "NURE8YPY", "status": "PENDENTE",
  "saldoTokensRestante": 175, "replay": false }
```

> "**É aqui que o token é queimado.** O lançamento debita com motivo `RESGATE` e **não credita
> ninguém** — sem contraparte, sem missão. É o que o separa de uma transferência, onde as duas pernas
> somam zero. E o código de retirada **não é credencial**: quem autoriza a baixa é o ADMIN, pelo id."

**Plano B:** se o saldo não der, resgate o remendo de câmara de ar (10 tokens). Se o catálogo vier
vazio, o `triboId` está errado — é o da Tribo Cidade Líder, onde estão os parceiros do seed.

---

## 5:00–6:00 · Resiliência: o bloco que depende de rede

```bash
curl -s "http://localhost:8080/api/v1/enderecos/01310100" | jq
curl -s "http://localhost:8080/api/v1/clima?lat=-23.564&lon=-46.6934" | jq
```

> "O app nunca fala com ViaCEP ou Open-Meteo direto. Passa pela nossa fronteira, atrás de
> **cache → disjuntor → bulkhead → retry**. O retry roda **por dentro** do disjuntor, para que uma
> rajada de tentativas conte como uma única falha."

### Plano B — e ele é melhor que o plano A

**Se a rede da sala falhar, demonstre a falha de propósito.** Desligue o Wi-Fi e repita o `curl`:

```json
{ "type": "https://omnitribo.dev/problemas/servico-externo-indisponivel", "status": 503 }
```

> "É o comportamento projetado: 503 com um `type` estável, e a reação de UI é **esconder** o recurso
> — o app não mostra erro de clima, ele simplesmente não mostra clima. Um card de conveniência fora
> do ar não pode derrubar a tela do mapa."

**Ensaie este plano B.** Ele responde à pergunta "e se cair?" com uma demonstração em vez de uma
promessa.

---

## 6:00–8:00 · A economia, e o defeito que a auditoria achou

Este é o bloco que diferencia o projeto. No terminal livre:

```bash
bash tools/evidencias/conservacao-por-categoria.sh
```

Ele roda os quatro ciclos completos, mais um quinto sem patrocínio, e imprime ao final:

```
TRIBO    Δ=0  recompensa=38
COLETA   Δ=0  recompensa=35
AJUDA    Δ=0  recompensa=30
ENTREGA  Δ=0  recompensa=66  (pote pago pelo patrocinador)
conservação: baseline=10845  final=10845
reconciliação final: {"integro":true,"divergencias":0}
```

O roteiro de fala, em três tempos:

1. **"Uma auditoria deste projeto encontrou uma impressora de dinheiro."** Concluir ENTREGA ou AJUDA
   criava token do nada. Antes disso, o mesmo padrão no BRL levou o sistema de R$ 118 para R$ 1.618
   em três ciclos, e o saldo do criador não se moveu — ele nunca pagou.
2. **"E o endpoint de integridade dizia que estava tudo certo — corretamente."** A reconciliação
   compara saldo com o histórico da carteira. Cunhar escreve **os dois lados**, então a igualdade
   continua verdadeira. Ela responde a outra pergunta.
3. **"A distinção que aprendemos: reconciliação não é conservação."** Uma tem endpoint; a outra não.
   **Uma invariante que ninguém mede não está garantida.**

Feche mostrando que ela fechou, e o que sobrou:

> "Hoje as quatro categorias conservam. A emissão virou um ponto só — o aporte que vocês viram no
> começo — e o resgate virou o sumidouro. A soma não é constante: ela **sobe no aporte e desce no
> resgate**, e não muda em mais lugar nenhum. O que ainda cunha é ENTREGA criada por um humano — e
> isso está declarado na linha da missão, em `fonte_pote`, não escondido num `if`."

**Plano B:** se o script falhar, os mesmos números estão em
[`evidencias/f14-conservacao-quatro-categorias.md`](evidencias/f14-conservacao-quatro-categorias.md),
já executados. Abra o arquivo.

---

## 8:00–9:00 · A integridade do ledger *(opcional)*

```bash
curl -s http://localhost:8080/api/v1/admin/carteiras/reconciliacao \
  -H "Authorization: Bearer $ADMIN" | jq
```

```json
{ "carteirasVerificadas": 12, "integro": true, "divergencias": [] }
```

> "Ele compara, carteira a carteira, o saldo projetado com a soma do ledger. É a resposta para
> 'algum token apareceu ou sumiu sem lançamento?'."

Vale dizer em voz alta o que ele **não** é — e é o ponto mais forte deste bloco:

> "Isto **não prova conservação**. São invariantes diferentes: a reconciliação passa enquanto a
> conservação pode estar sendo violada, e foi exatamente assim que o defeito econômico ficou
> invisível por semanas — ledger e projeção batendo, com token cunhado do nada. Quem prova
> conservação é a medição de soma antes-e-depois, no bloco anterior."

> **Havia aqui um painel de impacto**, `GET /admin/impacto`, com o funil da entrega falida e o custo
> de re-entrega evitado. Ele saiu junto com o eixo logístico (ADR 0031): sem aquele ciclo, os quatro
> blocos ficavam sem numerador.

**Plano B:** corte este bloco. É o único opcional.

---

## 9:00–10:00 · Qualidade: por que acreditar nos números

Mostre, sem rodar (o `verify` leva ~1 min e não cabe aqui):

| Abra | Diga |
|---|---|
| [`evidencias/f21-carga.md`](evidencias/f21-carga.md) | "14.967 requisições, **zero 5xx**. O radar não tem joelho até 74,6 req/s. O achado da medição foi o alerta de ponto lotado escrevendo 631 linhas idênticas sem teto — ele foi registrado como pendência em vez de corrigido às pressas, e **deixou de existir** quando o eixo logístico saiu" |
| [`evidencias/f6-explain-analyze.md`](evidencias/f6-explain-analyze.md) | "`EXPLAIN ANALYZE` real provando uso do índice GiST — não é 'usamos índice', é a saída do planejador" |
| [`qualidade/integridade-transacional.md`](qualidade/integridade-transacional.md) | "100 threads, deadlock cruzado, rollback. E a seção **'o que esta fase NÃO garante'**" |
| [`qualidade/mutacao.md`](qualidade/mutacao.md) | "teste de mutação sem gate: o número vai para o relatório, não para a porta. O valor está nos sobreviventes — quatro fronteiras de saldo sem teste no valor exato" |
| [`EVOLUCAO-ARQUITETURAL.md`](EVOLUCAO-ARQUITETURAL.md) | "**cinco dos sete defeitos da rodada F0→F7 eram invisíveis lendo o código**" |

Frase de encerramento:

> "O projeto não acertou de primeira. Ele mediu, encontrou o próprio erro e o corrigiu — e o que
> continua aberto está escrito, com o número medido do lado."

**Plano B — sem projetor:** os arquivos são Markdown e leem no GitHub pelo celular.

---

## Perguntas prováveis, e onde a resposta está

| Pergunta | Resposta curta | Documento |
|---|---|---|
| "Por que monólito e não microsserviços?" | Um time, um deploy, uma transação. A fronteira está pronta para extrair, e há ordem definida | [ADR 0001](adr/0001-monolito-modular.md) · [arquitetura-alvo](diagramas/arquitetura-alvo.md) |
| "Cadê o sistema inteligente de apoio à decisão?" | Existiu, previa falha de entrega, e saiu com a extensão logística. O eixo ficou **sem implementação**, e a decisão está registrada com o que se perdeu | [ADR 0031](adr/0031-remocao-da-extensao-logistica.md) |
| "Quem garante que o token não é inflacionado?" | A emissão tem um ponto só, auditado; a conservação foi medida nas quatro categorias com Δ=0 | [ADR 0024](adr/0024-carteira-de-patrocinador.md) · [f14](evidencias/f14-conservacao-quatro-categorias.md) |
| "Cadê os 50 metros do brief?" | Divergimos, por três razões medidas — inclusive porque "está em casa" não é observável sem rastreamento contínuo | [ADR 0020](adr/0020-ponto-de-custodia-comercial-e-proximidade-por-tribo.md) · [divergências](DIVERGENCIAS-DOCUMENTACAO.md) |
| "Por que a extensão logística saiu?" | Decisão de produto: manter só o eixo social. O que ela sustentava — a emissão de token e o fan-out de notificação — foi preservado com outro dono | [ADR 0031](adr/0031-remocao-da-extensao-logistica.md) |
| "Isso escala?" | Não como está, e o desenho de como escalaria está separado e marcado como não implementado. A carga medida é de uma máquina, 5 min por cenário | [arquitetura-alvo](diagramas/arquitetura-alvo.md) · [f21-carga](evidencias/f21-carga.md) |
| "Por que React Native e não nativo?" | Custo de demonstrar. E o que a escolha cobrou está listado | [comparativo](COMPARATIVO-TECNOLOGIAS.md) |
| "Como sei que o crédito de seis meses atrás estava certo?" | `versao_formula` fica congelada na missão; há teste dourado que falha se a calibração mudar sem subir a versão — foi ele que forçou a v4 | [ADR 0009](adr/0009-economia-do-cuidado-token-como-recompensa.md) |

---

## Checklist de 30 segundos, antes de começar

- [ ] `curl http://localhost:8080/api/v1/ping` responde `pong`
- [ ] `$ADMIN` e `$RENAN` exportados no terminal livre
- [ ] app aberto e **já logado** como `renan@omnitribo.dev`
- [ ] terminal livre na raiz do projeto
- [ ] Swagger aberto numa aba
- [ ] `make reset` feito **hoje** (banco limpo, sem lixo de ensaio)
- [ ] telefone no modo não perturbe

> **Se você ensaiou, rode `make reset` de novo antes da apresentação.** O ensaio gasta o saldo do
> apoiador, deixa missões em estados intermediários e queima tokens no resgate — e a soma que você
> vai mostrar no bloco da economia já não parte do baseline limpo.
