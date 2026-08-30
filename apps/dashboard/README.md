# apps/dashboard — Painel administrativo (Angular)

Painel web da Parte 3 do PBL. Consome a mesma API que o app mobile: `services/api`, Spring Boot.

**Angular 22.1** · standalone components · zoneless (signals) · CSS próprio, sem biblioteca de UI.

## Rodar

Precisa de **duas** coisas de pé, nesta ordem. O painel sozinho abre e não faz nada.

```bash
# 1. Banco (na RAIZ do repositório)
make up

# 2. Backend, perfil dev — é o perfil que libera http://localhost:4200 no CORS
cd services/api && ./mvnw spring-boot:run -Dspring-boot.run.profiles=dev

# 3. Painel (noutro terminal)
cd apps/dashboard && npm install   # primeira vez
npm start                          # http://localhost:4200
```

Clone novo exige `bash tools/gerar-chaves-dev.sh` antes do passo 2 — sem os PEM nenhum contexto
Spring sobe.

Entre com qualquer usuário do seed (`docs/INFRA.md`). Para ver a aba **/admin** com dados é preciso
papel ADMIN: `admin@omnitribo.dev` / `Senha@123`. Uma conta `USUARIO` chega à tela e recebe **403**
do servidor — o painel diz isso em vez de "erro ao carregar", porque não é falha.

## Rotas

| Rota | Protegida | O que mostra |
|---|---|---|
| `/login` | não | Formulário de entrada |
| `/home` | sim (`authGuard`) | Perfil da sessão e a lista de tribos (`GET /tribos`) |
| `/admin` | sim (`authGuard`) | Gestão de pontos de custódia: listagem + cadastro. Abaixo, o funil da entrega falida (`GET /admin/impacto`) |

`/` redireciona para `/home`; qualquer rota desconhecida também.

## Onde está o quê

| Arquivo | Papel |
|---|---|
| `src/app/core/auth.service.ts` | Login, logout, perfil, guarda do token |
| `src/app/core/auth.interceptor.ts` | Anexa `Authorization: Bearer …` a toda chamada |
| `src/app/core/auth.guard.ts` | Manda para `/login` quem não está autenticado |
| `src/app/core/api.config.ts` | `API_BASE_URL` — o único lugar com o endereço do backend |

## A validação do formulário NÃO substitui a do servidor

O cadastro de ponto de custódia (`/admin`) valida no cliente: obrigatoriedade, tamanho, o padrão
`[A-Z0-9-]+` do código, a faixa de latitude e longitude e a capacidade positiva. **Isso é
conveniência de digitação, e nada mais.**

Quem decide é o backend. `CadastrarPontoCustodiaRequest` carrega as mesmas restrições em Bean
Validation; `PontoCustodiaService.cadastrar` verifica o que só o servidor pode saber — se o código já
existe e se a tribo existe —, e `uk_ponto_custodia_codigo` no banco é a barreira final. Qualquer
linha do `validar()` deste projeto é contornável pelo DevTools em dois segundos; nenhuma das do
servidor é.

A consequência prática, e é ela que orienta a manutenção: **se este espelho divergir do DTO do
servidor, o sintoma correto é um 400 que a tela exibe campo a campo — não uma regra afrouxada aqui
para o formulário "passar".** Nada do backend foi relaxado para esta tela funcionar.

Dois campos do servidor **não** existem no formulário, de propósito: `ocupacao` e `ativo`. Todo ponto
nasce vazio e ativo. Ocupação é movida só pelo webhook de entrega falida e pela baixa da missão, sob
`SELECT ... FOR UPDATE` — aceitá-la num formulário abriria por fora do lock a corrida que ele existe
para fechar.

## O token fica em memória, e isso tem um custo

`AuthService` guarda `accessToken` e `refreshToken` em **campos privados de um serviço**. Nada vai
para `localStorage` ou `sessionStorage`.

**A consequência, dita por extenso: recarregar a aba (F5) encerra a sessão e devolve o usuário para
`/login`.** Não é bug e não há contorno implementado. Fechar a aba faz o mesmo.

A escolha é deliberada e o motivo é assimétrico. O app mobile guarda o refresh em
`expo-secure-store` — Keychain no iOS, Keystore no Android —, e **o navegador não tem equivalente**:
`localStorage` é texto claro legível por qualquer script que execute nesta origem. Um XSS no painel
levaria junto o refresh de **30 dias**, não só o access de 15 minutos, e o refresh é o que permite
reemitir acesso sem senha. Trocar perda de sessão no F5 por essa exposição não se paga num painel
administrativo, que é justamente onde as contas ADMIN entram.

