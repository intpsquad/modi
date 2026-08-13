import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/env.dart';
import '../auth/authenticated_http_client.dart';

/// 아카이브 탭(S-25) 폴더 API 클라이언트 — specs/0010-아카이브-탭.md.
/// 인증 헤더와 401 갱신 재시도는 [AuthenticatedHttpClient]가 담당한다.
class ArchiveApi {
  ArchiveApi({
    this.baseUrl = Env.apiBaseUrl,
    AuthenticatedHttpClient? client,
    http.Client? uploadClient,
  }) : _client = client ?? appAuthenticatedHttpClient,
       _uploadClient = uploadClient ?? http.Client();

  final String baseUrl;
  final AuthenticatedHttpClient _client;
  final http.Client _uploadClient;

  Future<List<ArchiveFolder>> fetchFolders(String idToken, int roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/archive/folders'),
      idToken: idToken,
    );
    _checkOk(response, '폴더 목록 조회 실패');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ArchiveFolder.fromJson)
        .toList();
  }

  Future<ArchiveFolder> createFolder(
    String idToken,
    int roomId,
    String name,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/archive/folders'),
      idToken: idToken,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode != 201) {
      throw StateError('폴더 생성 실패: ${response.statusCode} ${response.body}');
    }
    return ArchiveFolder.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ArchiveFolder> renameFolder(
    String idToken,
    int roomId,
    int folderId,
    String name,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/archive/folders/$folderId'),
      idToken: idToken,
      body: jsonEncode({'name': name}),
    );
    _checkOk(response, '폴더 이름 수정 실패');
    return ArchiveFolder.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteFolder(String idToken, int roomId, int folderId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/rooms/$roomId/archive/folders/$folderId'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('폴더 삭제 실패: ${response.statusCode} ${response.body}');
    }
  }

  Future<ArchiveFolderItems> fetchFolderItems(
    String idToken,
    int roomId,
    int folderId,
  ) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/archive/folders/$folderId/items'),
      idToken: idToken,
    );
    _checkOk(response, '항목 목록 조회 실패');
    return ArchiveFolderItems.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ArchiveItemDetail> fetchItemDetail(
    String idToken,
    int roomId,
    int itemId,
  ) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId'),
      idToken: idToken,
    );
    _checkOk(response, '자료 조회 실패');
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// AI 요약을 지금 만든다(S-25-B 「AI 요약 만들기」).
  ///
  /// 텍스트로 등록한 자료는 자동 요약을 하지 않는다 — 필요한 사람이 이걸 부른다.
  /// 요약이 이미 있으면 서버가 400 으로 거절한다(다시 만들 이유가 없다).
  Future<ArchiveItemDetail> summarizeItem(
    String idToken,
    int roomId,
    int itemId,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/summary'),
      idToken: idToken,
    );
    _checkOk(response, 'AI 요약 실패');
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ArchiveItemDetail> setItemPinned(
    String idToken,
    int roomId,
    int itemId,
    bool pinned,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/pin'),
      idToken: idToken,
      body: jsonEncode({'pinned': pinned}),
    );
    _checkOk(response, '핀 고정 변경 실패');
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ArchiveItemDetail> setItemLiked(
    String idToken,
    int roomId,
    int itemId,
    bool liked,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/like'),
      idToken: idToken,
      body: jsonEncode({'liked': liked}),
    );
    _checkOk(response, '좋아요 변경 실패');
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ArchiveItemDetail> moveItemToFolder(
    String idToken,
    int roomId,
    int itemId,
    int folderId,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/folder'),
      idToken: idToken,
      body: jsonEncode({'folderId': folderId}),
    );
    _checkOk(response, '폴더 이동 실패');
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// 메모 편집(S-25-B, 2026-08-06). null/빈 값이면 메모를 지운다.
  Future<ArchiveItemDetail> updateItemMemo(
    String idToken,
    int roomId,
    int itemId,
    String? memo,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/memo'),
      idToken: idToken,
      body: jsonEncode({'memo': memo}),
    );
    _checkOk(response, '메모 수정 실패');
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// 링크 편집(S-25-B, 2026-08-06) — 링크형 자료만 대상. 새 URL로 비동기 재분석이 다시 돈다.
  /// 응답은 항상 PENDING 상태다(등록과 같은 설계) — `CrawlStatusBadge`가 "분석 중"을 보여준다.
  Future<ArchiveItemDetail> updateItemUrl(
    String idToken,
    int roomId,
    int itemId,
    String url,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/url'),
      idToken: idToken,
      body: jsonEncode({'url': url}),
    );
    _checkOk(response, '링크 수정 실패');
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ArchiveItemDetail> updateItemTags(
    String idToken,
    int roomId,
    int itemId,
    List<String> tags,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/tags'),
      idToken: idToken,
      body: jsonEncode({'tags': tags}),
    );
    _checkOk(response, '태그 수정 실패');
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteItem(String idToken, int roomId, int itemId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('자료 삭제 실패: ${response.statusCode} ${response.body}');
    }
  }

  Future<ArchiveItemDetail> createItem(
    String idToken,
    int roomId,
    int folderId, {
    String? url,
    String? text,
    String? memo,
    String? imageUrl,
    String? title,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/archive/folders/$folderId/items'),
      idToken: idToken,
      body: jsonEncode({
        'url': url,
        'text': text,
        'memo': memo,
        'imageUrl': imageUrl,
        'title': title,
      }),
    );
    if (response.statusCode != 201) {
      throw StateError('자료 등록 실패: ${response.statusCode} ${response.body}');
    }
    return ArchiveItemDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// 폴더 직접 업로드 이미지 자료(V28) — presigned PUT 2단계 업로드.
  /// [TodosApi.uploadTodoImage]와 완전히 같은 모양.
  Future<String> uploadArchiveImage(
    String idToken,
    int roomId, {
    required List<int> bytes,
  }) async {
    final urlResponse = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/image/upload-url'),
      idToken: idToken,
    );
    _checkOk(urlResponse, '이미지 업로드 준비');
    final body = jsonDecode(urlResponse.body) as Map<String, dynamic>;
    final uploadUrl = body['uploadUrl'] as String;
    final publicUrl = body['publicUrl'] as String;

    final uploadResponse = await _uploadClient.put(
      Uri.parse(uploadUrl),
      body: bytes,
    );
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw StateError('이미지 업로드 실패 (${uploadResponse.statusCode})');
    }
    return publicUrl;
  }

  /// 자료 댓글 목록 — 오래된 순(서버가 ASC로 내려준다, 채팅형 UI와 맞춤). S-25-B 댓글 시트.
  Future<List<ArchiveComment>> fetchComments(
    String idToken,
    int roomId,
    int itemId,
  ) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/comments'),
      idToken: idToken,
    );
    _checkOk(response, '댓글 목록 조회 실패');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ArchiveComment.fromJson)
        .toList();
  }

  /// 댓글 작성(201) — 본문 500자 제한은 서버가 검증한다. 방금 쓴 댓글을 돌려준다.
  Future<ArchiveComment> createComment(
    String idToken,
    int roomId,
    int itemId,
    String body,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/archive/items/$itemId/comments'),
      idToken: idToken,
      body: jsonEncode({'body': body}),
    );
    if (response.statusCode != 201) {
      throw StateError('댓글 등록 실패: ${response.statusCode} ${response.body}');
    }
    return ArchiveComment.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// 댓글 수정(200) — 작성자 본인만(서버가 403). 수정된 댓글을 돌려준다.
  Future<ArchiveComment> updateComment(
    String idToken,
    int roomId,
    int itemId,
    int commentId,
    String body,
  ) async {
    final response = await _client.patch(
      Uri.parse(
        '$baseUrl/rooms/$roomId/archive/items/$itemId/comments/$commentId',
      ),
      idToken: idToken,
      body: jsonEncode({'body': body}),
    );
    _checkOk(response, '댓글 수정 실패');
    return ArchiveComment.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// 댓글 삭제 — 작성자 본인만(서버가 403).
  Future<void> deleteComment(
    String idToken,
    int roomId,
    int itemId,
    int commentId,
  ) async {
    final response = await _client.delete(
      Uri.parse(
        '$baseUrl/rooms/$roomId/archive/items/$itemId/comments/$commentId',
      ),
      idToken: idToken,
    );
    _checkOk(response, '댓글 삭제 실패');
  }

  /// 내 프로필(닉네임·사진) — 댓글 입력바의 내 아바타용. `GET /me/profile`을 아바타에 필요한
  /// 모양([ArchiveItemCreator])으로만 얇게 매핑한다(설정 화면의 `UserProfile`을 import 하지
  /// 않는 이유는 [ArchiveItemCreator] 주석과 같다 — 기능 간 결합 회피).
  Future<ArchiveItemCreator> fetchMyBrief(String idToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/me/profile'),
      idToken: idToken,
    );
    _checkOk(response, '내 프로필 조회 실패');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ArchiveItemCreator(
      userId: json['userId'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      profileImage: json['profileImage'] as String?,
    );
  }

  /// 이미지 탭 피드 — 방의 투두 첨부 사진 전체(폴더 무관, 2026-08-09 기획).
  ///
  /// ⚠️ **서버 미구현 — 제안 계약**(`docs/backend/todo-image-archive-handoff.md`).
  /// 서버가 배포되기 전에는 404/미구현 응답이 오므로 **빈 목록으로 폴백**해 화면은
  /// 기존 "준비 중" 빈 상태를 그대로 보여준다.
  Future<List<ArchiveTodoImage>> fetchTodoImages(
    String idToken,
    int roomId,
  ) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/archive/todo-images'),
      idToken: idToken,
    );
    if (response.statusCode != 200) return const [];
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ArchiveTodoImage.fromJson)
        .toList();
  }

  /// 이미지 핀 토글 — 제안 계약(위와 동일). 실패는 호출부가 롤백한다.
  Future<void> setTodoImagePinned(
    String idToken,
    int roomId,
    int imageId,
    bool pinned,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/archive/todo-images/$imageId/pin'),
      idToken: idToken,
      body: jsonEncode({'pinned': pinned}),
    );
    _checkOk(response, '이미지 핀 변경 실패');
  }

  void _checkOk(http.Response response, String message) {
    if (response.statusCode != 200) {
      throw StateError('$message: ${response.statusCode} ${response.body}');
    }
  }
}

