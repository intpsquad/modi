import Foundation
import MobileCoreServices
import UIKit

/// S-25-D iOS Share Extension.
///
/// This target deliberately does not start Flutter. It receives one URL or
/// text item, lets the signed-in user choose an active room and archive folder,
/// and creates the server-side PENDING/DONE item before closing itself.
///
/// 2026-08-09: the title-entry step was removed — registration now happens the
/// moment a folder is picked or created, using the shared value as the title
/// (사용자 확정, specs/0014-외부-공유-등록.md). Room/folder selection and the new
/// folder form were also switched from system `UIAlertController`s to custom
/// rows styled with the app's design tokens (see `UIConstants` below).
final class ShareViewController: UIViewController {
  private enum UIConstants {
    // Mirrors specs/design.md and app/lib/design/tokens.dart. Native token
    // generation is intentionally not introduced for this small extension.
    static let primary = UIColor(red: 1, green: 56.0 / 255.0, blue: 92.0 / 255.0, alpha: 1)
    static let primaryActive = UIColor(red: 224.0 / 255.0, green: 11.0 / 255.0, blue: 65.0 / 255.0, alpha: 1)
    static let foreground = UIColor(red: 34.0 / 255.0, green: 34.0 / 255.0, blue: 34.0 / 255.0, alpha: 1)
    static let muted = UIColor(red: 106.0 / 255.0, green: 106.0 / 255.0, blue: 106.0 / 255.0, alpha: 1)
    static let border = UIColor(red: 221.0 / 255.0, green: 221.0 / 255.0, blue: 221.0 / 255.0, alpha: 1)
    static let surfaceSoft = UIColor(red: 247.0 / 255.0, green: 247.0 / 255.0, blue: 247.0 / 255.0, alpha: 1)
    static let danger = UIColor(red: 193.0 / 255.0, green: 53.0 / 255.0, blue: 21.0 / 255.0, alpha: 1)
  }

  /// 폴더 목록에 함께 노출하는 "새 폴더 만들기" 액션 라벨(QA).
  private static let newFolderActionTitle = "＋ 새 폴더 만들기"

  /// 클로저를 들고 다니는 버튼 — 방/폴더 행마다 다른 캡처값을 selector 없이 붙이기 위해서다.
  private final class TapButton: UIButton {
    var onTap: (() -> Void)?

    @objc fileprivate func handleTap() {
      onTap?()
    }
  }

  private let contentStack = UIStackView()
  private let titleLabel = UILabel()
  private let activityIndicator = UIActivityIndicatorView(style: .medium)
  private let statusLabel = UILabel()

  private var sharedContent: ShareContent?
  private var token: String?
  private var apiClient: ShareAPIClient?
  private var selectedRoom: ShareRoom?
  private var selectedFolder: ShareFolder?
  private var newFolderField: UITextField?
  private var started = false
  private var finishing = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    view.layoutMargins = UIEdgeInsets(top: 24, left: 20, bottom: 20, right: 20)
    preferredContentSize = CGSize(width: 0, height: 520)

