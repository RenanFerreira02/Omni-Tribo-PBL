# DER — modelo relacional Oracle

Modelo físico implantado por [`sql/01_tabelas.sql`](../sql/01_tabelas.sql): 12 tabelas, todas com o
prefixo `OT_`. O significado de cada coluna e a origem de cada tabela no PostgreSQL do projeto estão
no [dicionário de dados](DICIONARIO.md).

## Diagrama

```mermaid
erDiagram
    OT_TRIBO ||--o{ OT_USUARIO : "reune"
    OT_TRIBO ||--o{ OT_PARCEIRO : "abriga"
    OT_TRIBO ||--o{ OT_RELATORIO_TRIBO : "resumida em"
    OT_USUARIO ||--o| OT_CARTEIRA : "possui"
    OT_USUARIO ||--o{ OT_MISSAO : "cria"
    OT_USUARIO |o--o{ OT_MISSAO : "executa"
    OT_USUARIO ||--o{ OT_CHECKIN : "registra"
    OT_USUARIO ||--o{ OT_RESGATE : "faz"
    OT_USUARIO |o--o{ OT_ALERTA : "recebe"
    OT_USUARIO ||--o{ OT_RELATORIO_TRIBO : "aparece em"
    OT_CARTEIRA ||--o{ OT_LANCAMENTO : "movimentada por"
    OT_LANCAMENTO ||--o| OT_RESGATE : "origina"
    OT_MISSAO ||--o{ OT_MISSAO_EVENTO : "tem trilha"
    OT_MISSAO ||..o{ OT_CHECKIN : "comprovada por"
    OT_MISSAO ||..o{ OT_LANCAMENTO : "financiada e paga por"
    OT_PARCEIRO ||--o{ OT_BENEFICIO : "oferece"
    OT_BENEFICIO ||--o{ OT_RESGATE : "resgatado em"

    OT_TRIBO {
        VARCHAR2 id PK
        VARCHAR2 nome
        VARCHAR2 bairro
        TIMESTAMP_TZ criada_em
    }
    OT_USUARIO {
        VARCHAR2 id PK
        VARCHAR2 nome
        VARCHAR2 handle UK
        VARCHAR2 tribo_id FK
        NUMBER xp
        NUMBER nivel
        VARCHAR2 papel
        VARCHAR2 status
        TIMESTAMP_TZ criado_em
    }
    OT_CARTEIRA {
        VARCHAR2 id PK
        VARCHAR2 usuario_id FK,UK
        NUMBER saldo_tokens
    }
    OT_LANCAMENTO {
        VARCHAR2 id PK
        VARCHAR2 carteira_id FK
        VARCHAR2 sinal
        VARCHAR2 motivo
        NUMBER valor_tokens
        VARCHAR2 missao_id
        VARCHAR2 contraparte_carteira_id FK
        VARCHAR2 chave_idempotencia UK
        NUMBER saldo_apos_tokens
        VARCHAR2 mensagem
        TIMESTAMP_TZ criado_em
    }
    OT_MISSAO {
        VARCHAR2 id PK
        VARCHAR2 criador_id FK
        VARCHAR2 executor_id FK
        VARCHAR2 categoria
        VARCHAR2 titulo
        VARCHAR2 status
        NUMBER xp_recompensa
        NUMBER tokens_recompensa
        NUMBER pote_tokens
        VARCHAR2 fonte_pote
        VARCHAR2 complexidade
        VARCHAR2 bairro
        VARCHAR2 cidade
        VARCHAR2 uf
        TIMESTAMP_TZ janela_inicio
        TIMESTAMP_TZ janela_fim
        TIMESTAMP_TZ criada_em
        TIMESTAMP_TZ aceita_em
        TIMESTAMP_TZ concluida_em
        TIMESTAMP_TZ estado_desde
    }
    OT_MISSAO_EVENTO {
        VARCHAR2 id PK
        VARCHAR2 missao_id FK
        VARCHAR2 tipo
        VARCHAR2 ator_id
        VARCHAR2 de_status
        VARCHAR2 para_status
        TIMESTAMP_TZ criado_em
    }
    OT_CHECKIN {
        VARCHAR2 id PK
        VARCHAR2 missao_id
        VARCHAR2 usuario_id FK
        NUMBER acuracia_m
        NUMBER distancia_alvo_m
        VARCHAR2 metodo
        NUMBER mock_detectado
        NUMBER velocidade_implicita_kmh
        NUMBER valido
        VARCHAR2 codigo_rejeicao
        TIMESTAMP_TZ criado_em
    }
    OT_PARCEIRO {
        VARCHAR2 id PK
        VARCHAR2 nome
        VARCHAR2 tribo_id FK
        VARCHAR2 bairro
        VARCHAR2 cidade
        VARCHAR2 uf
        NUMBER ativo
        TIMESTAMP_TZ criado_em
    }
    OT_BENEFICIO {
        VARCHAR2 id PK
        VARCHAR2 parceiro_id FK
        VARCHAR2 titulo
        VARCHAR2 descricao
        NUMBER custo_tokens
        VARCHAR2 tipo
        NUMBER ativo
        TIMESTAMP_TZ criado_em
    }
    OT_RESGATE {
        VARCHAR2 id PK,FK
        VARCHAR2 usuario_id FK
        VARCHAR2 beneficio_id FK
        NUMBER custo_tokens
        VARCHAR2 codigo_retirada UK
        VARCHAR2 status
        TIMESTAMP_TZ criado_em
        TIMESTAMP_TZ utilizado_em
    }
    OT_ALERTA {
        VARCHAR2 id PK
        VARCHAR2 usuario_id FK
        VARCHAR2 tipo
        VARCHAR2 titulo
        VARCHAR2 corpo
        VARCHAR2 missao_id
        NUMBER prioridade
        NUMBER lido
        TIMESTAMP_TZ criado_em
    }
    OT_RELATORIO_TRIBO {
        VARCHAR2 tribo_id PK,FK
        VARCHAR2 usuario_id PK,FK
        VARCHAR2 handle
        NUMBER missoes_concluidas
        NUMBER tokens_ganhos
        NUMBER tokens_financiados
        NUMBER tokens_resgatados
        NUMBER saldo_tokens
        TIMESTAMP_TZ gerado_em
    }
```

