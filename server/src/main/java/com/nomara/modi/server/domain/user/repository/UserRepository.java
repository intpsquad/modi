package com.nomara.modi.server.domain.user.repository;

import com.nomara.modi.server.domain.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<User, String> {}