    contentStack.axis = .vertical
    contentStack.alignment = .fill
    contentStack.spacing = 8
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(contentStack)
    NSLayoutConstraint.activate([
      contentStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      contentStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
      contentStack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
      contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor),
    ])

    titleLabel.text = "모아보기에 등록"
    titleLabel.font = .preferredFont(forTextStyle: .title2)
    titleLabel.textColor = UIConstants.foreground
    contentStack.addArrangedSubview(titleLabel)
    contentStack.setCustomSpacing(12, after: titleLabel)

    activityIndicator.color = UIConstants.primary
    activityIndicator.hidesWhenStopped = true
    activityIndicator.setContentHuggingPriority(.required, for: .vertical)

    statusLabel.font = .preferredFont(forTextStyle: .subheadline)
    statusLabel.textColor = UIConstants.muted
    statusLabel.numberOfLines = 0
    statusLabel.textAlignment = .center
    contentStack.addArrangedSubview(statusLabel)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    begin()
  }

  private func begin() {
    showLoading("공유한 자료를 준비하고 있어요")
    loadSharedContent { [weak self] result in
      guard let self else { return }
      DispatchQueue.main.async {
        switch result {
        case .success(let content):
          self.sharedContent = content
          guard let token = ShareSessionStore.loadIDToken() else {
            self.showFinishingMessage("앱을 열어 로그인해주세요")
            return
          }
          guard let baseURL = ShareSessionStore.apiBaseURL else {
            self.showFinishingMessage("앱을 열어 다시 시도해주세요")
            return
          }
          self.token = token
          self.apiClient = ShareAPIClient(baseURL: baseURL)
          self.fetchRooms()
        case .failure:
          self.showFinishingMessage("공유할 링크나 텍스트를 찾지 못했어요")
        }
      }
    }
  }

  // MARK: - Shared content

  private func loadSharedContent(completion: @escaping (Result<ShareContent, Error>) -> Void) {
    let providers = extensionContext?.inputItems
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] } ?? []
    loadNextProvider(providers, index: 0, completion: completion)
  }

  private func loadNextProvider(
    _ providers: [NSItemProvider],
    index: Int,
    completion: @escaping (Result<ShareContent, Error>) -> Void
  ) {
    guard index < providers.count else {
      completion(.failure(ShareExtensionError.noShareContent))
      return
    }

    let provider = providers[index]
    let urlType = kUTTypeURL as String
    let textType = kUTTypeText as String

    if provider.hasItemConformingToTypeIdentifier(urlType) {
      provider.loadItem(forTypeIdentifier: urlType, options: nil) { [weak self] item, _ in
        if let value = self?.stringValue(from: item),
           let content = ShareContentParser.parse(value) {
          completion(.success(content))
          return
        }
        self?.loadNextProvider(providers, index: index + 1, completion: completion)
      }
      return
    }

    if provider.hasItemConformingToTypeIdentifier(textType) {
      provider.loadItem(forTypeIdentifier: textType, options: nil) { [weak self] item, _ in
        if let value = self?.stringValue(from: item),
           let content = ShareContentParser.parse(value) {
          completion(.success(content))
          return
        }
        self?.loadNextProvider(providers, index: index + 1, completion: completion)
      }
      return
    }

    loadNextProvider(providers, index: index + 1, completion: completion)
  }

  private func stringValue(from item: NSSecureCoding?) -> String? {
    if let value = item as? URL { return value.absoluteString }
    if let value = item as? NSURL { return value.absoluteString }
    if let value = item as? String { return value }
    if let value = item as? NSString { return value as String }
    if let value = item as? Data { return String(data: value, encoding: .utf8) }
    return nil
  }

  // MARK: - Room/folder flow

  private func fetchRooms() {
    guard let token, let apiClient else { return }
    showLoading("등록할 방을 불러오고 있어요")
    apiClient.fetchRooms(token: token) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        switch result {
        case .success(let rooms):
          let activeRooms = rooms.filter { $0.status == nil || $0.status == "ACTIVE" }
          guard !activeRooms.isEmpty else {
            self.showFinishingMessage("진행 중인 방이 없어요")
            return
          }
          if activeRooms.count == 1 {
            self.fetchFolders(for: activeRooms[0])
          } else {
            self.presentRoomSelection(activeRooms)
          }
        case .failure(let error):
          self.showFinishingMessage(self.message(for: error, fallback: "등록하지 못했어요"))
        }
      }
    }
  }

  /// 방 목록 — 커스텀 리스트 화면(2026-08-09, 시스템 알림창 대체).
  private func presentRoomSelection(_ rooms: [ShareRoom]) {
    clearContent()
    showInstruction("등록할 방을 선택해주세요")
    for room in rooms {
      contentStack.addArrangedSubview(
        makeListRow(title: room.name) { [weak self] in
          self?.fetchFolders(for: room)
        }
      )
    }
    addCancelRow()
  }

  private func fetchFolders(for room: ShareRoom) {
    guard let token, let apiClient else { return }
    selectedRoom = room
    showLoading("등록할 폴더를 불러오고 있어요")
    apiClient.fetchFolders(roomID: room.id, token: token) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        switch result {
        case .success(let folders):
          // 폴더가 하나도 없어도 앱에 들어가지 않고 바로 새 폴더를 만들어 등록할 수 있게 한다
          // (specs/0014 개정 QA). 예전엔 여기서 안내 후 종료했다.
          if folders.isEmpty {
            self.promptNewFolder(in: room)
          } else {
            self.presentFolderSelection(folders, in: room)
          }
        case .failure(let error):
          self.showFinishingMessage(self.message(for: error, fallback: "등록하지 못했어요"))
        }
      }
    }
  }

  /// 폴더 목록 — 커스텀 리스트 화면. 행을 고르면(또는 새로 만들면) **그 즉시 등록한다**
  /// (2026-08-09, 제목 입력 단계 제거 — 사용자 확정).
  private func presentFolderSelection(_ folders: [ShareFolder], in room: ShareRoom) {
    clearContent()
    showInstruction("등록할 폴더를 선택해주세요")
    for folder in folders {
      contentStack.addArrangedSubview(
        makeListRow(title: folder.name) { [weak self] in
          self?.registerNow(in: room, folder: folder)
        }
      )
    }
    // 폴더가 있어도 새 폴더를 바로 만들 수 있게 선택지를 추가한다.
    contentStack.addArrangedSubview(
      makeListRow(title: Self.newFolderActionTitle, textColor: UIConstants.primary) { [weak self] in
        self?.promptNewFolder(in: room)
      }
    )
    addCancelRow()
  }

  // MARK: - New folder

  /// 공유 흐름 안에서 새 아카이브 폴더 이름을 입력받는다(QA). 커스텀 폼(2026-08-09,
  /// 시스템 알림창 대체) — errorMessage가 있으면(생성 실패 재시도) 안내를 빨간색으로 보여준다.
  private func promptNewFolder(in room: ShareRoom, errorMessage: String? = nil) {
    clearContent()
    if let errorMessage {
      showInlineError(errorMessage)
    } else {
      showInstruction("새 폴더를 만들어 등록해보세요")
    }

    let field = UITextField()
    field.borderStyle = .roundedRect
    field.font = .preferredFont(forTextStyle: .body)
    field.placeholder = "폴더 이름"
    field.autocapitalizationType = .none
    field.clearButtonMode = .whileEditing
    field.heightAnchor.constraint(equalToConstant: 48).isActive = true
    newFolderField = field
    contentStack.addArrangedSubview(field)

    contentStack.addArrangedSubview(
      makePrimaryButton(title: "만들기") { [weak self] in
        self?.createFolderTapped(in: room)
      }
    )
    addCancelRow()
  }

  private func createFolderTapped(in room: ShareRoom) {
    let name = newFolderField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !name.isEmpty else {
      promptNewFolder(in: room, errorMessage: "이름을 입력해 주세요")
      return
    }
    createFolder(named: String(name.prefix(20)), in: room)
  }

  private func createFolder(named name: String, in room: ShareRoom) {
    guard let token, let apiClient else { return }
    showLoading("폴더를 만들고 있어요")
    apiClient.createFolder(roomID: room.id, name: name, token: token) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        switch result {
        case .success(let folder):
          // 만든 폴더로 바로 등록한다.
          self.registerNow(in: room, folder: folder)
        case .failure(let error):
          // 인증 실패는 확장 안에서 복구 불가라 종료, 그 외(일시적 오류)는
          // Android·등록 실패와 동일하게 이름 입력을 유지해 재시도하게 한다.
          if self.isAuthenticationFailure(error) {
            self.showFinishingMessage("앱을 열어 로그인해주세요")
            return
          }
          self.promptNewFolder(in: room, errorMessage: "폴더를 만들지 못했어요. 다시 시도해주세요")
        }
      }
    }
  }

  // MARK: - Register (폴더 확정 즉시 자동 등록, 2026-08-09)

  /// 방·폴더가 확정된 순간(기존 폴더 선택 또는 새 폴더 생성 직후) 공유된 값을 제목으로 그대로
  /// 등록한다. 제목을 따로 입력받지 않는다 — 사용자 확정.
  private func registerNow(in room: ShareRoom, folder: ShareFolder) {
    guard let sharedContent, let token, let apiClient else { return }
    selectedRoom = room
    selectedFolder = folder
    let title = String(sharedContent.value.prefix(255))
    showLoading("모아보기에 등록하고 있어요")
    apiClient.registerItem(
      roomID: room.id,
      folderID: folder.id,
      title: title,
      content: sharedContent,
      token: token
    ) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        switch result {
        case .success:
          self.showInstruction("모아보기에 등록했어요")
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.complete()
          }
        case .failure(let error):
          if self.isAuthenticationFailure(error) {
            self.showFinishingMessage("앱을 열어 로그인해주세요")
            return
          }
          self.showRegisterRetry(in: room, folder: folder)
        }
      }
    }
  }

  /// 등록 실패 — 인라인 에러 + 다시 시도(같은 방·폴더로 재호출)/취소만 보여준다(제목 재입력 없음).
  private func showRegisterRetry(in room: ShareRoom, folder: ShareFolder) {
    clearContent()
    showInlineError("등록하지 못했어요. 다시 시도해주세요")
    contentStack.addArrangedSubview(
      makePrimaryButton(title: "다시 시도") { [weak self] in
        self?.registerNow(in: room, folder: folder)
      }
    )
    addCancelRow()
  }

  // MARK: - UI helpers

  /// 방·폴더 행처럼 여러 개를 나열하는 리스트 아이템 — surfaceSoft 배경 + 왼쪽 정렬(design.md 카드 톤).
  private func makeListRow(
    title: String,
    textColor: UIColor = UIConstants.foreground,
    onTap: @escaping () -> Void
  ) -> UIView {
    let button = TapButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(textColor, for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .body)
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.contentHorizontalAlignment = .left
    button.backgroundColor = UIConstants.surfaceSoft
    button.layer.cornerRadius = 12
    button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
    button.heightAnchor.constraint(equalToConstant: 48).isActive = true
    button.onTap = onTap
    button.addTarget(button, action: #selector(TapButton.handleTap), for: .touchUpInside)
    return button
  }

  /// 강조 CTA(만들기/다시 시도) — primary 채움 + 흰 글씨(design.md 버튼 톤, 기존 등록 버튼과 동일 스타일).
  private func makePrimaryButton(title: String, onTap: @escaping () -> Void) -> UIView {
    let button = TapButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.setTitleColor(.white.withAlphaComponent(0.65), for: .disabled)
    button.backgroundColor = UIConstants.primary
    button.layer.cornerRadius = 8
    button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    button.heightAnchor.constraint(equalToConstant: 48).isActive = true
    button.onTap = onTap
    button.addTarget(button, action: #selector(TapButton.handleTap), for: .touchUpInside)
    return button
  }

  private func addCancelRow() {
    let button = TapButton(type: .system)
    button.setTitle("취소", for: .normal)
    button.setTitleColor(UIConstants.foreground, for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .body)
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    button.onTap = { [weak self] in self?.cancel() }
    button.addTarget(button, action: #selector(TapButton.handleTap), for: .touchUpInside)
    contentStack.addArrangedSubview(button)
  }

  private func clearContent() {
    for subview in contentStack.arrangedSubviews where subview !== titleLabel {
      contentStack.removeArrangedSubview(subview)
      subview.removeFromSuperview()
    }
    activityIndicator.stopAnimating()
    newFolderField = nil
  }

  private func showLoading(_ message: String) {
    clearContent()
    activityIndicator.startAnimating()
    contentStack.addArrangedSubview(activityIndicator)
    showInstruction(message)
  }

  private func showInstruction(_ message: String) {
    statusLabel.text = message
    statusLabel.textColor = UIConstants.muted
    if statusLabel.superview == nil {
      contentStack.addArrangedSubview(statusLabel)
    }
  }

  private func showInlineError(_ message: String) {
    activityIndicator.stopAnimating()
    statusLabel.text = message
    statusLabel.textColor = UIConstants.danger
    if statusLabel.superview == nil {
      contentStack.addArrangedSubview(statusLabel)
    }
  }

  private func isAuthenticationFailure(_ error: Error) -> Bool {
    if case ShareAPIError.httpStatus(401) = error { return true }
    return false
  }

  private func message(for error: Error, fallback: String) -> String {
    isAuthenticationFailure(error) ? "앱을 열어 로그인해주세요" : fallback
  }

  private func showFinishingMessage(_ message: String) {
    guard !finishing else { return }
    clearContent()
    showInstruction(message)
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in self?.cancel() })
    present(alert, animated: true)
  }

  private func cancel() {
    guard !finishing else { return }
    finishing = true
    let error = NSError(
      domain: "com.nomara.modi.share-extension",
      code: 1,
      userInfo: nil
    )
    extensionContext?.cancelRequest(withError: error)
  }

  private func complete() {
    guard !finishing else { return }
    finishing = true
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}

private enum ShareExtensionError: Error {
  case noShareContent
}
