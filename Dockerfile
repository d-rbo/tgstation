# Используем более новый образ с Node.js 18
FROM node:18-bullseye

# Устанавливаем системные зависимости
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    libssl1.1 \
    gcc \
    g++ \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем весь проект
COPY . .

# Диагностика структуры BYOND папки
RUN echo "=== BYOND DIRECTORY STRUCTURE ===" && \
    if [ -d "BYOND" ]; then \
        echo "BYOND directory exists" && \
        find BYOND -type f -name "*" | head -20 && \
        echo "--- Full BYOND structure ---" && \
        ls -la BYOND/ && \
        if [ -d "BYOND/byond" ]; then \
            echo "Found BYOND/byond subdirectory" && \
            ls -la BYOND/byond/; \
        fi; \
    else \
        echo "BYOND directory not found"; \
    fi

# Устанавливаем BYOND с правильной логикой
RUN echo "=== INSTALLING BYOND ===" && \
    if [ -d "BYOND" ]; then \
        echo "Found local BYOND directory" && \
        if [ -d "BYOND/byond" ]; then \
            echo "Installing from BYOND/byond/" && \
            cp -r BYOND/byond /usr/local/byond; \
        elif [ -d "BYOND/bin" ]; then \
            echo "Installing from BYOND/ (direct structure)" && \
            mkdir -p /usr/local/byond && \
            cp -r BYOND/* /usr/local/byond/; \
        else \
            echo "Installing from BYOND/ (copying all)" && \
            cp -r BYOND /usr/local/byond; \
        fi && \
        echo "Making binaries executable..." && \
        find /usr/local/byond -name "dm" -type f -exec chmod +x {} \; && \
        find /usr/local/byond -name "dreamdaemon" -type f -exec chmod +x {} \; && \
        find /usr/local/byond -name "DreamMaker" -type f -exec chmod +x {} \; && \
        find /usr/local/byond -type f -executable -exec chmod +x {} \; && \
        echo "BYOND installed from local directory"; \
    else \
        echo "No local BYOND found, downloading..." && \
        wget -O byond.zip "http://www.byond.com/download/build/515/515.1637_byond_linux.zip" && \
        unzip -q byond.zip && \
        mv byond /usr/local/byond && \
        find /usr/local/byond -type f -executable -exec chmod +x {} \; && \
        rm byond.zip && \
        echo "BYOND downloaded and installed"; \
    fi

# Диагностика установки BYOND
RUN echo "=== BYOND INSTALLATION CHECK ===" && \
    find /usr/local/byond -name "dm" -type f 2>/dev/null || echo "dm not found" && \
    find /usr/local/byond -name "dreamdaemon" -type f 2>/dev/null || echo "dreamdaemon not found" && \
    ls -la /usr/local/byond/bin/ 2>/dev/null || echo "No /usr/local/byond/bin directory"

# Проверяем установку BYOND
RUN echo "=== BYOND VERSION ===" && \
    find /usr/local -name "dm" -type f -exec {} -version \; 2>/dev/null || echo "DM not working"

# Проверяем Node.js версию
RUN echo "=== NODE.JS VERSION ===" && node --version

# Выводим содержимое tools директории для отладки
RUN echo "=== TOOLS DIRECTORY ===" && ls -la tools/ 2>/dev/null || echo "No tools directory"
RUN echo "=== TOOLS/BUILD DIRECTORY ===" && ls -la tools/build/ 2>/dev/null || echo "No tools/build directory"
RUN echo "=== TOOLS/BOOTSTRAP DIRECTORY ===" && ls -la tools/bootstrap/ 2>/dev/null || echo "No tools/bootstrap directory"

# Исправляем синтаксис JavaScript для совместимости
RUN if [ -f "tools/build/lib/byond.js" ]; then \
        echo "=== FIXING JAVASCRIPT SYNTAX ===" && \
        sed -i 's/?? \[\]/|| []/g' tools/build/lib/byond.js && \
        sed -i 's/?? /|| /g' tools/build/lib/byond.js && \
        echo "JavaScript syntax fixed"; \
    fi

# Выполняем сборку проекта
RUN if [ -f "tools/bootstrap/javascript" ]; then \
        echo "=== FOUND: tools/bootstrap/javascript ===" && \
        chmod +x tools/bootstrap/javascript && \
        echo "Executing: tools/bootstrap/javascript tools/build/build.js" && \
        tools/bootstrap/javascript tools/build/build.js 2>&1 || echo "ERROR in bootstrap/javascript"; \
    elif [ -f "tools/build/build.js" ]; then \
        echo "=== FOUND: tools/build/build.js ===" && \
        echo "Executing: node tools/build/build.js" && \
        node tools/build/build.js 2>&1 || echo "ERROR in build.js"; \
    elif [ -f "tools/build/build" ]; then \
        echo "=== FOUND: tools/build/build ===" && \
        chmod +x tools/build/build && \
        echo "Executing: tools/build/build" && \
        tools/build/build 2>&1 || echo "ERROR in build script"; \
    else \
        echo "=== NO BUILD SCRIPTS FOUND, USING DM FALLBACK ===" && \
        echo "Looking for dm binary..." && \
        DM_PATH=$(find /usr/local -name "dm" -type f 2>/dev/null | head -1) && \
        if [ -n "$DM_PATH" ]; then \
            echo "Found dm at: $DM_PATH" && \
            echo "Executing: $DM_PATH tgstation.dme" && \
            $DM_PATH tgstation.dme 2>&1 || echo "ERROR in dm compilation"; \
        else \
            echo "ERROR: dm binary not found anywhere"; \
        fi; \
    fi

# Проверяем результат сборки
RUN echo "=== BUILD RESULTS ===" && \
    ls -la *.dmb 2>/dev/null || echo "No .dmb files found" && \
    ls -la *.rsc 2>/dev/null || echo "No .rsc files found"

# Настраиваем переменные окружения
ENV PATH="/usr/local/byond/bin:${PATH}"

# Открываем порты
EXPOSE 1337

# Команда запуска с детальной диагностикой
CMD ["sh", "-c", "echo '=== SS13 SERVER STARTUP DIAGNOSTICS ===' && echo 'Current directory:' && pwd && echo 'Available files:' && ls -la && echo 'Looking for .dmb files:' && ls -la *.dmb 2>/dev/null || echo 'No .dmb files found' && echo 'Looking for dreamdaemon:' && find /usr/local -name 'dreamdaemon' -type f 2>/dev/null || echo 'dreamdaemon not found' && echo 'Environment PATH:' && echo $PATH && if [ -f 'tgstation.dmb' ]; then echo '=== STARTING SERVER ===' && DAEMON_PATH=$(find /usr/local -name 'dreamdaemon' -type f 2>/dev/null | head -1) && if [ -n \"$DAEMON_PATH\" ]; then echo \"Using dreamdaemon: $DAEMON_PATH\" && echo \"Starting with command: $DAEMON_PATH tgstation.dmb -port 1337 -trusted -verbose\" && $DAEMON_PATH tgstation.dmb -port 1337 -trusted -verbose 2>&1; else echo 'ERROR: dreamdaemon binary not found' && find /usr/local -type f -name '*daemon*' 2>/dev/null && exit 1; fi; else echo 'ERROR: tgstation.dmb not found - build failed' && echo 'Available files:' && ls -la && exit 1; fi"]