O que isso **não** resolve: um XSS ainda alcança o token enquanto a aba está aberta, porque ele está
no heap do JS. Memória reduz a janela e o alcance — não elimina a classe de ataque. A defesa real
contra XSS é a CSP e o escape de saída, não o lugar onde o token dorme.

Caminho conhecido para persistir sem `localStorage`, caso a decisão mude: refresh em cookie
`HttpOnly` + `Secure` + `SameSite=Strict`, emitido pelo servidor. Exige mudança no backend (hoje o
refresh volta no corpo do JSON) e traz CSRF de volta ao escopo, que o `csrf disable` atual dispensa
justamente por não haver cookie de sessão. Não está feito.

## Sintaxe usada, e por que ela é essa

O enunciado do PBL pede `*ngIf` / `*ngFor` e `[(ngModel)]`, e é isso que o código usa — mesmo que o
Angular 22 prefira `@if` / `@for`. Duas armadilhas de componente **standalone**, ambas com sintoma
enganoso:

- **`*ngIf` e `*ngFor` exigem `CommonModule`** nos `imports` do próprio componente. Sem ele não há
  erro em execução: a diretiva é lida como atributo desconhecido e o bloco **nunca renderiza**.
- **`[(ngModel)]` exige `FormsModule`**, também por componente. Sem ele o erro de template diz que
  `ngModel` não é propriedade de `input` — e não menciona formulário nem módulo.

Em projeto com `NgModule` isso ficava resolvido uma vez no módulo; em standalone é por componente.

`*ngIf` e `*ngFor` estão marcados como `@deprecated 20.0` no Angular 22 (a recomendação é `@if` /
`@for`), mas seguem funcionando — o build passa sem aviso e a renderização está verificada.

## Não há zone.js, e a razão foi medida

O projeto **nasceu** com `ng new --zoneless=false`: zone.js nos polyfills e
`provideZoneChangeDetection({eventCoalescing: true})` nos providers. Não funcionou, e o modo como
não funcionou é a parte que interessa.

O sintoma: depois do login, `/home` ficava em **"Carregando tribos…" para sempre**. A requisição
respondia **200**, o console ficava **limpo**, e o estado do componente estava **correto** —
`carregando: false`, quatro tribos carregadas. Só o DOM estava parado no quadro anterior. Nada na
tela dizia o que havia de errado.

Medido no navegador, com o componente inspecionado pelo `window.ng`: forçar `ng.applyChanges()`
renderizava as quatro linhas na hora. Logo, `*ngIf` e `*ngFor` estavam corretos — o que não rodava
era change detection. E não rodava para **nada**: mutar um campo dentro de `setTimeout` ou de
`.then()` também não re-renderizava. NgZone não estava dirigindo CD, apesar de configurado.

Duas descobertas pelo caminho, ambas específicas do Angular 22:

1. `provideHttpClient()` passou a usar **`FetchBackend`** por padrão — é por isso que existe agora um
   `withXhr()` para voltar atrás.
2. zone.js **não patcha `fetch`** por padrão: `zone-patch-fetch` é um plugin opt-in separado.

Aplicar `zone-patch-fetch` fez `fetch` ficar patchado de fato — **e o DOM continuou parado**. Ou
seja: nem essa era a causa, e manter o plugin teria sido cargo cult.

A saída não foi reanimar o zone.js e sim depender de algo que funciona nos dois modos. **Estado
escrito em callback assíncrono vive em `signal()`**, e escrever num signal notifica o agendador de
change detection do Angular diretamente, com ou sem zona. zone.js foi removido das dependências e
dos polyfills por ser peso morto — o bundle caiu de 348,88 kB para 310,21 kB.

Os campos ligados a `[(ngModel)]` **continuam campos comuns**, e de propósito: quem os altera é o
usuário digitando, e um event listener de template agenda CD por conta própria. Signal ali só
adicionaria cerimônia. A regra que o código segue é essa: *signal quando quem escreve é um callback;
campo comum quando quem escreve é o usuário.*

## Comandos

```bash
npm start          # ng serve em http://localhost:4200
npm run build      # bundle de produção em dist/
npm run watch      # build incremental
```

Não há suíte de testes: o scaffold foi gerado com `--skip-tests`. O critério de aceite desta entrega
é o fluxo de login executado contra o backend real.