class ArchiveFolder {
  ArchiveFolder({
    required this.id,
    required this.name,
    required this.itemCount,
    this.thumbnail,
  });

  final int id;
  final String name;
  final int itemCount;

  /// 폴더 대표 썸네일(폴더 내 대표/최신 항목 이미지) — 서버가 목록 응답에 내려준다.
  /// 미반영/빈 폴더면 null → 화면은 플레이스홀더로 폴백.
  final String? thumbnail;

  factory ArchiveFolder.fromJson(Map<String, dynamic> json) {
    return ArchiveFolder(
      id: json['id'] as int,
      name: json['name'] as String,
      itemCount: json['itemCount'] as int,
      thumbnail: json['thumbnail'] as String?,
    );
  }
}

class ArchiveFolderItems {
  ArchiveFolderItems({
    required this.folderId,
    required this.folderName,
    required this.items,
  });

  final int folderId;
  final String folderName;
  final List<ArchiveItem> items;

  factory ArchiveFolderItems.fromJson(Map<String, dynamic> json) {
    return ArchiveFolderItems(
      folderId: json['folderId'] as int,
      folderName: json['folderName'] as String,
      items: (json['items'] as List)
          .cast<Map<String, dynamic>>()
          .map(ArchiveItem.fromJson)
          .toList(),
    );
  }
}

