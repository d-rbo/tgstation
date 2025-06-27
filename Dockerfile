# Простой Dockerfile для SS13 на Railway
FROM ubuntu:22.04

# Установка базовых зависимостей
RUN apt-get update && apt-get install -y \
    unzip \
    lib32gcc-s1 \
    lib32stdc++6 \
    libc6-i386 \
    make \
    && rm -rf /var/lib/apt/lists/*

# Копируем BYOND из локальной папки
COPY BYOND/ /usr/local/byond/

# Добавляем в PATH
ENV PATH="/usr/local/byond/bin:${PATH}"

# Устанавливаем BYOND (если нужна установка)
RUN cd /usr/local/byond && make install

# Копирование кода игры
WORKDIR /tgstation
COPY . .

# Компиляция проекта
RUN chmod +x BUILD.cmd && ./BUILD.cmd

# Запуск сервера
ENTRYPOINT ["/usr/local/byond/bin/DreamDaemon", "tgstation.dmb", "-port", "1337", "-trusted", "-close"]
EXPOSE 1337
