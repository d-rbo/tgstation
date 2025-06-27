# Простой Dockerfile для SS13 на Railway
FROM ubuntu:22.04

# Установка базовых зависимостей + Node.js для JavaScript
RUN apt-get update && apt-get install -y \
    unzip \
    lib32gcc-s1 \
    lib32stdc++6 \
    libc6-i386 \
    make \
    python3 \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Копируем BYOND из локальной папки
COPY BYOND/ /usr/local/byond/

# Добавляем в PATH
ENV PATH="/usr/local/byond/bin:${PATH}"

# Даем права на выполнение для BYOND
RUN chmod +x /usr/local/byond/bin/*

# Копирование кода игры
WORKDIR /tgstation
COPY . .

# Проверяем структуру и запускаем правильную сборку
RUN ls -la tools/build/ && ls -la tools/bootstrap/ 2>/dev/null || echo "No bootstrap directory"

# Сборка через JavaScript (аналог build.bat)
RUN if [ -f "tools/bootstrap/javascript" ]; then \
        echo "Using Linux bootstrap" && chmod +x tools/bootstrap/javascript && tools/bootstrap/javascript tools/build/build.js; \
    elif [ -f "tools/build/build.js" ]; then \
        echo "Running build.js directly with node" && node tools/build/build.js; \
    elif [ -f "tools/build/build" ]; then \
        echo "Using Linux build script" && chmod +x tools/build/build && tools/build/build; \
    else \
        echo "Fallback to dm compilation" && /usr/local/byond/bin/dm tgstation.dme; \
    fi

# Запуск сервера
ENTRYPOINT ["/usr/local/byond/bin/DreamDaemon", "tgstation.dmb", "-port", "1337", "-trusted", "-close"]
EXPOSE 1337
