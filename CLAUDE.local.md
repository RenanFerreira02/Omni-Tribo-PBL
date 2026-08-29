# CLAUDE.local.md

Preferências e ambiente da minha máquina. Arquivo privado (gitignored) — o que vale para o time
fica no `CLAUDE.md`.

## Container runtime: podman, não Docker Desktop

Não há Docker Desktop aqui. Testcontainers precisa do socket do podman **exportado antes** de
qualquer `./mvnw verify`, senão a suíte falha inteira ao subir o PostgreSQL+PostGIS:

```bash
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock
# se o socket não existir: systemctl --user start podman.socket
```

Consequência no `/verificar`: o passo `docker compose ps` **não tem alvo nesta máquina** quando eu
não subi o banco com `make up` — a suíte sobe o banco por Testcontainers. Ausência de container de
longa duração ali não é vermelho; está registrado em `docs/qualidade/verificacao-2026-08-15.md`.

## JDK

`JAVA_HOME` vem do SDKMAN (`~/.sdkman/candidates/java/current`). O `java` do PATH do Fedora é
JRE-only — Maven não roda com ele. O hook `formatar-java.sh` já resolve isso sozinho; um `./mvnw`
disparado fora do hook, não.
