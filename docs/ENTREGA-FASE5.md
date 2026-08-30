# PBL Fase 5 — Smart HAS · Omni-Tribo

**FIAP — Sistemas de Informação**
**RM 555833 — Renan Ferreira**

**Repositório:** https://github.com/RenanFerreira02/Omni-Tribo-PBL
**Vídeo (YouTube, não listado):** `COLE-A-URL-DO-VIDEO-AQUI`

---

## 1. O produto, em uma frase

**Vizinho ajuda vizinho, e o bairro remunera esse cuidado.**

O cuidado de vizinhança já acontece e não é reconhecido. Quem monta o móvel do vizinho, puxa o
mutirão da rua ou tira os recicláveis do prédio faz trabalho real e não recebe nada. O Omni-Tribo dá
a esse trabalho um **registro**, uma **prova** (check-in geolocalizado) e uma **retribuição** que
circula no próprio bairro — XP e token comunitário, resgatável em benefícios de parceiros locais.

**Token é reconhecimento, não dinheiro.** Ele circula entre vizinhos da mesma tribo e **não é
conversível em reais**. Essa recusa é decisão registrada ([ADR 0009](adr/0009-economia-do-cuidado-token-como-recompensa.md) §6):
token conversível é dinheiro, com KYC e enquadramento regulatório junto.

### Como isso responde ao Smart HAS

| Eixo do enunciado | Resposta | Onde está |
|---|---|---|
| **Sociedade 5.0** | Tecnologia centrada num problema humano concreto — o vizinho que precisa e o vizinho que pode — e não em ampliar conectividade. A recompensa é pertencimento e benefício local, não alcance. | [ADR 0009](adr/0009-economia-do-cuidado-token-como-recompensa.md) |
| **Economia auditável** | Três moedas com fronteiras explícitas, um único ponto de emissão (aporte ADMIN, idempotente) e um sumidouro (o resgate queima token). A invariante é enunciável: a soma de carteiras e potes é constante dentro do ciclo e muda só nas duas pontas. | [ADR 0027](adr/0027-resgate-queima-token.md) · [ADR 0024](adr/0024-carteira-de-patrocinador.md) |
| **Prova, não confiança** | Check-in geolocalizado validado no servidor com PostGIS, antifraude cinemático, ledger append-only e reconciliação ledger × projeção. O que os controles **não** pegam está escrito. | [antifraude](seguranca/antifraude-geolocalizacao.md) · [integridade](qualidade/integridade-transacional.md) |

> **O projeto respondia a três eixos, e um deles foi REMOVIDO em 2026-08-30.** A extensão logística —
> webhook de transportadora, ponto de custódia, missão de retirada e o modelo de previsão de risco —
> saiu inteira. A decisão, o que sobreviveu e o que se perdeu com ela estão no
> [ADR 0031](adr/0031-remocao-da-extensao-logistica.md). **O eixo "sistema inteligente de apoio à
> decisão" ficou sem implementação**, e isso está dito lá em vez de maquiado aqui.

As quatro categorias de missão: **AJUDA** (uma mão para montar, carregar, instalar), **TRIBO**
(mutirão de rua), **COLETA** (recicláveis) e **ENTREGA** (levar algo a alguém, incluindo o caso
patrocinado). Três das quatro não têm nada de logística.

---

## 2. Parte 1 — Stack tecnológica e justificativa

### A escolha: Opção A, migração para React Native

A Fase 4 tinha um **protótipo em Flutter que foi descartado**, e a reconstrução trocou a stack:
backend Java/Spring Boot e app **React Native + Expo SDK 57** (RN 0.86.2), TypeScript strict.

**Por que a migração se justifica tecnicamente**, e não por moda:

1. **Uma base de código, dois sistemas operacionais**, com o time que existe — uma pessoa.
2. **Demonstração sem build nativo.** O app roda no **Expo Go pelo QR code**. Isso não é conveniência
   de desenvolvimento: é o que torna a demonstração desta entrega reproduzível em qualquer aparelho
   do avaliador, sem cadeia de assinatura.
