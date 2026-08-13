package com.nomara.modi.server.domain.category.controller;

import com.nomara.modi.server.domain.category.dto.CategoryResponse;
import com.nomara.modi.server.domain.category.dto.CreateCategoryRequest;
import com.nomara.modi.server.domain.category.dto.UpdateCategoryRequest;
import com.nomara.modi.server.domain.category.service.CategoryService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** specs/0006-투두-탭.md — 카테고리 CRUD(S-15 인라인). */
@RestController
public class CategoryController {

  private final CategoryService categoryService;

  public CategoryController(CategoryService categoryService) {
    this.categoryService = categoryService;
  }

  @GetMapping("/rooms/{roomId}/categories")
  public List<CategoryResponse> list(HttpServletRequest request, @PathVariable Long roomId) {
    return categoryService.listCategories(uid(request), roomId);
  }

  @PostMapping("/rooms/{roomId}/categories")
  @ResponseStatus(HttpStatus.CREATED)
  public CategoryResponse create(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @Valid @RequestBody CreateCategoryRequest body) {
    return categoryService.createCategory(uid(request), roomId, body);
  }

  @PatchMapping("/rooms/{roomId}/categories/order")
  public List<CategoryResponse> reorder(
      HttpServletRequest request, @PathVariable Long roomId, @RequestBody List<Long> categoryIds) {
    return categoryService.reorderCategories(uid(request), roomId, categoryIds);
  }

  @PatchMapping("/rooms/{roomId}/categories/{categoryId}")
  public CategoryResponse rename(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long categoryId,
      @Valid @RequestBody UpdateCategoryRequest body) {
    return categoryService.renameCategory(uid(request), roomId, categoryId, body);
  }

  @DeleteMapping("/rooms/{roomId}/categories/{categoryId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long categoryId) {
    categoryService.deleteCategory(uid(request), roomId, categoryId);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
