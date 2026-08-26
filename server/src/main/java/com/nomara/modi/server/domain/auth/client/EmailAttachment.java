package com.nomara.modi.server.domain.auth.client;

/**
 * 메일 첨부 한 건. 피드백 스크린샷(#70)이 첫 사용처다 — 스크린샷은 버킷에서 공개로 열지 않으므로(개인정보가 담길 수 있다) 링크가 아니라 바이트를 그대로 실어 보낸다.
 */
public record EmailAttachment(String filename, byte[] content, String contentType) {}