3. **O protótipo descartado tinha defeitos de produto, não de framework.** Distância e valor eram
   `String`, não havia autenticação, e **aceitar uma missão creditava a recompensa na hora**. É por
   isso que hoje `CONCLUIDA` é o único estado que credita, verificado por teste. A comparação
   honesta entre Flutter, Kotlin nativo e React Native está em
   [COMPARATIVO-TECNOLOGIAS.md](COMPARATIVO-TECNOLOGIAS.md), **incluindo o que a escolha custou**.

### O que foi implementado

**12 telas** mais uma rota-porta (`app/index.tsx`, um `<Redirect>` que decide entre onboarding,
autenticação e abas durante a renderização — não num `useEffect`, que deixaria a tela protegida
montar antes de redirecionar).

Componentes exigidos pelo enunciado, todos presentes e verificáveis por `grep`:

| Componente | Ocorrências | Exemplo |
|---|---|---|
| `View` | 212 | toda tela |
| `Text` | 355 | toda tela |
| `Image` | 5 | [`app/(app)/sobre.tsx`](../apps/mobile/app/(app)/sobre.tsx) |
| `Button` | 6 | [`app/(app)/sobre.tsx`](../apps/mobile/app/(app)/sobre.tsx) |

O padrão do design system é `Botao` (sobre `Pressable`), porque o `Button` do React Native não
aceita estilo. A tela **Sobre** é a exceção deliberada: numa tela de créditos a simplicidade dele não
destoa, e é onde a tese do produto é dita ao usuário dentro do app.

### Roadmap tecnológico

**Concluído antes desta fase**
- Backend F0–F8: autenticação JWT, missões com máquina de 9 estados e 17 transições, geolocalização
  PostGIS, carteira com ledger append-only, notificações, integrações externas
- Mobile F9–F12: 12 telas, design system, sessão segura, radar geoespacial, carteira
- F12b: medição de carga (k6, três cenários)
- F13: entrega acadêmica, diagramas, matriz de rastreabilidade

**Feito NESTA fase**
- **Parte 3 completa**: dashboard administrativo em Angular 22.1 (`apps/dashboard`), do zero
- **Parte 2**: página Spring MVC + Thymeleaf (`GET /status`), completando o requisito
- Formulário de escrita no dashboard, ligado a `POST /api/v1/admin/beneficios` (só ADMIN)
- CORS configurado para o dashboard, com correção de um defeito que bloqueava cinco endpoints
- **Reposicionamento social** do produto: tese, documentação e textos de UI
- Tela **Sobre** no mobile, com `Image` e `Button`

**Próximas fases**
- Fechar as duas pendências diagnosticadas e registradas em `CLAUDE.md`: a outbox abandona evento em
  silêncio após 5 tentativas (sem carta-morta); e nada localiza pote de token imobilizado em missão
  parada. Havia uma terceira — o alerta de ponto lotado sem teto —, que **deixou de existir** com a
  remoção do eixo logístico em vez de ser corrigida
- Acessibilidade: passada de TalkBack no Android (lacuna L4 da auditoria mobile)

---

## 3. Parte 2 — Back-end com Spring Boot

**Java 21 · Spring Boot 4.1 · Maven · PostgreSQL + PostGIS · Flyway**

### API REST

**20 controllers**, organizados em monólito modular: um pacote por módulo, cada um com `api/`
(controllers, DTOs, portas), `dominio/` (entidades, regras) e `infra/` (repositórios, clientes).
Módulo só acessa outro por porta pública ou evento — **regra verificada por ArchUnit**, não por
disciplina.

Superfície principal: `/auth`, `/missoes` (lista, radar geoespacial, criação e 10 ações de
transição), `/carteira`, `/tribos`, `/beneficios`, `/resgates`, `/alertas`, `/usuarios`, `/clima` e
`/enderecos`, mais a área `/admin`. **Nenhuma rota de escrita é anônima.**

