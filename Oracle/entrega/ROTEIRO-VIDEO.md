# Roteiro do vídeo — PBL Fase 6 (5 minutos)

Publicar no YouTube como **não listado**. Depois de publicar, gerar o pacote de novo com o link
(ver [README.md](README.md)) — o enunciado pede o link no documento **e** nos slides.

O vídeo tem duas partes: os slides (cerca de 2 min 20 s) e a demonstração rodando (cerca de
2 min 30 s). **A demonstração é obrigatória** pelo enunciado; se o tempo apertar, corte fala de
slide, não a demo.

## Antes de gravar

Deixe tudo aberto e pronto. Nada de digitar senha ou esperar build com a gravação rodando.

```bash
# Terminal 1 — banco Oracle no estado inicial
export JAVA_HOME=~/.sdkman/candidates/java/current SQLCL=~/.local/share/sqlcl/bin/sql
bash Oracle/executar.sh instalar.sql

# Terminal 2 — Java que chama as procedures (porta 8085)
set -a; source Oracle/.env; set +a
services/api/mvnw -f Oracle/java/pom.xml spring-boot:run

# Terminais 3 e 4 — sistema principal, para mostrar o dashboard
make reset && make up                      # o banco de dev precisa estar na versão atual
cd services/api && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev
cd apps/dashboard && npm start             # http://localhost:4200
```

Tenha abertos: o PDF dos slides em tela cheia, o terminal 1 com fonte grande, e o navegador em
`localhost:4200` **já logado** como `admin@omnitribo.dev` / `Senha@123`, na tela `/admin`.

Os comandos `curl` da demonstração estão em [`../README.md`](../README.md#4-java--oracle). Deixe-os
copiados num arquivo de texto para colar.

> O dashboard só mostra linhas em "Potes imobilizados" se houver missão parada no PostgreSQL de
> dev, e o seed não tem nenhuma. Sem isso a seção aparece com zero — o que também é uma resposta
> válida, mas rende menos na tela. Se quiser linhas, leve uma missão até `EM_ANDAMENTO` pelo app
> antes de gravar.

---

## 0:00 – 0:20 · Identificação — slide 1

> "Renan Ferreira, RM 555833, Sistemas de Informação. Este é o Omni-Tribo na Fase 6 do PBL: a
> camada Oracle com PL/SQL, integrada ao back-end Java."

## 0:20 – 0:40 · O projeto — slide 2

> "O Omni-Tribo é um app de missões de bairro. O vizinho ajuda, comprova com check-in
> geolocalizado e recebe um token comunitário. Até a Fase 5 eu tinha app, API e dashboard. Nesta
> fase entrou o Oracle."

## 0:40 – 1:05 · Arquitetura e modelo — slides 3 e 4

> "O Oracle entra ao lado do PostgreSQL, não no lugar dele: o sistema depende do PostGIS para a
> parte geoespacial. O Oracle recebe os dados do próprio sistema, em 12 tabelas, e é sobre elas que
> o PL/SQL roda. As regras vieram junto: token é inteiro, o extrato é append-only por trigger, e
> nenhum dado pessoal foi copiado."

## 1:05 – 1:40 · Functions e procedures — slides 5 e 6

> "São três functions principais: duas calculam indicadores — a taxa de conclusão da tribo e a
> divergência entre carteira e extrato — e uma devolve o resumo da missão formatado. Todas rodam
> dentro do SELECT."
>
> "E três procedures. A principal é a varredura: missão que parou além do prazo é encerrada, e o
> token de quem financiou volta. Ela usa dois cursores, savepoint e tratamento de exceção: uma
> missão corrompida é isolada, vira alerta, e as outras seguem."

## 1:40 – 2:00 · Java — slide 7

> "A procedure de resgate é acionada pelo Java, por JDBC. A primeira chamada responde 201. Repetir
> com a mesma chave responde 200 com o mesmo resgate, sem debitar de novo. Saldo insuficiente vira
> 422 com a mensagem que a própria procedure escreveu."

## 2:00 – 2:20 · Parte 1 e resultados — slides 8 e 9

> "Na melhoria do sistema, o painel passou a mostrar token imobilizado em missão parada — algo que
> a verificação de integridade não enxergava. E tudo aqui foi executado no Oracle da FIAP: 23
> objetos válidos e 90 de 90 testes."

---

## 2:20 – 4:50 · Demonstração — slide 10 e depois as telas

Mostre o slide 10 por dois segundos e troque para o terminal.

### 2:20 – 2:50 · Instalação (terminal 1)

Role a saída de `instalar.sql` até a lista de objetos.

> "Esta é a instalação no Oracle da FIAP. Tabelas, triggers, functions e procedures, todos VALID,
> e nenhum erro de compilação."

### 2:50 – 3:35 · Functions e varredura (terminal 1)

```bash
bash Oracle/executar.sh 06_consultas_de_uso.sql
```

Pare em três pontos da saída:

1. **Seção 1**, o ranking de tribos.
   > "A function de indicador dentro do SELECT. Tribo sem missão encerrada mostra 'sem dado', não
   > zero por cento."
2. **Seção 3**, os potes imobilizados.
   > "A function de formatação. Quatro missões com token parado, e todas as carteiras íntegras logo
   > acima."
3. **Seção 6**, a varredura.
   > "A procedure encerrou quatro missões, devolveu 60 tokens e isolou a quinta, que eu corrompi de
   > propósito. Aqui embaixo estão os alertas que ela gravou."

### 3:35 – 4:20 · Java chamando o Oracle (terminal 2 visível ao fundo)

Cole os três `curl`, um de cada vez:

> "Agora o Java. Resgate da Marlene: 201, com o código de retirada."
>
> "A mesma chamada de novo: 200, replay verdadeiro, mesmo código, saldo igual."
>
> "E o Gustavo, que não tem token: 422, com a mensagem da procedure."

### 4:20 – 4:50 · Dashboard (navegador)

Role a tela `/admin` até "Integridade do ledger" e "Potes imobilizados".

> "E no sistema principal: a integridade do ledger diz que está tudo certo, e logo abaixo a seção
> nova mostra o token que está preso em missão parada."

---

## 4:50 – 5:00 · Encerramento

> "O código, as evidências e a documentação estão no repositório. Obrigado."

---

## Se algo falhar na gravação

| Sintoma | O que fazer |
|---|---|
| `ORA-01017` ao conectar | Senha em `Oracle/.env` errada ou conta bloqueada |
| A varredura mostra "0 expiradas" | O banco já foi varrido: rode `instalar.sql` de novo |
| O resgate responde 200 logo na primeira chamada | A chave `Idempotency-Key` já foi usada: troque o valor ou reinstale |
| A API principal não sobe | O banco de dev está defasado: `make reset` |
| Passou de 5 minutos | Corte os slides 5 e 6 para uma frase cada; a demo fica |
