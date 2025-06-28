# Оптимизированная версия Dockerfile для Railway с фиксом mfc140u.dll и оптимизацией памяти
# Используем альтернативные источники образов для надежности
FROM --platform=linux/amd64 debian:bullseye-slim

# Альтернативные варианты базового образа (раскомментируйте нужный):
# FROM --platform=linux/amd64 ubuntu:22.04
# FROM --platform=linux/amd64 registry.gitlab.com/nvidia/container-images/ubuntu:22.04
# FROM --platform=linux/amd64 public.ecr.aws/ubuntu/ubuntu:22.04

# Предотвращаем интерактивные запросы
ENV DEBIAN_FRONTEND=noninteractive

# Добавляем альтернативные репозитории для надежности
RUN echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bullseye-updates main" >> /etc/apt/sources.list

# Устанавливаем только необходимые системные зависимости в одном слое
RUN apt-get update --fix-missing && apt-get install -y --no-install-recommends \
    wget \
    unzip \
    curl \
    gcc \
    g++ \
    libc6-dev \
    libssl1.1 \
    python3 \
    python3-pip \
    git \
    make \
    pkg-config \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && rm -rf /tmp/* /var/tmp/*

# Устанавливаем Node.js 18 (используем альтернативный источник)
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

# Install bun (required for tgui build) - оптимизированная установка
RUN curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    rm -rf /root/.bun/install/cache

# УСТАНОВКА WINE и необходимых библиотек (оптимизированная)
RUN echo "=== INSTALLING WINE and dependencies ===" && \
    dpkg --add-architecture i386 && \
    wget -nc https://dl.winehq.org/wine-builds/winehq.key && \
    apt-key add winehq.key && \
    echo "deb https://dl.winehq.org/wine-builds/debian/ bullseye main" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        winehq-stable \
        xvfb \
        winetricks \
        cabextract \
        p7zip-full \
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
ENV WINEPREFIX=/root/.wine
    
# КРИТИЧЕСКИЙ ФИКС: Правильная установка Visual C++ библиотек
RUN echo "=== SETTING UP WINE AND VISUAL C++ LIBRARIES ===" && \
    export WINEDLLOVERRIDES="mscoree,mshtml=" && \
    export DISPLAY=:99 && \
    export WINEPREFIX=/root/.wine && \
    # Запускаем виртуальный дисплей
    Xvfb :99 -screen 0 1024x768x16 -ac & \
    sleep 3 && \
    # Инициализируем wine
    echo "Initializing wine..." && \
    wineboot --init && \
    sleep 5 && \
    # Скачиваем Visual C++ Redistributable 2015-2019 с альтернативных источников
    echo "Downloading Visual C++ Redistributable..." && \
    (wget -q -O /tmp/vc_redist.x86.exe "https://aka.ms/vs/16/release/vc_redist.x86.exe" || \
     wget -q -O /tmp/vc_redist.x86.exe "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe") && \
    (wget -q -O /tmp/vc_redist.x64.exe "https://aka.ms/vs/16/release/vc_redist.x64.exe" || \
     wget -q -O /tmp/vc_redist.x64.exe "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe") && \
    # Устанавливаем VC++ Redistributable в тихом режиме
    echo "Installing Visual C++ Redistributable x86..." && \
    wine /tmp/vc_redist.x86.exe /quiet /norestart && \
    sleep 10 && \
    echo "Installing Visual C++ Redistributable x64..." && \
    wine /tmp/vc_redist.x64.exe /quiet /norestart && \
    sleep 10 && \
    # Дополнительно устанавливаем через winetricks как fallback
    echo "Installing additional components via winetricks..." && \
    winetricks --unattended vcrun2019 mfc140 && \
    sleep 5 && \
    # Проверяем что библиотеки установились
    echo "Checking installed DLLs..." && \
    ls -la /root/.wine/drive_c/windows/system32/ | grep -E "(mfc140|vcruntime)" && \
    ls -la /root/.wine/drive_c/windows/syswow64/ | grep -E "(mfc140|vcruntime)" && \
    # Очистка
    rm -f /tmp/vc_redist.* && \
    pkill Xvfb || true && \
    sleep 1

# СОЗДАНИЕ WRAPPER'ов
RUN echo "=== CREATING WRAPPERS ===" && \
    # Создаем wrapper для dm.exe
    echo '#!/bin/bash' > /usr/local/bin/dm && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /usr/local/bin/dm && \
    echo 'export DISPLAY=:99' >> /usr/local/bin/dm && \
    echo 'export WINEPREFIX=/root/.wine' >> /usr/local/bin/dm && \
    echo 'if ! pgrep Xvfb > /dev/null; then' >> /usr/local/bin/dm && \
    echo '    Xvfb :99 -screen 0 1024x768x16 -ac & sleep 2' >> /usr/local/bin/dm && \
    echo 'fi' >> /usr/local/bin/dm && \
    echo 'wine /usr/local/byond/bin/dm.exe "$@" 2>/dev/null' >> /usr/local/bin/dm && \
    chmod +x /usr/local/bin/dm && \
    # Создаем wrapper для dreamdaemon.exe с улучшенной диагностикой
    echo '#!/bin/bash' > /usr/local/bin/dreamdaemon && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /usr/local/bin/dreamdaemon && \
    echo 'export DISPLAY=:99' >> /usr/local/bin/dreamdaemon && \
    echo 'export WINEPREFIX=/root/.wine' >> /usr/local/bin/dreamdaemon && \
    echo 'if ! pgrep Xvfb > /dev/null; then' >> /usr/local/bin/dreamdaemon && \
    echo '    Xvfb :99 -screen 0 1024x768x16 -ac & sleep 3' >> /usr/local/bin/dreamdaemon && \
    echo 'fi' >> /usr/local/bin/dreamdaemon && \
    echo '# Логируем все выходы для отладки' >> /usr/local/bin/dreamdaemon && \
    echo 'echo "DreamDaemon wrapper called with: $*"' >> /usr/local/bin/dreamdaemon && \
    echo '# Проверяем наличие необходимых DLL перед запуском' >> /usr/local/bin/dreamdaemon && \
    echo 'echo "Checking required DLLs..."' >> /usr/local/bin/dreamdaemon && \
    echo 'find /root/.wine -name "mfc140u.dll" -exec ls -la {} \;' >> /usr/local/bin/dreamdaemon && \
    echo 'find /root/.wine -name "vcruntime140.dll" -exec ls -la {} \;' >> /usr/local/bin/dreamdaemon && \
    echo 'wine /usr/local/byond/bin/dreamdaemon.exe "$@"' >> /usr/local/bin/dreamdaemon && \
    chmod +x /usr/local/bin/dreamdaemon && \
    ln -sf /usr/local/bin/dm /usr/local/bin/DreamMaker && \
    ln -sf /usr/local/bin/dreamdaemon /usr/local/bin/DreamDaemon

# Копируем остальной код проекта
COPY . .

# СБОРКА TGUI И DM (оптимизированная для малой памяти)
RUN echo "=== BUILDING PROJECT ===" && \
    export PATH="/usr/local/byond/bin:$PATH" && \
    export WINEPREFIX=/root/.wine && \
    export NODE_OPTIONS="--max-old-space-size=2048" && \
    Xvfb :99 -screen 0 1024x768x16 -ac & \
    sleep 3 && \
    echo "Building TGUI..." && \
    node tools/build/build.js tgui --skip-icon-cutter && \
    # Очищаем кеш после TGUI сборки
    rm -rf node_modules/.cache /tmp/* && \
    echo "Building DM..." && \
    node tools/build/build.js dm --skip-icon-cutter && \
    pkill Xvfb || true && \
    # Финальная очистка
    rm -rf node_modules/.cache /root/.npm /root/.cache /tmp/* && \
    if [ -f "tgstation.dmb" ]; then \
        echo "SUCCESS: Build completed" && \
        ls -lh tgstation.dmb; \
    else \
        echo "ERROR: Build failed" && \
        exit 1; \
    fi

# Агрессивная очистка для экономии места
RUN echo "=== AGGRESSIVE CLEANUP ===" && \
    find . -name "*.dm" -not -path "./maps/*" -delete 2>/dev/null || true && \
    find . -name "*.dmi" -delete 2>/dev/null || true && \
    rm -rf tools/build && \
    rm -rf tgui/packages && \
    rm -rf /root/.npm && \
    rm -rf /root/.cache && \
    rm -rf /root/.bun/install/cache && \
    rm -rf /var/cache/* && \
    rm -rf /usr/share/doc && \
    rm -rf /usr/share/man && \
    rm -rf /usr/share/locale && \
    find /usr -name "*.a" -delete 2>/dev/null || true && \
    # Очищаем wine кеш но оставляем DLLs
    rm -rf /root/.wine/drive_c/users/root/Temp/* && \
    rm -rf /root/.wine/drive_c/windows/Temp/* && \
    apt-get autoremove -y && \
    apt-get autoclean

# Открываем порт
EXPOSE $PORT

# Создаем улучшенный startup скрипт с проверкой библиотек
RUN echo '#!/bin/bash' > /app/start_server.sh && \
    echo 'set -e' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'echo "🚀 Starting SS13 TGStation Server (FIXED VCREDIST VERSION)"' >> /app/start_server.sh && \
    echo 'echo "======================================================="' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Railway переменные' >> /app/start_server.sh && \
    echo 'export PORT=${PORT:-1337}' >> /app/start_server.sh && \
    echo 'export DISPLAY=:99' >> /app/start_server.sh && \
    echo 'export WINEDLLOVERRIDES="mscoree,mshtml="' >> /app/start_server.sh && \
    echo 'export WINEPREFIX=/root/.wine' >> /app/start_server.sh && \
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
    echo '# КРИТИЧЕСКАЯ ПРОВЕРКА Visual C++ библиотек' >> /app/start_server.sh && \
    echo 'echo "🔍 Checking Visual C++ libraries..."' >> /app/start_server.sh && \
    echo 'MFC140_FOUND=false' >> /app/start_server.sh && \
    echo 'VCRUN_FOUND=false' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'if find /root/.wine -name "mfc140u.dll" | grep -q .; then' >> /app/start_server.sh && \
    echo '    echo "✅ mfc140u.dll found:"' >> /app/start_server.sh && \
    echo '    find /root/.wine -name "mfc140u.dll" -exec ls -la {} \;' >> /app/start_server.sh && \
    echo '    MFC140_FOUND=true' >> /app/start_server.sh && \
    echo 'else' >> /app/start_server.sh && \
    echo '    echo "❌ mfc140u.dll NOT FOUND - attempting emergency fix"' >> /app/start_server.sh && \
    echo '    # Попытка экстренного восстановления через альтернативные источники' >> /app/start_server.sh && \
    echo '    (wget -q -O /tmp/emergency_mfc140u.dll "https://files.000webhost.com/files/279990/mfc140u.dll" || \\' >> /app/start_server.sh && \
    echo '     curl -L -o /tmp/emergency_mfc140u.dll "https://github.com/nalexandru/api-ms-win-core-path-HACK/raw/master/dll/mfc140u.dll" || \\' >> /app/start_server.sh && \
    echo '     echo "All emergency sources failed") && \\' >> /app/start_server.sh && \
    echo '    if [ -f "/tmp/emergency_mfc140u.dll" ]; then' >> /app/start_server.sh && \
    echo '        cp /tmp/emergency_mfc140u.dll /root/.wine/drive_c/windows/system32/mfc140u.dll' >> /app/start_server.sh && \
    echo '        cp /tmp/emergency_mfc140u.dll /root/.wine/drive_c/windows/syswow64/mfc140u.dll' >> /app/start_server.sh && \
    echo '        echo "⚡ Emergency mfc140u.dll installed"' >> /app/start_server.sh && \
    echo '        MFC140_FOUND=true' >> /app/start_server.sh && \
    echo '    fi' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'if find /root/.wine -name "vcruntime140.dll" | grep -q .; then' >> /app/start_server.sh && \
    echo '    echo "✅ vcruntime140.dll found:"' >> /app/start_server.sh && \
    echo '    find /root/.wine -name "vcruntime140.dll" -exec ls -la {} \;' >> /app/start_server.sh && \
    echo '    VCRUN_FOUND=true' >> /app/start_server.sh && \
    echo 'else' >> /app/start_server.sh && \
    echo '    echo "❌ vcruntime140.dll NOT FOUND"' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'if [ "$MFC140_FOUND" = false ] || [ "$VCRUN_FOUND" = false ]; then' >> /app/start_server.sh && \
    echo '    echo "❌ CRITICAL: Required Visual C++ libraries missing!"' >> /app/start_server.sh && \
    echo '    echo "This will cause DreamDaemon to fail. Check build process."' >> /app/start_server.sh && \
    echo '    # Не выходим, попробуем запустить всё равно' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
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
    echo 'sleep 5' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Проверяем что X-сервер запустился' >> /app/start_server.sh && \
    echo 'if ! pgrep Xvfb > /dev/null; then' >> /app/start_server.sh && \
    echo '    echo "❌ ERROR: Failed to start Xvfb"' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    echo 'echo "✅ Virtual display started (PID: $XVFB_PID)"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Создаем директории для логов' >> /app/start_server.sh && \
    echo 'mkdir -p /app/data/logs' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Функция очистки при завершении' >> /app/start_server.sh && \
    echo 'cleanup() {' >> /app/start_server.sh && \
    echo '    echo "🛑 Shutting down server..."' >> /app/start_server.sh && \
    echo '    kill $XVFB_PID 2>/dev/null || true' >> /app/start_server.sh && \
    echo '    pkill wine || true' >> /app/start_server.sh && \
    echo '    exit 0' >> /app/start_server.sh && \
    echo '}' >> /app/start_server.sh && \
    echo 'trap cleanup SIGTERM SIGINT EXIT' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Запускаем сервер' >> /app/start_server.sh && \
    echo 'echo "🎮 Starting SS13 server on port $PORT..."' >> /app/start_server.sh && \
    echo 'echo "🔧 Command: /usr/local/bin/dreamdaemon tgstation.dmb -port $PORT -trusted -verbose"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '/usr/local/bin/dreamdaemon tgstation.dmb -port $PORT -trusted -verbose &' >> /app/start_server.sh && \
    echo 'DAEMON_PID=$!' >> /app/start_server.sh && \
    echo 'echo "🎯 DreamDaemon started with PID: $DAEMON_PID"' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo '# Ждем и проверяем статус' >> /app/start_server.sh && \
    echo 'sleep 15' >> /app/start_server.sh && \
    echo '' >> /app/start_server.sh && \
    echo 'if kill -0 $DAEMON_PID 2>/dev/null; then' >> /app/start_server.sh && \
    echo '    echo "✅ DreamDaemon is running! Server accessible on port $PORT"' >> /app/start_server.sh && \
    echo '    wait $DAEMON_PID' >> /app/start_server.sh && \
    echo 'else' >> /app/start_server.sh && \
    echo '    echo "❌ DreamDaemon crashed or exited!"' >> /app/start_server.sh && \
    echo '    ps aux | grep wine || echo "No wine processes"' >> /app/start_server.sh && \
    echo '    find /app -name "*.log" -exec ls -la {} \; || echo "No logs"' >> /app/start_server.sh && \
    echo '    exit 1' >> /app/start_server.sh && \
    echo 'fi' >> /app/start_server.sh && \
    chmod +x /app/start_server.sh

# Команда запуска
CMD ["/app/start_server.sh"]
