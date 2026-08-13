package com.nomara.modi.server.domain.category.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.category.dto.CategoryResponse;
import com.nomara.modi.server.domain.category.dto.CreateCategoryRequest;
import com.nomara.modi.server.domain.category.dto.UpdateCategoryRequest;
import com.nomara.modi.server.domain.category.entity.Category;
import com.nomara.modi.server.domain.category.repository.CategoryRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 카테고리 CRUD(specs/0006-투두-탭.md, S-15 인라인)를 실제 Postgres+Redis(Testcontainers)로 검증한다. */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CategoryServiceTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @Container
  @ServiceConnection(name = "redis")
  static GenericContainer<?> redis =
      new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
  }

  @Autowired private TestRestTemplate restTemplate;
  @Autowired private CategoryService categoryService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private CategoryRepository categoryRepository;
  @Autowired private TodoRepository todoRepository;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  @Test
  void listWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/rooms/1/categories", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void createCategoryThenListReturnsInCreationOrder() {
    Room room = room();
    User member = user("uid-cat-a");
    roomMemberRepository.save(new RoomMember(room, member));

    categoryService.createCategory(member.getId(), room.getId(), new CreateCategoryRequest("첫번째"));
    categoryService.createCategory(member.getId(), room.getId(), new CreateCategoryRequest("두번째"));

    List<CategoryResponse> categories =
        categoryService.listCategories(member.getId(), room.getId());

    assertThat(categories).extracting(CategoryResponse::name).containsExactly("첫번째", "두번째");
  }

  @Test
  void renameCategoryUpdatesName() {
    Room room = room();
    User member = user("uid-cat-b");
    roomMemberRepository.save(new RoomMember(room, member));
    CategoryResponse created =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("원래이름"));

    CategoryResponse renamed =
        categoryService.renameCategory(
            member.getId(), room.getId(), created.id(), new UpdateCategoryRequest("바뀐이름"));

    assertThat(renamed.name()).isEqualTo("바뀐이름");
  }

  @Test
  void deletingCategorySetsChildTodosCategoryToNull() {
    Room room = room();
    User member = user("uid-cat-c");
    roomMemberRepository.save(new RoomMember(room, member));
    Category category = categoryRepository.save(new Category(room, "삭제될 카테고리"));
    Todo todo = todoRepository.save(new Todo(room, category, "하위 투두", null));

    categoryService.deleteCategory(member.getId(), room.getId(), category.getId());

    assertThat(categoryRepository.findById(category.getId())).isEmpty();
    assertThat(todoRepository.findById(todo.getId()).orElseThrow().getCategory()).isNull();
  }

  @Test
  void nonMemberCannotCreateCategory() {
    Room room = room();
    User member = user("uid-cat-owner");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                categoryService.createCategory(
                    "uid-cat-outsider", room.getId(), new CreateCategoryRequest("이름")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void categoryFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-cat-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    Category categoryOfRoomB = categoryRepository.save(new Category(roomB, "남의 카테고리"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                categoryService.renameCategory(
                    member.getId(),
                    roomA.getId(),
                    categoryOfRoomB.getId(),
                    new UpdateCategoryRequest("바꾸기")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void reorderCategoriesUpdatesOrder() {
    Room room = room();
    User member = user("uid-cat-order-a");
    roomMemberRepository.save(new RoomMember(room, member));
    CategoryResponse first =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("첫번째"));
    CategoryResponse second =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("두번째"));
    CategoryResponse third =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("세번째"));

    List<CategoryResponse> reordered =
        categoryService.reorderCategories(
            member.getId(), room.getId(), List.of(third.id(), first.id(), second.id()));

    assertThat(reordered).extracting(CategoryResponse::name).containsExactly("세번째", "첫번째", "두번째");
    assertThat(categoryService.listCategories(member.getId(), room.getId()))
        .extracting(CategoryResponse::name)
        .containsExactly("세번째", "첫번째", "두번째");
  }

  @Test
  void creatingCategoryAfterReorderAppendsAtEnd() {
    Room room = room();
    User member = user("uid-cat-order-b");
    roomMemberRepository.save(new RoomMember(room, member));
    CategoryResponse first =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("첫번째"));
    CategoryResponse second =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("두번째"));
    categoryService.reorderCategories(
        member.getId(), room.getId(), List.of(second.id(), first.id()));

    categoryService.createCategory(member.getId(), room.getId(), new CreateCategoryRequest("새로만듦"));

    assertThat(categoryService.listCategories(member.getId(), room.getId()))
        .extracting(CategoryResponse::name)
        .containsExactly("두번째", "첫번째", "새로만듦");
  }

  @Test
  void nonMemberCannotReorderCategories() {
    Room room = room();
    User member = user("uid-cat-order-c");
    roomMemberRepository.save(new RoomMember(room, member));
    CategoryResponse only =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("하나"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                categoryService.reorderCategories(
                    "uid-cat-order-outsider", room.getId(), List.of(only.id())),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void reorderWithIdFromAnotherRoomIsRejectedAsBadRequest() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-cat-order-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    CategoryResponse categoryOfRoomA =
        categoryService.createCategory(
            member.getId(), roomA.getId(), new CreateCategoryRequest("A방"));
    Category categoryOfRoomB = categoryRepository.save(new Category(roomB, "B방"));

    // roomA에 대한 reorder 요청인데 roomB 소속 id가 섞여 있음 — 카테고리 하나가
    // 없다는 의미(404)가 아니라 "정상적인 순열이 아니다"라는 의미라 400을 던진다.
    ApiException ex =
        catchThrowableOfType(
            () ->
                categoryService.reorderCategories(
                    member.getId(),
                    roomA.getId(),
                    List.of(categoryOfRoomB.getId(), categoryOfRoomA.id())),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void reorderWithMissingCategoryIsRejectedAsBadRequest() {
    Room room = room();
    User member = user("uid-cat-order-missing");
    roomMemberRepository.save(new RoomMember(room, member));
    CategoryResponse first =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("첫번째"));
    categoryService.createCategory(member.getId(), room.getId(), new CreateCategoryRequest("두번째"));

    // 방에는 카테고리가 2개인데 1개짜리 목록만 보냄 — 정상적인 순열이 아니다.
    ApiException ex =
        catchThrowableOfType(
            () ->
                categoryService.reorderCategories(
                    member.getId(), room.getId(), List.of(first.id())),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void reorderWithDuplicateIdIsRejectedAsBadRequest() {
    Room room = room();
    User member = user("uid-cat-order-dup");
    roomMemberRepository.save(new RoomMember(room, member));
    CategoryResponse first =
        categoryService.createCategory(
            member.getId(), room.getId(), new CreateCategoryRequest("첫번째"));
    // 카테고리를 2개 만들어 크기는 맞추고(2==2), id 중복만으로 실패하는지를 격리해서 검증한다.
    categoryService.createCategory(member.getId(), room.getId(), new CreateCategoryRequest("두번째"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                categoryService.reorderCategories(
                    member.getId(), room.getId(), List.of(first.id(), first.id())),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }
}
