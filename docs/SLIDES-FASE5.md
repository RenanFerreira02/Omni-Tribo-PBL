# Roteiro dos slides — PBL Fase 5

10 slides, o teto do enunciado. Cada bloco abaixo é um slide: o **título** vai no topo, os bullets
são o corpo, e a **nota** é o que você fala — não o que aparece na tela.

> **Regra que evita o erro mais comum:** nenhum slide leva parágrafo. Se está escrito, você não
> precisa falar; se você vai falar, não escreva. O slide 9 é a demo e quase não tem texto.

---

## Slide 1 — Identificação

**Omni-Tribo · Smart HAS — PBL Fase 5**

- FIAP — Sistemas de Informação
- **Renan Ferreira — RM 555833** + `[FOTO]`
- Link do repositório
- Link do vídeo

> Se o grupo tiver mais integrantes, repita nome + RM + foto de cada um. O enunciado pede isso
> explicitamente e é o primeiro item que se confere.

---

## Slide 2 — O problema

**A ajuda de vizinhança é invisível**

- Solidão urbana e vínculos de bairro enfraquecidos
- Quem já ajuda não tem registro, prova nem retribuição
- Apps ampliam a conectividade virtual enquanto o isolamento cresce

> Comece pela dor social, não pelo sistema. Trinta segundos.

---

## Slide 3 — A tese

**Vizinho ajuda vizinho, e o bairro remunera esse cuidado**

- Pedido de ajuda → missão com escopo, prazo e recompensa
- Prova: **check-in geolocalizado**, validado no servidor
- Retribuição: XP + **token comunitário**, trocado por benefícios locais
- **Token é reconhecimento, não dinheiro** — não converte em reais

> A última linha é a que mais desarma pergunta de banca. Diga que a recusa é decisão registrada
> (ADR 0009), não omissão.

---

## Slide 4 — Onde entra a logística

**Uma extensão, não o produto**

- Entrega falha → encomenda fica no ponto de custódia
- A retirada pelo vizinho **também é ajuda** — mas quem paga é a transportadora
- Único caminho em que o dinheiro vem **de fora** do bairro
- Autenticado por HMAC sobre o corpo bruto

> É aqui que você cobre a "AI Logistics Extension" do enunciado sem transformar o produto num app de
> logística. Uma frase: "é a prova de que a economia do cuidado recebe dinheiro externo sem deixar
> de ser comunitária".

---

## Slide 5 — Parte 1 · Stack mobile

**React Native + Expo SDK 57** (Opção A)

- Protótipo Flutter da Fase 4 **descartado** — por defeito de produto, não de framework
- Uma base, dois sistemas · demonstração pelo **QR do Expo Go**, sem build nativo
- 13 telas · TypeScript strict · design system com contraste auditado
- `View` · `Text` · `Image` · `Button`

> Sobre o protótipo: "aceitar uma missão creditava a recompensa na hora — é por isso que hoje
> CONCLUIDA é o único estado que credita, e isso tem teste".

---

## Slide 6 — Parte 2 · Back-end

**Java 21 · Spring Boot 4.1 · PostgreSQL + PostGIS**

- 20 controllers · monólito modular com fronteira **verificada por ArchUnit**
- JWT RS256 + Argon2 · 11 operações restritas a ADMIN
- Flyway (25 schema + 7 seed) · ledger **append-only**
- Erros RFC 9457 · **Swagger** · página **Thymeleaf** em `/status`

> Se sobrar tempo: "a aplicação conecta com um papel que não consegue apagar do ledger, e isso é
> provado em runtime por teste, não afirmado em comentário".

---

## Slide 7 — Parte 3 · Dashboard Angular

**Angular 22.1 — mesma API do app**

- Rotas `/login` `/home` `/admin` com guard
- `HttpClient` + interceptor que anexa o token
- Binding nas quatro formas · `*ngIf` · `*ngFor`
- Formulário com `[(ngModel)]`: cadastro de ponto de custódia

> Diga que a validação do cliente **não substitui** a do servidor — e que o backend não foi
> afrouxado para o formulário funcionar.

---

## Slide 8 — Qualidade

**O que sustenta as afirmações**

- **722** testes no backend · **223** no mobile
- Dois gates JaCoCo bloqueantes · SpotBugs em `failOnError`
- Testcontainers com **PostGIS real** — nunca H2 para geoespacial
- Testes de concorrência em toda operação de valor

> Um slide de números medidos. Não invente nenhum: rode `./mvnw verify` antes de gravar e use a
> saída do dia.

---

## Slide 9 — DEMONSTRAÇÃO

**`[sem texto — tela cheia]`**

> Este slide existe só para marcar o corte. A partir daqui é tela compartilhada, e o roteiro está em
> `docs/ROTEIRO-VIDEO.md`. **Reserve ao menos 2 dos 5 minutos para isto** — o enunciado pede a
> demonstração do aplicativo rodando, e é o item mais fácil de perder por falta de tempo.

---

## Slide 10 — O que vem depois

**Declarado, não escondido**

- Modelo de risco treinado em **dados sintéticos** — validar com dado real
- Três pendências diagnosticadas e registradas (outbox sem carta-morta; pote imobilizado sem
  diagnóstico; alerta de ponto lotado sem teto)
- Acessibilidade: passada de TalkBack no Android
- **Navegação:** Expo Router, não React Navigation — decisão consciente, medida e documentada

> Fechar admitindo limite é mais forte que fechar prometendo. Se perguntarem do React Navigation,
> a resposta é: "medi — o Expo Router 57 não embrulha o React Navigation, e trocar reescreveria 13
> telas e 18 arquivos de teste na véspera. Está declarado no documento."
