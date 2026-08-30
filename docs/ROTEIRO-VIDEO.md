# Roteiro do vídeo — 5 minutos

**Publicar no YouTube como NÃO LISTADO** e colar o link no documento e no slide 1.

## Antes de gravar

```bash
make up                                                            # banco
cd services/api && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev
cd apps/dashboard && npm start                                     # :4200
cd apps/mobile && npm start                                        # QR do Expo Go
```

Deixe **tudo já rodando e logado** antes de apertar REC. Login ao vivo é onde se perdem 40 segundos
por causa de teclado no celular. Tenha aberto: navegador em `localhost:4200`, uma aba em
`localhost:8080/swagger-ui.html`, uma aba em `localhost:8080/status`, e o celular espelhado.

---

## 0:00 – 0:30 · Identificação e problema

Slides 1 e 2.

> "Renan Ferreira, RM 555833, Sistemas de Informação. O Omni-Tribo parte de uma dor social: a ajuda
> entre vizinhos já acontece, mas é invisível — não deixa registro e não retribui nada a quem ajuda."

---

## 0:30 – 1:10 · Tese e onde a logística entra

Slides 3 e 4.

> "A tese é: vizinho ajuda vizinho, e o bairro remunera esse cuidado. O pedido vira missão com
> escopo e prazo, a prova é o check-in geolocalizado, e a retribuição é token comunitário — que é
> reconhecimento, não dinheiro: não converte em reais, e essa recusa é decisão registrada."
>
> "Existe um caso em que quem paga vem de fora: quando uma entrega falha, a retirada pelo vizinho
> também é ajuda, e aí a transportadora financia. É a extensão de logística do enunciado — uma
> extensão, não o produto."

---

## 1:10 – 2:10 · As três partes, em slides

Slides 5, 6, 7 — **20 segundos cada, sem se demorar.** O detalhe está no documento; aqui é só
mostrar que as três partes existem.

---

## 2:10 – 4:30 · DEMONSTRAÇÃO (o miolo)

**Esta é a parte que não pode ser cortada.** Ordem sugerida — do mais visual para o mais técnico:

### a) App mobile — 50 s
1. Abrir com o Expo Go (mostre o QR por 2 segundos, não mais)
2. **Radar**: lista de missões próximas, com a distância medida pelo servidor
3. Abrir uma missão de **AJUDA** ou **TRIBO** — não comece por ENTREGA
4. **Carteira**: saldo em token e extrato
5. **Perfil → "O que é o Omni-Tribo"**: a tela Sobre, com a tese em tela

> "A distância é calculada pelo PostGIS no servidor; o app nunca informa distância."

### b) Dashboard Angular — 50 s
1. `/login` com `admin@omnitribo.dev` / `Senha@123` *(deixe já digitado)*
2. `/home`: cards de indicador e a lista de missões recentes
3. Trocar o filtro para **"Em disputa"** → mostra o **estado vazio que ensina**
4. `/admin`: listagem de pontos de custódia
5. **Cadastrar um ponto**: submeter com campo inválido → mostra a validação; corrigir → salva e
   **a lista se atualiza sem recarregar a página**

> "A validação do cliente não substitui a do servidor — o backend confere de novo e ainda checa o
> que só ele sabe, como código duplicado."

### c) Back-end — 40 s
1. `localhost:8080/swagger-ui.html` — role a lista de endpoints
2. `localhost:8080/status` — a página Thymeleaf renderizada no servidor
3. *(opcional, se sobrar tempo)* terminal com a saída de `./mvnw verify` já pronta

> "A página em Thymeleaf é a demonstração de Spring MVC renderizado no servidor. A interface
> administrativa de verdade é o dashboard Angular."

---

## 4:30 – 5:00 · Fechamento

Slide 10.

> "Fecho pelo que ainda não está pronto: o modelo de risco é treinado em dados sintéticos, há três
> pendências diagnosticadas e registradas, e a navegação usa Expo Router em vez de React Navigation
> — medi, e nessa versão o Expo Router não embrulha o React Navigation. Está tudo declarado no
> documento."

---

## Erros que custam tempo

| Risco | Prevenção |
|---|---|
| Login ao vivo no celular | Deixe a sessão já aberta |
| Backend não subiu | Confira `localhost:8080/api/v1/ping` **antes** de gravar |
| Dashboard sem dados | Confira que o banco tem seed: `make reset` e suba o backend |
| CORS bloqueando o dashboard | O perfil `dev` já libera `localhost:4200`; confirme que subiu com `-Dspring-boot.run.profiles=dev` |
| Passar de 5 min | Cronometre a demo separada. Se estourar, corte os slides 5–7, nunca a demo |
