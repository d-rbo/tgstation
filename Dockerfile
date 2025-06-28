# Используем более легкий базовый образ
FROM ubuntu:22.04

# Предотвращаем интерактивные запросы
ENV DEBIAN_FRONTEND=noninteractive

# Устанавливаем только необходимые системные зависимости в одном слое
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    unzip \
    curl \
    gcc \
    g++ \
    libc6-dev \
    libssl3 \
    python3 \
    python3-pip \
    git \
    make \
    pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && rm -rf /tmp/* /var/tmp/*

# Устанавливаем Node.js 18 (более компактная установка)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем только необходимые файлы сначала (для лучшего кэширования)
COPY package*.json ./
COPY tools/ ./tools/
COPY tgui/ ./tgui/

# Install bun (required for tgui build) - более компактная установка
RUN curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    # Очищаем кэш установки
    rm -rf /root/.bun/install/cache

# УСТАНОВКА WINE (только если абсолютно необходимо)
# Попробуйте использовать Linux версию BYOND если возможно
RUN echo "=== INSTALLING WINE (minimal) ===" && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends wine wine32 && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    # Убираем ненужные файлы wine
    rm -rf /usr/share/wine/mono /usr/share/wine/gecko

# Копируем BYOND только после установки wine
COPY BYOND/ /usr/local/byond/

# Настройка BYOND (компактная версия)
RUN if [ -d "/usr/local/byond" ]; then \
        find /usr/local/byond -type f -name "*.exe" -exec chmod +x {} \; && \
        # Удаляем ненужные файлы из BYOND
        find /usr/local/byond -name "*.pdb" -delete && \
        find /usr/local/byond -name "*.lib" -delete && \
        echo "BYOND installed"; \
    else \
        echo "ERROR: No BYOND found" && exit 1; \
    fi

# Настраиваем переменные окружения
ENV PATH="/usr/local/bin:${PATH}"
ENV WINEDLLOVERRIDES="mscoree,mshtml="
ENV DISPLAY=:0

# НАСТРОЙКА WINE И СОЗДАНИЕ WRAPPER'ов (компактная версия)
RUN echo "=== SETTING UP WINE WRAPPERS ===" && \
    export WINEDLLOVERRIDES="mscoree,mshtml=" && \
    export DISPLAY=:0 && \
    wineboot --init 2>/dev/null || true && \
    # Создаем wrapper для dm.exe
    echo -e '#!/bin/bash\nexport WINEDLLOVERRIDES="mscoree,mshtml="\nexport DISPLAY=:0\nwine /usr/local/byond/bin/dm.exe "$@" 2>/dev/null' > /usr/local/bin/dm && \
    chmod +x /usr/local/bin/dm && \
    # Создаем wrapper для dreamdaemon.exe
    echo -e '#!/bin/bash\nexport WINEDLLOVERRIDES="mscoree,mshtml="\nexport DISPLAY=:0\nwine /usr/local/byond/bin/dreamdaemon.exe "$@" 2>/dev/null' > /usr/local/bin/dreamdaemon && \
    chmod +x /usr/local/bin/dreamdaemon && \
    ln -sf /usr/local/bin/dm /usr/local/bin/DreamMaker && \
    # Очищаем временные файлы wine
    rm -rf /root/.wine/drive_c/windows/Installer/*

# Копируем остальной код проекта
COPY . .

# СБОРКА TGUI И DM (в одном слое для экономии места)
RUN echo "=== BUILDING PROJECT ===" && \
    export PATH="/usr/local/byond/bin:$PATH" && \
    # Собираем TGUI
    echo "Building TGUI..." && \
    node tools/build/build.js tgui --skip-icon-cutter && \
    # Собираем DM
    echo "Building DM..." && \
    node tools/build/build.js dm --skip-icon-cutter && \
    # Очищаем временные файлы сборки
    rm -rf node_modules/.cache && \
    rm -rf /tmp/* && \
    # Проверяем результат
    if [ -f "tgstation.dmb" ]; then \
        echo "SUCCESS: Build completed" && \
        ls -lh tgstation.dmb; \
    else \
        echo "ERROR: Build failed" && \
        exit 1; \
    fi

# Удаляем ненужные файлы после сборки
RUN echo "=== CLEANUP ===" && \
    # Удаляем исходники после сборки (оставляем только скомпилированные файлы)
    find . -name "*.dm" -not -path "./maps/*" -delete 2>/dev/null || true && \
    find . -name "*.dmi" -delete 2>/dev/null || true && \
    # Удаляем инструменты сборки
    rm -rf tools/build && \
    rm -rf tgui/packages && \
    # Очищаем кэши
    rm -rf /root/.npm && \
    rm -rf /root/.cache && \
    rm -rf /var/cache/* && \
    # Удаляем документацию и примеры
    rm -rf /usr/share/doc && \
    rm -rf /usr/share/man && \
    find /usr -name "*.a" -delete 2>/dev/null || true

# Открываем порты
EXPOSE 1337

# Создаем компактный startup скрипт
RUN echo -e '#!/bin/bash\necho "=== SS13 SERVER STARTUP ==="\nif [ ! -f "tgstation.dmb" ]; then\n    echo "ERROR: tgstation.dmb not found"; exit 1\nfi\nDAEMON_PATH=$(find /usr/local -name "dreamdaemon" -type f 2>/dev/null | head -1)\nif [ -z "$DAEMON_PATH" ]; then\n    echo "ERROR: dreamdaemon not found"; exit 1\nfi\necho "Starting SS13 server on port 1337..."\nexec "$DAEMON_PATH" tgstation.dmb -port 1337 -trusted -verbose' > /app/start_server.sh && \
    chmod +x /app/start_server.sh

# Команда запуска
CMD ["/app/start_server.sh"]
