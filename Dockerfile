# Исправленная версия вашего оригинального Dockerfile для Railway
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
RUN echo "=== INSTALLING WINE (minimal) ===" && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends wine wine32 xvfb && \
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

# Настраиваем переменные окружения для Railway
ENV PATH="/usr/local/bin:${PATH}"
ENV WINEDLLOVERRIDES="mscoree,mshtml="
ENV DISPLAY=:99
ENV PORT=1337

# НАСТРОЙКА WINE И СОЗДАНИЕ WRAPPER'ов (исправленная версия для Railway)
RUN echo "=== SETTING UP WINE WRAPPERS ===" && \
    export WINEDLLOVERRIDES="mscoree,mshtml=" && \
    export DISPLAY=:99 && \
    # Инициализируем wine в фоновом режиме
    Xvfb :99 -screen 0 1024x768x16 & \
    sleep 2 && \
    wineboot --init 2>/dev/null || true && \
    sleep 3 && \
    pkill Xvfb || true && \
    # Создаем wrapper для dm.exe (исправленный для Railway)
    echo '#!/bin/bash' > /usr/local/bin/dm && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /usr/local/bin/dm && \
    echo 'export DISPLAY=:99' >> /usr/local/bin/dm && \
    echo '# Запускаем Xvfb в фоне если нужно' >> /usr/local/bin/dm && \
    echo 'if ! pgrep Xvfb > /dev/null; then' >> /usr/local/bin/dm && \
    echo '    Xvfb :99 -screen 0 1024x768x16 & sleep 2' >> /usr/local/bin/dm && \
    echo 'fi' >> /usr/local/bin/dm && \
    echo 'wine /usr/local/byond/bin/dm.exe "$@" 2>/dev/null' >> /usr/local/bin/dm && \
    chmod +x /usr/local/bin/dm && \
    # Создаем wrapper для dreamdaemon.exe (исправленный для Railway)
    echo '#!/bin/bash' > /usr/local/bin/dreamdaemon && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /usr/local/bin/dreamdaemon && \
    echo 'export DISPLAY=:99' >> /usr/local/bin/dreamdaemon && \
    echo '# Запускаем Xvfb в фоне если нужно' >> /usr/local/bin/dreamdaemon && \
    echo 'if ! pgrep Xvfb > /dev/null; then' >> /usr/local/bin/dreamdaemon && \
    echo '    Xvfb :99 -screen 0 1024x768x16 & sleep 2' >> /usr/local/bin/dreamdaemon && \
    echo 'fi' >> /usr/local/bin/dreamdaemon && \
    echo 'wine /usr/local/byond/bin/dreamdaemon.exe "$@" 2>/dev/null' >> /usr/local/bin/dreamdaemon && \
    chmod +x /usr/local/bin/dreamdaemon && \
    ln -sf /usr/local/bin/dm /usr/local/bin/DreamMaker && \
    ln -sf /usr/local/bin/dreamdaemon /usr/local/bin/DreamDaemon && \
    # Очищаем временные файлы wine
    rm -rf /root/.wine/drive_c/windows/Installer/* || true

# Копируем остальной код проекта
COPY . .

# СБОРКА TGUI И DM (в одном слое для экономии места)
RUN echo "=== BUILDING PROJECT ===" && \
    export PATH="/usr/local/byond/bin:$PATH" && \
    # Запускаем Xvfb для сборки
    Xvfb :99 -screen 0 1024x768x16 & \
    sleep 2 && \
    # Собираем TGUI
    echo "Building TGUI..." && \
    node tools/build/build.js tgui --skip-icon-cutter && \
    # Собираем DM
    echo "Building DM..." && \
    node tools/build/build.js dm --skip-icon-cutter && \
    # Останавливаем Xvfb
    pkill Xvfb || true && \
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

# Открываем порт (Railway автоматически назначит переменную PORT)
EXPOSE $PORT

# Создаем Railway-совместимый startup скрипт
RUN echo '#!/bin/bash' > /app/start_server.sh && \
    echo 'set -e' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'echo "🚀 Starting SS13 TGStation Server"' >> /app/start_server.sh && \
    echo 'echo "=================================="' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Railway переменные' >> /app/start_server.sh && \
    echo 'export PORT=${PORT:-1337}' >> /app/start_server.sh && \
    echo 'export DISPLAY=:99' >> /app/start_server.sh && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Проверяем файлы' >> /app/start_server.sh && \
    echo 'if [ ! -f "tgstation.dmb" ]; then' >> /app/start_server.sh && \
    echo '    echo "❌ ERROR: tgstation.dmb not found"' >> /app/start_server.sh && \
    echo '    ls -la' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'echo "✅ Found tgstation.dmb"' >> /app/start_server.sh && \
    echo 'ls -lh tgstation.dmb' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Очищаем старые X-серверы и блокировки' >> /app/start_server.sh && \
    echo 'echo "🧹 Cleaning up old X servers..."' >> /app/start_server.sh && \
    echo 'pkill Xvfb || true' >> /app/start_server.sh && \
    echo 'rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 || true' >> /app/start_server.sh && \
    echo 'sleep 1' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Запускаем виртуальный дисплей' >> /app/start_server.sh && \
    echo 'echo "🖥️  Starting virtual display..."' >> /app/start_server.sh && \
    echo 'Xvfb :99 -screen 0 1024x768x16 -ac &' >> /app/start_server.sh && \
    echo 'XVFB_PID=$!' >> /app/start_server.sh && \
    echo 'sleep 3' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Проверяем что X-сервер запустился' >> /app/start_server.sh && \
    echo 'if ! pgrep Xvfb > /dev/null; then' >> /app/start_server.sh && \
    echo '    echo "❌ ERROR: Failed to start Xvfb"' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo 'echo "✅ Virtual display started (PID: $XVFB_PID)"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Ищем DreamDaemon' >> /app/start_server.sh && \
    echo 'DAEMON_PATH=$(find /usr/local -name "dreamdaemon" -type f 2>/dev/null | head -1)' >> /app/start_server.sh && \
    echo 'if [ -z "$DAEMON_PATH" ]; then' >> /app/start_server.sh && \
    echo '    echo "❌ ERROR: dreamdaemon not found"' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'echo "🎮 Starting SS13 server on port $PORT..."' >> /app/start_server.sh && \
    echo 'echo "🔧 Using DreamDaemon: $DAEMON_PATH"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Создаем директории для логов' >> /app/start_server.sh && \
    echo 'mkdir -p /app/data/logs' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Функция очистки при завершении' >> /app/start_server.sh && \
    echo 'cleanup() {' >> /app/start_server.sh && \
    echo '    echo "🛑 Shutting down..."' >> /app/start_server.sh && \
    echo '    kill $XVFB_PID 2>/dev/null || true' >> /app/start_server.sh && \
    echo '    exit 0' >> /app/start_server.sh && \
    echo '}' >> /app/start_server.sh && \
    echo 'trap cleanup SIGTERM SIGINT' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Запускаем сервер' >> /app/start_server.sh && \
    echo 'echo "🚀 Launching DreamDaemon..."' >> /app/start_server.sh && \
    echo 'exec "$DAEMON_PATH" tgstation.dmb -port $PORT -trusted -verbose' >> /app/start_server.sh && \
    chmod +x /app/start_server.sh

# Команда запуска
CMD ["/app/start_server.sh"]
