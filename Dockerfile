# Исправленная версия Dockerfile для Railway
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

# Устанавливаем Node.js 18
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем только необходимые файлы сначала
COPY package*.json ./
COPY tools/ ./tools/
COPY tgui/ ./tgui/

# Install bun (required for tgui build)
RUN curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    rm -rf /root/.bun/install/cache

# УСТАНОВКА WINE и необходимых библиотек
RUN echo "=== INSTALLING WINE and dependencies ===" && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine \
        wine32 \
        xvfb \
        winetricks \
        cabextract \
        wget \
    && rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Копируем BYOND только после установки wine
COPY BYOND/ /usr/local/byond/

# Настройка BYOND
RUN if [ -d "/usr/local/byond" ]; then \
        find /usr/local/byond -type f -name "*.exe" -exec chmod +x {} \; && \
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


# Альтернативный способ установки vcredist (добавьте после установки wine)
RUN echo "=== MANUAL VCREDIST INSTALLATION ===" && \
    export WINEDLLOVERRIDES="mscoree,mshtml=" && \
    export DISPLAY=:99 && \
    # Запускаем X-сервер
    Xvfb :99 -screen 0 1024x768x16 & \
    sleep 2 && \
    wineboot --init 2>/dev/null || true && \
    sleep 3 && \
    # Скачиваем и устанавливаем vcredist вручную
    cd /tmp && \
    wget -q https://aka.ms/vs/17/release/vc_redist.x86.exe -O vcredist_x86.exe && \
    wget -q https://aka.ms/vs/17/release/vc_redist.x64.exe -O vcredist_x64.exe && \
    # Устанавливаем x86 версию (тихая установка)
    wine vcredist_x86.exe /quiet /norestart || echo "x86 vcredist failed" && \
    sleep 5 && \
    # Устанавливаем x64 версию
    wine vcredist_x64.exe /quiet /norestart || echo "x64 vcredist failed" && \
    sleep 5 && \
    # Очищаем
    rm -f vcredist_*.exe && \
    pkill Xvfb || true && \
    # Проверяем что библиотеки установились
    find /root/.wine -name "*mfc140*" -type f || echo "mfc140 not found after
    
