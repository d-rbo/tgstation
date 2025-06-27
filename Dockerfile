# Простой Dockerfile для SS13 на Railway
FROM ubuntu:22.04

# Установка базовых зависимостей
RUN apt-get update && apt-get install -y \
    unzip \
    lib32gcc-s1 \
    lib32stdc++6 \
    libc6-i386 \
    make \
    python3 \
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

# Компиляция проекта - используем прямую компиляцию вместо BUILD.cmd
RUN if [ -f "tools/build/build" ]; then \
        chmod +x tools/build/build && ./tools/build/build; \
    elif [ -f "tools/build/build.py" ]; then \
        python3 tools/build/build.py; \
    else \
        /usr/local/byond/bin/dm tgstation.dme; \
    fi

# Запуск сервера
ENTRYPOINT ["/usr/local/byond/bin/DreamDaemon", "tgstation.dmb", "-port", "1337", "-trusted", "-close"]
EXPOSE 1337