class ArchiveItem {
  ArchiveItem({
    required this.id,
    required this.title,
    required this.url,
    required this.source,
    required this.thumbnail,
    required this.imageUrl,
    required this.pinned,
    required this.createdAt,
    required this.tags,
    required this.likeCount,
    required this.crawlStatus,
  });

  final int id;
  final String title;
  final String? url;
  final String? source;
  final String? thumbnail;

  /// 폴더 직접 업로드 이미지 자료(V28)의 원본 URL — 링크/텍스트 자료는 null.
  /// null이 아니면 이 자료는 이미지다(서버와 같은 관례 — url/bodyText/imageUrl 중 하나만 채워진다).
  final String? imageUrl;
  final bool pinned;
  final DateTime createdAt;
  final List<String> tags;
  final int likeCount;
  final String crawlStatus;

  factory ArchiveItem.fromJson(Map<String, dynamic> json) {
    return ArchiveItem(
      id: json['id'] as int,
      title: json['title'] as String,
      url: json['url'] as String?,
      source: json['source'] as String?,
      thumbnail: json['thumbnail'] as String?,
      imageUrl: json['imageUrl'] as String?,
      pinned: json['pinned'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      tags: (json['tags'] as List).cast<String>(),
      likeCount: json['likeCount'] as int,
      crawlStatus: json['crawlStatus'] as String,
    );
  }

  /// 핀 낙관적 토글용(목록에서 즉시 반영). 현재는 `pinned`만 바꾸면 충분하다.
  ArchiveItem copyWith({bool? pinned}) => ArchiveItem(
    id: id,
    title: title,
    url: url,
    source: source,
    thumbnail: thumbnail,
    imageUrl: imageUrl,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt,
    tags: tags,
    likeCount: likeCount,
    crawlStatus: crawlStatus,
  );
}

/// 자료를 등록한 사람 — 상세 화면 사진 우하단 아바타에 쓴다(2026-08-08, S-25-B 리디자인).
///
/// 서버는 `MemberBriefResponse`(userId·nickname·profileImage)를 그대로 실어 준다. 투두 탭에도 같은
/// 모양의 `MemberBrief`가 있지만 가져다 쓰지 않는다 — 이 앱은 기능별로 `*_api.dart`를 따로 두고
/// 공용 모델 계층이 없어서, 남의 기능 파일을 import 하면 아카이브가 투두에 묶인다.
class ArchiveItemCreator {
  ArchiveItemCreator({
    required this.userId,
    required this.nickname,
    this.profileImage,
  });