# НАСТРОЙКА WINE И СОЗДАНИЕ WRAPPER'ов
RUN echo "=== SETTING UP WINE WRAPPERS ===" && \
    export WINEDLLOVERRIDES="mscoree,mshtml=" && \
    export DISPLAY=:99 && \
    # Инициализируем wine в фоновом режиме
    Xvfb :99 -screen 0 1024x768x16 & \
    sleep 2 && \
    wineboot --init 2>/dev/null || true && \
    sleep 3 && \
    pkill Xvfb || true && \
    # Создаем wrapper для dm.exe
    echo '#!/bin/bash' > /usr/local/bin/dm && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /usr/local/bin/dm && \
    echo 'export DISPLAY=:99' >> /usr/local/bin/dm && \
    echo 'if ! pgrep Xvfb > /dev/null; then' >> /usr/local/bin/dm && \
    echo '    Xvfb :99 -screen 0 1024x768x16 & sleep 2' >> /usr/local/bin/dm && \
    echo 'fi' >> /usr/local/bin/dm && \
    echo 'wine /usr/local/byond/bin/dm.exe "$@" 2>/dev/null' >> /usr/local/bin/dm && \
    chmod +x /usr/local/bin/dm && \
    # Создаем wrapper для dreamdaemon.exe (ИСПРАВЛЕННЫЙ)
    echo '#!/bin/bash' > /usr/local/bin/dreamdaemon && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /usr/local/bin/dreamdaemon && \
    echo 'export DISPLAY=:99' >> /usr/local/bin/dreamdaemon && \
    echo 'if ! pgrep Xvfb > /dev/null; then' >> /usr/local/bin/dreamdaemon && \
    echo '    Xvfb :99 -screen 0 1024x768x16 & sleep 2' >> /usr/local/bin/dreamdaemon && \
    echo 'fi' >> /usr/local/bin/dreamdaemon && \
    echo '# Логируем все выходы для отладки' >> /usr/local/bin/dreamdaemon && \
    echo 'echo "DreamDaemon wrapper called with: $*"' >> /usr/local/bin/dreamdaemon && \
    echo 'wine /usr/local/byond/bin/dreamdaemon.exe "$@"' >> /usr/local/bin/dreamdaemon && \
    chmod +x /usr/local/bin/dreamdaemon && \
    ln -sf /usr/local/bin/dm /usr/local/bin/DreamMaker && \
    ln -sf /usr/local/bin/dreamdaemon /usr/local/bin/DreamDaemon && \
    rm -rf /root/.wine/drive_c/windows/Installer/* || true

# Копируем остальной код проекта
COPY . .

# СБОРКА TGUI И DM
RUN echo "=== BUILDING PROJECT ===" && \
    export PATH="/usr/local/byond/bin:$PATH" && \
    Xvfb :99 -screen 0 1024x768x16 & \
    sleep 2 && \
    echo "Building TGUI..." && \
    node tools/build/build.js tgui --skip-icon-cutter && \
    echo "Building DM..." && \
    node tools/build/build.js dm --skip-icon-cutter && \
    pkill Xvfb || true && \
    rm -rf node_modules/.cache && \
    rm -rf /tmp/* && \
    if [ -f "tgstation.dmb" ]; then \
        echo "SUCCESS: Build completed" && \
        ls -lh tgstation.dmb; \
    else \
        echo "ERROR: Build failed" && \
        exit 1; \
    fi

# Удаляем ненужные файлы после сборки
RUN echo "=== CLEANUP ===" && \
    find . -name "*.dm" -not -path "./maps/*" -delete 2>/dev/null || true && \
    find . -name "*.dmi" -delete 2>/dev/null || true && \
    rm -rf tools/build && \
    rm -rf tgui/packages && \
    rm -rf /root/.npm && \
    rm -rf /root/.cache && \
    rm -rf /var/cache/* && \
    rm -rf /usr/share/doc && \
    rm -rf /usr/share/man && \
    find /usr -name "*.a" -delete 2>/dev/null || true

# Открываем порт
EXPOSE $PORT

# Создаем ИСПРАВЛЕННЫЙ startup скрипт
RUN echo '#!/bin/bash' > /app/start_server.sh && \
    echo 'set -e' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'echo "🚀 Starting SS13 TGStation Server (FIXED VERSION)"' >> /app/start_server.sh && \
    echo 'echo "======================================================="' >> /app/start_server.sh && \
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
    echo '# Очищаем старые X-серверы' >> /app/start_server.sh && \
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
    echo '# Проверяем DreamDaemon' >> /app/start_server.sh && \
    echo 'echo "🔍 Checking DreamDaemon..."' >> /app/start_server.sh && \
    echo 'if [ ! -f "/usr/local/bin/dreamdaemon" ]; then' >> /app/start_server.sh && \
    echo '    echo "❌ ERROR: dreamdaemon wrapper not found"' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'if [ ! -f "/usr/local/byond/bin/dreamdaemon.exe" ]; then' >> /app/start_server.sh && \
    echo '    echo "❌ ERROR: dreamdaemon.exe not found"' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Создаем директории для логов' >> /app/start_server.sh && \
    echo 'mkdir -p /app/data/logs' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Тестируем DreamDaemon с версией' >> /app/start_server.sh && \
    echo 'echo "🧪 Testing DreamDaemon..."' >> /app/start_server.sh && \
    echo 'timeout 10s /usr/local/bin/dreamdaemon -version || echo "Version check failed/timed out"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Функция очистки при завершении' >> /app/start_server.sh && \
    echo 'cleanup() {' >> /app/start_server.sh && \
    echo '    echo "🛑 Shutting down server..."' >> /app/start_server.sh && \
    echo '    kill $XVFB_PID 2>/dev/null || true' >> /app/start_server.sh && \
    echo '    # Убиваем все wine процессы' >> /app/start_server.sh && \
    echo '    pkill wine || true' >> /app/start_server.sh && \
    echo '    exit 0' >> /app/start_server.sh && \
    echo '}' >> /app/start_server.sh && \
    echo 'trap cleanup SIGTERM SIGINT EXIT' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Запускаем сервер с подробными логами' >> /app/start_server.sh && \
    echo 'echo "🎮 Starting SS13 server on port $PORT..."' >> /app/start_server.sh && \
    echo 'echo "🔧 DMB file: $(pwd)/tgstation.dmb"' >> /app/start_server.sh && \
    echo 'echo "🔧 DreamDaemon wrapper: /usr/local/bin/dreamdaemon"' >> /app/start_server.sh && \
    echo 'echo "🔧 DreamDaemon exe: /usr/local/byond/bin/dreamdaemon.exe"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Запускаем с максимальными логами и без exec (чтобы поймать ошибки)' >> /app/start_server.sh && \
    echo 'echo "🚀 Launching DreamDaemon with full logging..."' >> /app/start_server.sh && \
    echo 'echo "Command: /usr/local/bin/dreamdaemon tgstation.dmb -port $PORT -trusted -verbose"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Запускаем и ждем, чтобы увидеть что происходит' >> /app/start_server.sh && \
    echo '/usr/local/bin/dreamdaemon tgstation.dmb -port $PORT -trusted -verbose &' >> /app/start_server.sh && \
    echo 'DAEMON_PID=$!' >> /app/start_server.sh && \
    echo 'echo "🎯 DreamDaemon started with PID: $DAEMON_PID"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Ждем и проверяем статус' >> /app/start_server.sh && \
    echo 'sleep 10' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'if kill -0 $DAEMON_PID 2>/dev/null; then' >> /app/start_server.sh && \
    echo '    echo "✅ DreamDaemon is running! Waiting indefinitely..."' >> /app/start_server.sh && \
    echo '    wait $DAEMON_PID' >> /app/start_server.sh && \
    echo 'else' >> /app/start_server.sh && \
    echo '    echo "❌ DreamDaemon crashed or exited early!"' >> /app/start_server.sh && \
    echo '    echo "Checking wine processes:"' >> /app/start_server.sh && \
    echo '    ps aux | grep wine || echo "No wine processes"' >> /app/start_server.sh && \
    echo '    echo "Checking for log files:"' >> /app/start_server.sh && \
    echo '    find /app -name "*.log" -exec ls -la {} \; || echo "No log files found"' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    chmod +x /app/start_server.sh

# Команда запуска
CMD ["/app/start_server.sh"]
