package com.nomara.modi.server;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.ResponseEntity;

/**
 * springdoc-openapi가 자동 생성하는 /v3/api-docs를 docs/api/openapi.json으로 내보낸다. CLAUDE.md 문서 자동화 하네스:
 * 컨트롤러가 바뀌면 이 테스트가 파일도 함께 최신화하므로, server-ci 워크플로가 이 파일의 git diff를 검사해 커밋 누락(드리프트)을 잡아낸다.
 */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class OpenApiExportTest {

  @Autowired private TestRestTemplate restTemplate;

  @Test
  void exportsOpenApiSpec() throws IOException {
    ResponseEntity<String> response = restTemplate.getForEntity("/v3/api-docs", String.class);
    assertThat(response.getStatusCode().is2xxSuccessful()).isTrue();

    ObjectMapper mapper = new ObjectMapper();
    ObjectNode json = (ObjectNode) mapper.readTree(response.getBody());
    // 테스트마다 랜덤 포트가 박히는 서버 URL은 문서로서 의미가 없고 CI drift 체크만 방해하므로 제외.
    json.remove("servers");
    String pretty = mapper.writerWithDefaultPrettyPrinter().writeValueAsString(json);

    Path target = Path.of("..", "docs", "api", "openapi.json");
    Files.createDirectories(target.getParent());
    Files.writeString(target, pretty + System.lineSeparator());
  }
}