### Autenticação e autorização

- **JWT RS256** (assimétrico: verificar não exige o segredo de assinar) + **Argon2** para senha
  (resistente a GPU, ao contrário de hash rápido) — [ADR 0005](adr/0005-autenticacao-jwt-argon2.md)
- Access token de 15 min, refresh de 30 dias com rotação e detecção de reuso
- **11 anotações `@PreAuthorize`** restringindo operações a ADMIN
- Bloqueio progressivo de login e rate limit por usuário

### Persistência

- **PostgreSQL + PostGIS**: o produto é geoespacial (raio de check-in, radar de proximidade), e o
  PostGIS resolve isso **no banco**, com índice GiST, em vez de trazer linhas para filtrar em Java
- **Flyway** é a única fonte de schema, `ddl-auto` sempre `validate`: **25 migrations de schema** e
  **7 de seed**
- Dinheiro é `numeric(12,2)`→`BigDecimal`, token é `bigint`, coordenada é `geography(POINT,4326)`
- `lancamento`, `auditoria` e `checkin` são **append-only** — correção por estorno, nunca `UPDATE`.
  A aplicação conecta com um papel que **não tem permissão** de apagar nessas tabelas, e isso é
  provado em runtime por teste (SQLState 42501), não afirmado

### Erros e validação

Toda resposta de erro é **RFC 9457 `ProblemDetail`**, com um catálogo de URIs estáveis no campo
`type` — **uma URI por reação de interface**, não por causa ([ADR 0010](adr/0010-catalogo-de-tipos-de-problema.md)).
O cliente discrimina pelo `type`, nunca pelo `detail`, que é texto para humano e muda a cada revisão
de copy. Validação por Bean Validation nos DTOs, com `errors[{campo, mensagem}]` prontos para marcar
o campo no formulário.

### Documentação e página server-side

- **Swagger/OpenAPI** por springdoc: `/swagger-ui.html` e `/v3/api-docs`. Um teste
  (`ContratoOpenApiTest`) reprova o build se um endpoint existir sem estar descrito no schema.
- **Spring MVC + Thymeleaf**: `GET /status` renderiza no servidor nome, versão, perfil ativo, estado
  do banco e contagem de migrations. É demonstração de MVC e **nada mais** — a interface
  administrativa é o dashboard Angular, e há teste que reprova a inclusão de formulário ou menu ali.

### Qualidade

`./mvnw verify` não é só teste: inclui **Spotless**, **SpotBugs** em `failOnError` e **dois gates
JaCoCo bloqueantes** (80% global, 85% nos pacotes de domínio). Testes de integração usam
**Testcontainers com PostGIS real** — nunca H2 para geoespacial. Operações de valor têm teste de
concorrência multi-thread.

---

## 4. Parte 3 — Dashboard Angular

**Angular 22.1 · standalone components · zoneless (signals) · CSS próprio, sem biblioteca de UI**

`apps/dashboard` consome a **mesma API REST** do app mobile.

| Requisito | Onde |
|---|---|
| Serviços com `HttpClient` | `core/auth.service.ts`, `core/painel.service.ts` |
| Interceptor de autenticação | `core/auth.interceptor.ts` — anexa `Authorization: Bearer` |
| Guard de rota | `core/auth.guard.ts` — devolve `UrlTree`, cancelando a navegação |
| Rotas | `/login`, `/home`, `/admin` |
| `{{ }}` interpolação | 73 ocorrências |
| `[ ]` property binding | 6 — `[disabled]`, `[style.width.%]`, `[class]`, `[attr.aria-*]` |
| `( )` event binding | 9 — `(ngSubmit)`, `(click)` |
| `[( )]` two-way | 9 — `[(ngModel)]` nos 7 campos do formulário |
| `*ngIf` | 40 · **`*ngFor`** 12 |
| Formulário funcional | cadastro de benefício de parceiro em `/admin` |
| Feedback visual | estados de carregando, vazio, erro e sucesso, com cor e mensagem |

