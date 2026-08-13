package com.nomara.modi.server;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 실제 Postgres에 Flyway로 V1__init.sql을 적용한 뒤 ddl-auto=validate로 Hibernate가 도메인 엔티티 매핑을 검증하게 한다. 엔티티가
 * 마이그레이션과 정확히 일치한다는 것을 증명하는 유일한 테스트 — 다른 테스트는 계속 H2(test/resources/application.yml, flyway 비활성)로
 * 빠르게 돈다.
 */
@Testcontainers
@SpringBootTest
class SchemaValidationTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @DynamicPropertySource
  static void schemaValidationProperties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
  }

  @Test
  void entitiesMatchMigratedSchema() {}
}
