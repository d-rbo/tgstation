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

# ПРАВИЛЬНАЯ УСТАНОВКА BYOND ДЛЯ LINUX
RUN echo "=== INSTALLING BYOND ===" && \
    if [ -d "BYOND" ] && [ -f "BYOND/bin/dm" ]; then \
        echo "Found local Linux BYOND directory" && \
        if [ -d "BYOND/byond" ]; then \
            cp -r BYOND/byond /usr/local/byond; \
        elif [ -d "BYOND/bin" ]; then \
            mkdir -p /usr/local/byond && \
            cp -r BYOND/* /usr/local/byond/; \
        else \
            cp -r BYOND /usr/local/byond; \
        fi && \
        find /usr/local/byond -type f -exec chmod +x {} \; && \
        echo "BYOND installed from local directory"; \
    else \
        echo "Downloading BYOND Linux version (local appears to be Windows)..." && \
        wget -O byond.zip "http://www.byond.com/download/build/515/515.1637_byond_linux.zip" && \
        unzip -q byond.zip && \
        mv byond /usr/local/byond && \
        find /usr/local/byond -type f -exec chmod +x {} \; && \
        rm byond.zip && \
        echo "BYOND downloaded and installed"; \
    fi

# Проверяем установку BYOND (Linux файлы БЕЗ .exe)
RUN echo "=== BYOND CHECK ===" && \
    echo "Looking for Linux BYOND binaries:" && \
    find /usr/local/byond -name "dm" -type f && \
    find /usr/local/byond -name "dreamdaemon" -type f && \
    echo "BYOND directory contents:" && \
    ls -la /usr/local/byond/bin/

# Настраиваем переменные окружения
ENV PATH="/usr/local/byond/bin:${PATH}"

# ИСПРАВЛЯЕМ BYOND для работы с TG build system (Linux версия)
RUN echo "=== FIXING BYOND FOR TG BUILD SYSTEM ===" && \
    # Создаем симлинк DreamMaker -> dm для совместимости (БЕЗ .exe!)
    ln -sf /usr/local/byond/bin/dm /usr/local/byond/bin/DreamMaker && \
    # Проверяем что все файлы на месте
    echo "BYOND executables:" && \
    ls -la /usr/local/byond/bin/ && \
    echo "Testing DM compiler:" && \
    /usr/local/byond/bin/dm --version 2>&1 || echo "DM version check completed"

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
CMD ["/app/start_server.sh"]
