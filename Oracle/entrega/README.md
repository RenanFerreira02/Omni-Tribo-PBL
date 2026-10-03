# Entrega — PBL Fase 6

Gera o que a plataforma pede: o **documento em PDF**, a **apresentação em PDF** (10 slides) e o
**ZIP** com os dois, os links e os fontes desta fase.

| Arquivo | Papel |
|---|---|
| [`gerar.mjs`](gerar.mjs) | Monta os dois PDFs e o ZIP |
| [`slides.html`](slides.html) | Os 10 slides |
| [`ROTEIRO-VIDEO.md`](ROTEIRO-VIDEO.md) | Roteiro do vídeo de 5 minutos, com a demonstração |
| `imagens/` | Captura do dashboard usada no documento e nos slides |
| `saida/` | O que é gerado (não versionado) |

O documento em PDF é montado a partir de [`../docs/`](../docs/): a entrega, o DER, a explicação
do PL/SQL, o dicionário de dados e as evidências. Para mudar o texto, edite o Markdown de lá.

## Passo a passo

1. **Foto.** Salve a foto do integrante como `Oracle/entrega/foto.jpg`. Ela entra no slide 1 e não é
   versionada.
2. **Vídeo.** Grave seguindo o [roteiro](ROTEIRO-VIDEO.md) e publique no YouTube como não listado.
3. **Gerar**, já com o link:

   ```bash
   cd Oracle/entrega
   npm install                                   # primeira vez
   VIDEO_URL="https://youtu.be/SEU-VIDEO" node gerar.mjs
   ```

4. **Enviar** `saida/Omni-Tribo-Fase6-RM555833.zip` na plataforma FIAP ON.

O script avisa quando falta a foto ou o link, e mesmo assim gera os arquivos — com o link marcado
como pendente. Não envie um pacote gerado com aviso.

## O que vai no ZIP

```
Omni-Tribo-Fase6-RM555833/
  Omni-Tribo - Fase 6 - Documentacao.pdf
  Omni-Tribo - Fase 6 - Slides.pdf
  LINKS.txt                  repositório e vídeo
  codigo/Oracle/             SQL, PL/SQL, Java e evidências desta fase
```

O arquivo de credencial (`.env`) nunca entra: o script confere antes de compactar e aborta se
encontrar um.

O projeto completo (app mobile, API e dashboard) vai pelo link do repositório. **Os links do PDF
apontam para a branch `main` do GitHub**, então o trabalho desta fase precisa estar publicado lá
antes da entrega.
