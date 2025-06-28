# Используем Ubuntu 22.04 для поддержки GLIBC 2.35
FROM ubuntu:22.04

# Предотвращаем интерактивные запросы
ENV DEBIAN_FRONTEND=noninteractive

# Устанавливаем системные зависимости
RUN apt-get update && apt-get install -y \
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
    lib32z1 \
    lib32ncurses6 \
    lib32stdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Устанавливаем Node.js 18
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем весь проект
COPY . .

# Install bun (required for tgui build)
RUN curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun

# Проверяем версию GLIBC
RUN echo "=== GLIBC VERSION CHECK ===" && \
    ldd --version

# УСТАНОВКА WINE ДЛЯ ЗАПУСКА WINDOWS BYOND
RUN echo "=== INSTALLING WINE FOR WINDOWS BYOND ===" && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y wine32 wine64 winbind && \
    rm -rf /var/lib/apt/lists/*

# УСТАНОВКА BYOND ЧЕРЕЗ WINE
RUN echo "=== INSTALLING BYOND ===" && \
    if [ -d "BYOND" ]; then \
        echo "Found local BYOND directory" && \
        if [ -d "BYOND/byond" ]; then \
            cp -r BYOND/byond /usr/local/byond; \
        elif [ -d "BYOND/bin" ]; then \
            mkdir -p /usr/local/byond && \
            cp -r BYOND/* /usr/local/byond/; \
        else \
            cp -r BYOND /usr/local/byond; \
        fi && \
        find /usr/local/byond -type f -name "*.exe" -exec chmod +x {} \; && \
        echo "BYOND installed from local directory"; \
    else \
        echo "ERROR: No local BYOND found and byond.com is down" && \
        exit 1; \
    fi

# Проверяем установку BYOND (Windows версия через Wine)
RUN echo "=== BYOND CHECK ===" && \
    echo "Looking for Windows BYOND binaries:" && \
    find /usr/local/byond -name "dm.exe" -type f && \
    find /usr/local/byond -name "dreamdaemon.exe" -type f && \
    echo "BYOND directory contents:" && \
    ls -la /usr/local/byond/bin/

# Настраиваем переменные окружения
ENV PATH="/usr/local/bin:${PATH}"
ENV WINEDLLOVERRIDES="mscoree,mshtml="
ENV DISPLAY=:0

# НАСТРОЙКА WINE И СОЗДАНИЕ WRAPPER'ов
RUN echo "=== SETTING UP WINE WRAPPERS ===" && \
    # Инициализируем Wine
    export WINEDLLOVERRIDES="mscoree,mshtml=" && \
    export DISPLAY=:0 && \
    wineboot --init 2>/dev/null || true && \
    # Создаем wrapper для dm.exe
    echo '#!/bin/bash' > /usr/local/bin/dm && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /usr/local/bin/dm && \
    echo 'export DISPLAY=:0' >> /usr/local/bin/dm && \
    echo 'wine /usr/local/byond/bin/dm.exe "$@" 2>/dev/null' >> /usr/local/bin/dm && \
    chmod +x /usr/local/bin/dm && \
    # Создаем wrapper для dreamdaemon.exe
    echo '#!/bin/bash' > /usr/local/bin/dreamdaemon && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /usr/local/bin/dreamdaemon && \
    echo 'export DISPLAY=:0' >> /usr/local/bin/dreamdaemon && \
    echo 'wine /usr/local/byond/bin/dreamdaemon.exe "$@" 2>/dev/null' >> /usr/local/bin/dreamdaemon && \
    chmod +x /usr/local/bin/dreamdaemon && \
    # Создаем симлинк DreamMaker
    ln -sf /usr/local/bin/dm /usr/local/bin/DreamMaker

# СБОРКА TGUI (интерфейс) - это критически важно!
RUN echo "=== BUILDING TGUI ===" && \
    export PATH="/usr/local/byond/bin:$PATH" && \
    cd /app && \
    echo "Building TGUI components..." && \
    node tools/build/build.js tgui --skip-icon-cutter

# СБОРКА DM (игровая логика) 
RUN echo "=== BUILDING DM ===" && \
    export PATH="/usr/local/byond/bin:$PATH" && \
    cd /app && \
    echo "Building DM components..." && \
    node tools/build/build.js dm --skip-icon-cutter

# Проверяем результат сборки
RUN echo "=== FINAL BUILD CHECK ===" && \
    ls -la *.dmb *.rsc 2>/dev/null || echo "Build files check failed" && \
    if [ -f "tgstation.dmb" ]; then \
        echo "SUCCESS: Build completed" && \
        ls -lh tgstation.dmb; \
    else \
        echo "ERROR: Build failed" && \
        exit 1; \
    fi

# Открываем порты
EXPOSE 1337

# Создаем startup скрипт
RUN echo '#!/bin/bash' > /app/start_server.sh && \
    echo 'echo "=== SS13 SERVER STARTUP ==="' >> /app/start_server.sh && \
    echo 'echo "Current directory: $(pwd)"' >> /app/start_server.sh && \
    echo 'echo "Available files:"' >> /app/start_server.sh && \
    echo 'ls -la' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Проверяем наличие dmb файла' >> /app/start_server.sh && \
    echo 'if [ ! -f "tgstation.dmb" ]; then' >> /app/start_server.sh && \
    echo '    echo "ERROR: tgstation.dmb not found"' >> /app/start_server.sh && \
    echo '    echo "Available files:"' >> /app/start_server.sh && \
    echo '    ls -la' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Ищем dreamdaemon' >> /app/start_server.sh && \
    echo 'DAEMON_PATH=$(find /usr/local -name "dreamdaemon" -type f 2>/dev/null | head -1)' >> /app/start_server.sh && \
    echo 'if [ -z "$DAEMON_PATH" ]; then' >> /app/start_server.sh && \
    echo '    echo "ERROR: dreamdaemon not found"' >> /app/start_server.sh && \
    echo '    find /usr/local -name "*daemon*" 2>/dev/null' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'echo "Found dreamdaemon: $DAEMON_PATH"' >> /app/start_server.sh && \
    echo 'echo "Starting SS13 server on port 1337..."' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Запускаем сервер' >> /app/start_server.sh && \
    echo 'exec "$DAEMON_PATH" tgstation.dmb -port 1337 -trusted -verbose' >> /app/start_server.sh && \
    chmod +x /app/start_server.sh

# Команда запуска
CMD ["/app/start_server.sh"]]
