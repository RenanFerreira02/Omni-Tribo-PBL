# Roteiro do vídeo — PBL Fase 6 (5 minutos)

Publicar no YouTube como **não listado**. Depois de publicar, gerar o pacote de novo com o link
(ver [README.md](README.md)) — o enunciado pede o link no documento **e** nos slides.

O vídeo é gravado **inteiro sobre os slides**: cada um traz, ao lado da explicação, a saída real da
execução no Oracle da FIAP. Não é preciso abrir terminal.

## Antes de gravar

```bash
cd Oracle/entrega
node gerar.mjs
```

Abra `saida/previa-slides.html` no navegador, em tela cheia (F11), e role de slide em slide. Ou use
o PDF `saida/Omni-Tribo-Fase6-RM555833/Omni-Tribo - Fase 6 - Slides.pdf` em modo apresentação.

Nada precisa estar rodando.

> **Sobre "a demonstração do aplicativo rodando".** O enunciado pede isso. Aqui o que aparece é a
> saída de execuções reais, gravada em [`../evidencias/`](../evidencias/), e não a execução ao
> vivo. Se quiser reforçar sem complicar a gravação, termine o vídeo com dez segundos do SQL
> Developer aberto na lista de objetos `OT_`, ou do dashboard em `/admin`.

---

## 0:00 – 0:20 · Slide 1 — Identificação

> "Renan Ferreira, RM 555833, Sistemas de Informação. Este é o Omni-Tribo na Fase 6 do PBL: a
> camada Oracle com PL/SQL, integrada ao back-end Java."

## 0:20 – 0:40 · Slide 2 — O projeto

> "O Omni-Tribo é um app de missões de bairro. O vizinho ajuda, comprova com check-in
> geolocalizado e recebe um token comunitário. Até a Fase 5 eu tinha app, API e dashboard. Nesta
> fase entrou o Oracle."

## 0:40 – 1:00 · Slide 3 — Arquitetura

> "O Oracle entra ao lado do PostgreSQL, não no lugar dele: o sistema depende do PostGIS para a
> parte geoespacial. O Oracle recebe os dados do próprio sistema, e é sobre eles que o PL/SQL roda."

## 1:00 – 1:35 · Slide 4 — Modelo e implantação

Aponte primeiro os grupos de tabelas, depois o bloco à direita.

> "São 12 tabelas, que levam as regras do sistema para o banco: token é inteiro, o extrato é
> append-only por trigger, e nenhum dado pessoal foi copiado."
>
> "À direita está a saída da instalação no Oracle 19c da FIAP: tabelas, triggers, functions e
> procedures, todos VALID, e zero erros de compilação."

## 1:35 – 2:15 · Slide 5 — Functions

Percorra as três seções do bloco, de cima para baixo.

> "As functions rodam dentro do SELECT. Na primeira consulta, a taxa de conclusão por tribo: quem
> ainda não encerrou missão aparece como 'sem dado', não como zero por cento."
>
> "Na segunda, a reconciliação: todas as carteiras íntegras. E na terceira, a function de
> formatação mostra quatro missões com token parado. Ou seja: carteiras certas e, ainda assim,
> token preso. É esse o problema que a procedure resolve."

## 2:15 – 2:55 · Slide 6 — Procedure de varredura

> "A varredura encerra missão que passou do prazo. Usa dois cursores, savepoint e tratamento de
> exceção. O resultado está na segunda linha: duas expiradas, duas concluídas, 60 tokens devolvidos
> e uma falha."
>
> "A falha é proposital: eu corrompi uma missão. A procedure a isolou, gravou o alerta em vermelho
> lá embaixo e seguiu com as outras quatro. Os demais alertas são os avisos a quem recebeu estorno
> e a quem foi pago."

## 2:55 – 3:35 · Slide 7 — Java → Oracle

Vá de bloco em bloco: 201, 200, 422, 404.

> "A procedure de resgate é acionada pelo Java, por JDBC. A primeira chamada responde 201, com o
> código de retirada. A mesma chamada de novo responde 200, com o mesmo resgate e replay
> verdadeiro: nada foi debitado duas vezes."
>
> "Sem saldo, 422 com a mensagem que a própria procedure escreveu. Benefício inativo, 404. E a
> última linha é a conferência direto no banco: um único lançamento para as duas chamadas."

## 3:35 – 4:05 · Slide 8 — Dashboard

> "Na melhoria do sistema, o painel de administração passou a mostrar o token imobilizado em missão
> parada. A verificação de integridade dizia que estava tudo certo com 113 tokens presos. Era uma
> pendência registrada desde agosto, e foi fechada nesta fase, do banco até a tela."

## 4:05 – 4:35 · Slide 9 — Testes

> "Tudo foi executado: 23 objetos válidos, 90 de 90 asserções em PL/SQL e 580 testes no back-end.
> À direita, parte da saída: a conservação dos tokens, a idempotência do resgate e as regras que o
> próprio banco garante, como rejeitar UPDATE no extrato."

## 4:35 – 5:00 · Slide 10 — Encerramento

> "Um defeito só apareceu na execução real: saldo insuficiente respondia 500, com o teste unitário
> passando. Foi corrigido. E os limites estão declarados: as procedures repetem regras que existem
> em Java, sobre uma cópia dos dados. O código e as evidências estão no repositório. Obrigado."

---

## Se passar de 5 minutos

Corte nesta ordem: a segunda fala do slide 6 (os alertas), a segunda fala do slide 5, e o slide 3
para uma frase só. Não corte os slides 4, 7 e 9: são os que provam a execução.