  final String userId;
  final String nickname;
  final String? profileImage;

  factory ArchiveItemCreator.fromJson(Map<String, dynamic> json) {
    return ArchiveItemCreator(
      userId: json['userId'] as String,
      nickname: json['nickname'] as String,
      profileImage: json['profileImage'] as String?,
    );
  }
}

class ArchiveItemDetail {
  ArchiveItemDetail({
    required this.id,
    required this.folderId,
    required this.title,
    required this.url,
    required this.source,
    required this.thumbnail,
    required this.summary,
    required this.bodyText,
    required this.pinned,
    required this.tags,
    required this.likeCount,
    required this.likedByMe,
    required this.createdAt,
    required this.crawlStatus,
    this.memo,
    // 뒤늦게 붙은 필드들은 `memo`와 같은 이유로 optional 이다 — 구버전 서버 응답에는 실제로 없고,
    // 이 화면 밖의 픽스처(위젯북·테스트)가 전부 이 값을 알 필요도 없다.
    this.folderName,
    this.createdBy,
    this.commentCount = 0,
    this.imageUrl,
  });

  final int id;
  final int folderId;

  /// 상세 화면 앱바에 쓰는 폴더 이름. 라우트가 `/archive/item/:id`라 **홈 아카이브 미리보기에서 곧바로
  /// 들어오면 폴더를 거치지 않아** 앱이 이름을 알 수 없다 — 그래서 서버가 실어 준다.
  /// **서버 배포 전 앱에서는 null**이라 앱바를 비운다.
  final String? folderName;

  /// 등록자 — **null일 수 있다.** 탈퇴하면 자료는 남고 작성자만 지워지고(`V9`), `created_by` 컬럼이
  /// 생기기 전 등록분은 애초에 비어 있다. 이때는 아바타 자리를 통째로 비운다(빈 원을 그리지 않는다).
  final ArchiveItemCreator? createdBy;

  final String title;
  final String? url;
  final String? source;
  final String? thumbnail;

  /// 폴더 직접 업로드 이미지 자료(V28)의 원본 URL — 링크/텍스트 자료는 null.
  final String? imageUrl;

  // 사용자 메모(자유 텍스트). 서버 도입 전이면 null → 화면에서 표시 생략.
  final String? memo;
  // 본문의 AI 요약. null이면 요약 영역을 감춘다 — 없는 것이 정상인 경우가 셋 있다:
  // V5 마이그레이션 이전에 등록된 자료 / 크롤링 전(PENDING) / 요약 호출 실패.
  final String? summary;
  // S-25-D 외부 공유(URL) 등록은 크롤링 전이라 bodyText가 아직 없을 수 있다(crawlStatus == 'PENDING').
  // ⚠️ 역은 성립하지 않는다 — 'PENDING'이라고 본문이 없는 것은 아니다. 2026-08-05부터 텍스트 공유도
  // PENDING으로 들어오는데(태깅·요약·임베딩이 남아서) 그쪽은 본문이 처음부터 채워져 있다.
  final String? bodyText;
  final bool pinned;
  final List<String> tags;
  final int likeCount;
  final bool likedByMe;
  final DateTime createdAt;
  final String crawlStatus;

  /// 댓글 수 — 하단 반응 바의 카운트(2026-08-09, S-25-B 댓글). 구버전 서버 응답에는 없어 0 폴백.
  final int commentCount;

