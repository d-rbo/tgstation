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

# Устанавливаем BYOND из локальной папки
RUN echo "=== INSTALLING BYOND ===" && \
    if [ -d "BYOND" ]; then \
        echo "Found local BYOND directory" && \
        cp -r BYOND/* /usr/local/ && \
        chmod +x /usr/local/byond/bin/* && \
        echo "BYOND installed from local directory"; \
    else \
        echo "No local BYOND found, downloading..." && \
        wget -O byond.zip "http://www.byond.com/download/build/515/515.1637_byond_linux.zip" && \
        unzip -q byond.zip && \
        mv byond /usr/local/byond && \
        chmod +x /usr/local/byond/bin/* && \
        rm byond.zip && \
        echo "BYOND downloaded and installed"; \
    fi

# Проверяем установку BYOND
RUN echo "=== BYOND VERSION ===" && \
    /usr/local/byond/bin/dm -version 2>/dev/null || echo "DM not found"

# Проверяем Node.js версию
RUN echo "=== NODE.JS VERSION ===" && node --version

# Выводим содержимое tools директории для отладки
RUN echo "=== TOOLS DIRECTORY ===" && ls -la tools/ 2>/dev/null || echo "No tools directory"
RUN echo "=== TOOLS/BUILD DIRECTORY ===" && ls -la tools/build/ 2>/dev/null || echo "No tools/build directory"
RUN echo "=== TOOLS/BOOTSTRAP DIRECTORY ===" && ls -la tools/bootstrap/ 2>/dev/null || echo "No tools/bootstrap directory"

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
        echo "Executing: /usr/local/byond/bin/dm tgstation.dme" && \
        /usr/local/byond/bin/dm tgstation.dme 2>&1 || echo "ERROR in dm compilation"; \
    fi

# Проверяем результат сборки
RUN echo "=== BUILD RESULTS ===" && \
    ls -la *.dmb 2>/dev/null || echo "No .dmb files found" && \
    ls -la *.rsc 2>/dev/null || echo "No .rsc files found"

# Настраиваем переменные окружения
ENV PATH="/usr/local/byond/bin:${PATH}"

# Открываем порты
EXPOSE 1337

# Команда запуска
CMD ["sh", "-c", "echo 'Starting SS13 server...' && if [ -f 'tgstation.dmb' ]; then echo 'Found tgstation.dmb, starting server...' && /usr/local/byond/bin/dreamdaemon tgstation.dmb -port 1337 -trusted -verbose; else echo 'ERROR: tgstation.dmb not found' && ls -la *.dmb 2>/dev/null && exit 1; fi"]
