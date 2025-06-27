# Простой Dockerfile для SS13 на Railway
FROM ubuntu:22.04

# Установка базовых зависимостей
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    lib32gcc-s1 \
    lib32stdc++6 \
    libc6-i386 \
    && rm -rf /var/lib/apt/lists/*

# Скачивание и установка BYOND
ENV BYOND_MAJOR=515
ENV BYOND_MINOR=1637
WORKDIR /byond
RUN wget "http://www.byond.com/download/build/${BYOND_MAJOR}/${BYOND_MAJOR}.${BYOND_MINOR}_byond_linux.zip" -O byond.zip \
    && unzip byond.zip \
    && cd byond \
    && make install \
    && cd .. \
    && rm -rf byond byond.zip

# Копирование кода игры
WORKDIR /tgstation
COPY . .

# Компиляция проекта (упрощенная)
RUN env DM_EXE=/usr/local/byond/bin/dm DreamMaker tgstation.dme

# Запуск сервера
ENTRYPOINT ["/usr/local/byond/bin/DreamDaemon", "tgstation.dmb", "-port", "1337", "-trusted", "-close"]
EXPOSE 1337
