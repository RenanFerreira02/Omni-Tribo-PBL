#!/usr/bin/env bash
# Executa um script SQL de Oracle/sql no Oracle configurado em Oracle/.env.
#
# Uso:
#   bash Oracle/executar.sh instalar.sql
#   bash Oracle/executar.sh 07_testes.sql
#   bash Oracle/executar.sh 06_consultas_de_uso.sql > Oracle/evidencias/consultas.txt
#
# Precisa do SQLcl (https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/) e de um JDK.
# Aponte SQLCL para o executável se ele não estiver no PATH:
#   SQLCL=~/.local/share/sqlcl/bin/sql bash Oracle/executar.sh instalar.sql
#
# A senha NÃO vai na linha de comando: argumento de processo aparece no `ps` de qualquer usuário
# da máquina. O `connect` é enviado pela entrada padrão.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${1:?informe o script, por exemplo: instalar.sql}"

if [[ -f "$aqui/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$aqui/.env"
  set +a
fi

: "${ORACLE_URL:?defina ORACLE_URL (ver Oracle/.env.example)}"
: "${ORACLE_USER:?defina ORACLE_USER (ver Oracle/.env.example)}"
: "${ORACLE_PASSWORD:?defina ORACLE_PASSWORD (ver Oracle/.env.example)}"

sqlcl="${SQLCL:-$(command -v sql || true)}"
if [[ -z "$sqlcl" || ! -x "$sqlcl" ]]; then
  echo "SQLcl não encontrado. Instale-o ou aponte a variável SQLCL para o executável." >&2
  exit 1
fi

# A URL do .env é a do JDBC (a mesma que o Java usa); o SQLcl quer só o que vem depois do '@'.
destino="${ORACLE_URL#jdbc:oracle:thin:@}"

# Os scripts usam @@ (caminho relativo ao próprio script), então rodam a partir de Oracle/sql.
cd "$aqui/sql"

# -S: sem banner. UTF-8 explícito: os scripts têm acento, e a codificação padrão da JVM varia.
JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8 ${JAVA_TOOL_OPTIONS:-}" "$sqlcl" -S /nolog <<SQL
WHENEVER SQLERROR EXIT FAILURE
SET SQLFORMAT default
connect ${ORACLE_USER}/"${ORACLE_PASSWORD}"@${destino}
@${script}
exit
SQL