**O formulário tem validação no cliente espelhando a do servidor — e o documento diz que ela não o
substitui.** Obrigatoriedade, tamanho, padrão do código, faixa de coordenada e capacidade positiva
são conferidos na tela para poupar uma ida ao servidor; quem decide é o backend, que ainda verifica
o que só ele sabe (código duplicado, tribo existente) e tem a constraint do banco como barreira
final. Nada do backend foi afrouxado para o formulário funcionar.

**Estado vazio que ensina.** Quando um filtro devolve zero linhas, a tela explica que a consulta
funcionou, por que está vazia e o que fazer — em vez de ficar em branco.

---

## 5. Divergências declaradas

Esta seção existe porque afirmar conformidade que não se tem é pior que a lacuna.

**1. Navegação: Expo Router, não React Navigation.**
O enunciado pede React Navigation. O app usa **Expo Router 57**, o roteador oficial do Expo, com
rotas baseadas em arquivos. **Medido:** `expo-router@57.0.11` depende de `standard-navigation`, e
`@react-navigation` **não existe** em `node_modules` — nesta versão o Expo Router **não** embrulha o
React Navigation, ao contrário do que se costuma afirmar. Não migramos porque a troca reescreveria
as telas, os quatro layouts de grupo, o guard de sessão e os arquivos de teste — e é o Expo
Router que sustenta a demonstração pelo Expo Go. A decisão é consciente, e está aqui em vez de
escondida.

**2. Banco: PostgreSQL + PostGIS, não Firebase.**
O enunciado diz "configure um banco de dados de forma apropriada (Firebase, por exemplo)". O produto
é geoespacial: raio de check-in, radar por proximidade, distância medida no servidor. Firebase não
faz consulta geoespacial com índice; PostGIS faz, com GiST, e há evidência de `EXPLAIN ANALYZE`
provando o uso do índice sobre 200 mil linhas. Além disso a carteira exige transação com
`SELECT ... FOR UPDATE` e ordem determinística de lock.

**3. Um eixo do enunciado ficou sem implementação.**
O "sistema inteligente de apoio à decisão" era a regressão logística que previa falha de entrega, e
ela saiu junto com a extensão logística que a consumia (ADR 0031). O modelo era treinado em dados
SINTÉTICOS, e isso sempre esteve declarado; removê-lo é uma perda deliberada de escopo, não um
esquecimento — e preferimos declará-la a manter um modelo vivo sem ninguém que o chame.

**4. Duas pendências conhecidas e não corrigidas**, listadas no roadmap acima. Estão registradas
como decisão pendente porque fechá-las muda contrato de entrega de notificação.

**5. A documentação em PDF da Fase 4** (`documentacao/`) é um PETI e **não é fonte de verdade
técnica**. Onde a implementação diverge dela, e por quê, está em
[DIVERGENCIAS-DOCUMENTACAO.md](DIVERGENCIAS-DOCUMENTACAO.md).

---

## 6. Como executar

```bash
# 1. Chaves de desenvolvimento (uma vez, num clone novo)
bash tools/gerar-chaves-dev.sh

# 2. Banco
make up

# 3. Backend  → http://localhost:8080 · Swagger em /swagger-ui.html · Thymeleaf em /status
cd services/api && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev

# 4. Dashboard → http://localhost:4200
cd apps/dashboard && npm install && npm start

# 5. App mobile → leia o QR com o Expo Go
cd apps/mobile && npm install && npm start
```

Contas do seed (senha `Senha@123`): `admin@omnitribo.dev` (ADMIN) · `alice@omnitribo.dev` (usuário).
Lista completa em [INFRA.md](INFRA.md).

**Verificação:**
```bash
cd services/api && ./mvnw verify                                   # 722 testes + 2 gates JaCoCo
cd apps/mobile  && npm run typecheck && npm run lint && npm test   # 223 testes
cd apps/dashboard && npx ng build
```
