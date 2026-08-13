package com.nomara.modi.server.domain.archive.client;

import java.util.List;

/** 아카이브 자료 등록(S-25-C) AI 자동 태깅. 실패 시 호출부가 빈 리스트로 폴백한다(specs/OPEN.md 확정). */
public interface AiTaggingClient {

  List<String> suggestTags(String bodyText);
}
