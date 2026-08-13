package com.nomara.modi.server.domain.notification.repository;

import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import org.springframework.data.jpa.repository.JpaRepository;

public interface NotificationSettingRepository extends JpaRepository<NotificationSetting, String> {}
