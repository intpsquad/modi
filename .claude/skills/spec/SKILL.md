---
name: spec
description: 새 기능의 스펙을 specs/ 아래에 작성한다. 추측하지 말고 AskUserQuestion으로 애매한 점을 사용자에게 물어 채운다. "/spec <기능명>"으로 호출.
---
새 기능 스펙을 `specs/NNNN-<기능명>.md`로 작성한다.
1. 기존 `specs/`(design, architecture, data-model, navigation)를 먼저 읽어 정합성을 맞춘다.
2. 다음 형식으로 작성: 목적 / 하지 않을 것 / 진입·화면(S-xx 연결) / 액션·전이 / 데이터(엔티티 연결) / 성공(인수) 기준 / 상태(로딩·빈·에러) / 엣지케이스.
3. 명세에 없어 확정이 필요한 부분은 **추측하지 말고 AskUserQuestion으로 질문**한다.
4. 스펙 확정 후에만 구현으로 넘어간다.
