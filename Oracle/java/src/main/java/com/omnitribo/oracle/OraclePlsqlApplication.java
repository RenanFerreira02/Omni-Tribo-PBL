package com.omnitribo.oracle;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Aplicação de demonstração da Fase 6: o caminho REST → Java → JDBC → Oracle.
 *
 * <p>É independente de {@code services/api} de propósito. O sistema continua sendo PostgreSQL +
 * PostGIS; esta aplicação existe para mostrar o back-end Java acionando as rotinas PL/SQL, sem
 * mexer nas regras do projeto principal (Flyway como única fonte de schema, ArchUnit, gates).
 */
@SpringBootApplication
public class OraclePlsqlApplication {

  public static void main(String[] args) {
    SpringApplication.run(OraclePlsqlApplication.class, args);
  }
}
