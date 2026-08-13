package com.nomara.modi.server.domain.category.service;

import com.nomara.modi.server.domain.category.dto.CategoryResponse;
import com.nomara.modi.server.domain.category.dto.CreateCategoryRequest;
import com.nomara.modi.server.domain.category.dto.UpdateCategoryRequest;
import com.nomara.modi.server.domain.category.entity.Category;
import com.nomara.modi.server.domain.category.exception.CategoryNotFoundException;
import com.nomara.modi.server.domain.category.repository.CategoryRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** specs/0006-투두-탭.md — 카테고리는 S-15 화면 내 인라인 CRUD로만 존재(별도 화면 없음). */
@Service
public class CategoryService {

  private final CategoryRepository categoryRepository;
  private final RoomRepository roomRepository;
  private final RoomMemberRepository roomMemberRepository;

  public CategoryService(
      CategoryRepository categoryRepository,
      RoomRepository roomRepository,
      RoomMemberRepository roomMemberRepository) {
    this.categoryRepository = categoryRepository;
    this.roomRepository = roomRepository;
    this.roomMemberRepository = roomMemberRepository;
  }

  @Transactional(readOnly = true)
  public List<CategoryResponse> listCategories(String uid, Long roomId) {
    requireMembership(uid, roomId);
    return categoryRepository.findByRoomIdOrderByPositionAscIdAsc(roomId).stream()
        .map(CategoryResponse::of)
        .toList();
  }

  @Transactional
  public CategoryResponse createCategory(String uid, Long roomId, CreateCategoryRequest request) {
    requireMembership(uid, roomId);
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    int position =
        categoryRepository
            .findFirstByRoomIdOrderByPositionDesc(roomId)
            .map(c -> c.getPosition() + 1)
            .orElse(0);
    Category saved = categoryRepository.save(new Category(room, request.name(), position));
    return CategoryResponse.of(saved);
  }

  @Transactional
  /**
   * 순열 검증(크기·중복·소속 방 일치)은 요청받은 순서가 지금 방의 카테고리 구성과 맞는지만 확인하는 것이지 낙관적 동시성 제어(OCC)가 아니다 — 버전이나 타임스탬프를
   * 비교하지 않는다. 두 클라이언트가 동시에 서로 다른 순서로 reorder를 보내면 둘 다 검증을 통과하고 나중에 커밋되는 쪽이 이긴다 (last-write-wins).
   * 순서변경은 파괴적이지 않은 작업이라 이 정도로 충분하다고 판단했다.
   */
  public List<CategoryResponse> reorderCategories(String uid, Long roomId, List<Long> categoryIds) {
    requireMembership(uid, roomId);
    List<Category> current = categoryRepository.findByRoomIdOrderByPositionAscIdAsc(roomId);

    boolean sameSize = categoryIds.size() == current.size();
    boolean noDuplicates = new HashSet<>(categoryIds).size() == categoryIds.size();
    Set<Long> currentIds = current.stream().map(Category::getId).collect(Collectors.toSet());
    boolean allBelongToRoom = currentIds.containsAll(categoryIds);
    if (!sameSize || !noDuplicates || !allBelongToRoom) {
      throw new BadRequestException("카테고리 순서 목록이 방의 카테고리 구성과 일치하지 않아요");
    }

    Map<Long, Integer> targetPositionByCategoryId = new HashMap<>();
    for (int i = 0; i < categoryIds.size(); i++) {
      targetPositionByCategoryId.put(categoryIds.get(i), i);
    }
    // id 오름차순으로 적용해 동시에 반대 순서로 들어오는 두 reorder 요청이
    // 서로 다른 순서로 행을 잠가 교착(deadlock)하는 것을 방지한다.
    current.stream()
        .sorted(Comparator.comparingLong(Category::getId))
        .forEach(category -> category.moveTo(targetPositionByCategoryId.get(category.getId())));

    Map<Long, Category> categoryById =
        current.stream().collect(Collectors.toMap(Category::getId, c -> c));
    return categoryIds.stream().map(categoryById::get).map(CategoryResponse::of).toList();
  }

  @Transactional
  public CategoryResponse renameCategory(
      String uid, Long roomId, Long categoryId, UpdateCategoryRequest request) {
    requireMembership(uid, roomId);
    Category category = resolveCategory(roomId, categoryId);
    category.rename(request.name());
    return CategoryResponse.of(category);
  }

  @Transactional
  public void deleteCategory(String uid, Long roomId, Long categoryId) {
    requireMembership(uid, roomId);
    Category category = resolveCategory(roomId, categoryId);
    // 하위 todos.category_id는 DB ON DELETE SET NULL로 자동 미분류 전환 — 별도 재배치 코드 불필요.
    categoryRepository.delete(category);
  }

  private Category resolveCategory(Long roomId, Long categoryId) {
    Category category =
        categoryRepository.findById(categoryId).orElseThrow(CategoryNotFoundException::new);
    if (!category.getRoom().getId().equals(roomId)) {
      throw new CategoryNotFoundException();
    }
    return category;
  }

  private void requireMembership(String uid, Long roomId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
  }
}