## Como ler

**Linha contínua** é chave estrangeira declarada no banco. **Linha pontilhada** é referência por id
sem `FOREIGN KEY`, e são três, todas deliberadas:

| Referência | Por que não tem FK |
|---|---|
| `OT_LANCAMENTO.MISSAO_ID` → missão | A carteira referencia a missão por id puro para não depender do módulo de missões. É a mesma decisão do sistema de origem, onde `carteira` e `missoes` são módulos separados. |
| `OT_CHECKIN.MISSAO_ID` → missão | Mesmo motivo: a geolocalização registra a leitura sem depender da missão. |
| `OT_ALERTA.MISSAO_ID` → missão | O alerta sobrevive à missão a que se refere. |

`OT_MISSAO_EVENTO.ATOR_ID` também não tem FK: fica **nulo** quando quem agiu foi o sistema (a
varredura por prazo), e não uma pessoa.

## Cardinalidades que carregam regra de negócio

- **Usuário 1 — 0..1 Carteira.** A conta de sistema existe sem carteira. É o caso que
  `PRC_OT_RESGATAR_BENEFICIO` trata com o erro `-20032`.
- **Lançamento 1 — 0..1 Resgate, com o mesmo id.** `OT_RESGATE.ID` é chave primária e chave
  estrangeira para `OT_LANCAMENTO.ID`. O resgate e o débito nascem na mesma transação, e o modelo
  torna impossível existir resgate sem o lançamento que o pagou.
- **Usuário 0..1 — N Missão (executor).** Missão aberta ainda não tem executor.
- **Tribo 1 — N Usuário, opcional do lado do usuário.** O apoiador do bairro e a conta de sistema
  não pertencem a tribo nenhuma.

## O que não está no diagrama, de propósito

| Ficou no PostgreSQL | Motivo |
|---|---|
| Coordenadas (`GEOGRAPHY`) de missão, check-in e parceiro | O geoespacial é do PostGIS. Aqui ficam bairro, cidade e a distância já calculada. |
| E-mail e hash de senha do usuário | Esta camada é analítica; credencial não tem uso nela. |
| Saldo e lançamentos em reais | BRL está fora do ciclo de missões (ADR 0009). |
| Consentimento, refresh token, dispositivo, auditoria, outbox | Infraestrutura de sessão e de mensageria, sem papel nas rotinas PL/SQL. |