  factory ArchiveItemDetail.fromJson(Map<String, dynamic> json) {
    final creator = json['createdBy'] as Map<String, dynamic>?;
    return ArchiveItemDetail(
      id: json['id'] as int,
      folderId: json['folderId'] as int,
      folderName: json['folderName'] as String?,
      createdBy: creator == null ? null : ArchiveItemCreator.fromJson(creator),
      title: json['title'] as String,
      url: json['url'] as String?,
      source: json['source'] as String?,
      thumbnail: json['thumbnail'] as String?,
      imageUrl: json['imageUrl'] as String?,
      summary: json['summary'] as String?,
      bodyText: json['bodyText'] as String?,
      pinned: json['pinned'] as bool,
      tags: (json['tags'] as List).cast<String>(),
      likeCount: json['likeCount'] as int,
      likedByMe: json['likedByMe'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      crawlStatus: json['crawlStatus'] as String,
      memo: json['memo'] as String?,
      commentCount: json['commentCount'] as int? ?? 0,
    );
  }

  ArchiveItemDetail copyWith({
    bool? pinned,
    bool? likedByMe,
    int? likeCount,
    int? commentCount,
  }) {
    return ArchiveItemDetail(
      id: id,
      folderId: folderId,
      folderName: folderName,
      createdBy: createdBy,
      title: title,
      url: url,
      source: source,
      thumbnail: thumbnail,
      imageUrl: imageUrl,
      summary: summary,
      bodyText: bodyText,
      pinned: pinned ?? this.pinned,
      tags: tags,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      createdAt: createdAt,
      crawlStatus: crawlStatus,
      memo: memo,
      commentCount: commentCount ?? this.commentCount,
    );
  }
}

/// 자료 댓글 한 건 — S-25-B 댓글 시트(2026-08-09). 서버 `ArchiveCommentResponse`.
///
/// [author]는 **null일 수 있다** — 탈퇴한 작성자면 서버가 비워 보낸다(`ON DELETE SET NULL`,
/// 상세의 `createdBy`와 같은 규칙). 이때 화면은 이니셜 '?' 아바타 + "(알 수 없음)"으로 그린다.
class ArchiveComment {
  ArchiveComment({
    required this.id,
    required this.body,
    required this.createdAt,
    this.author,
  });

  final int id;
  final ArchiveItemCreator? author;
  final String body;
  final DateTime createdAt;

  factory ArchiveComment.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    return ArchiveComment(
      id: json['id'] as int,
      author: author == null ? null : ArchiveItemCreator.fromJson(author),
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// 모아보기 "이미지" 탭 셀 하나 — 투두에 첨부된 사진(2026-08-09 기획 확정: 투두 이미지가
/// 이미지 탭에 쌓인다).
///
/// ⚠️ **서버 미구현 — 제안 계약이다**(`docs/backend/todo-image-archive-handoff.md`).
/// 서버가 다른 필드명/경로로 구현하면 이 모델과 [ArchiveApi.fetchTodoImages]만 고치면 된다.
class ArchiveTodoImage {
  ArchiveTodoImage({
    required this.id,
    required this.imageUrl,
    required this.todoId,
    required this.todoTitle,
    required this.pinned,
    required this.createdAt,
    this.assignee,
  });

  final int id;
  final String imageUrl;
  final int todoId;

  /// 사진 아래에 보여줄 관련 투두 제목.
  final String todoTitle;

  /// 사진 우하단에 얹을 담당자(대표 1명). 미지정 투두면 null → 아바타 생략.
  final ArchiveItemCreator? assignee;

  final bool pinned;
  final DateTime createdAt;

  factory ArchiveTodoImage.fromJson(Map<String, dynamic> json) {
    final assignee = json['assignee'] as Map<String, dynamic>?;
    return ArchiveTodoImage(
      id: json['id'] as int,
      imageUrl: json['imageUrl'] as String,
      todoId: json['todoId'] as int,
      todoTitle: json['todoTitle'] as String,
      assignee: assignee == null ? null : ArchiveItemCreator.fromJson(assignee),
      pinned: json['pinned'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  ArchiveTodoImage copyWith({bool? pinned}) => ArchiveTodoImage(
    id: id,
    imageUrl: imageUrl,
    todoId: todoId,
    todoTitle: todoTitle,
    assignee: assignee,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt,
  );
}
