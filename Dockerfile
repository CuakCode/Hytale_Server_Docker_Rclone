FROM docker.io/eclipse-temurin:25-jre-alpine
RUN apk add --no-cache gcompat libstdc++ rclone util-linux procps
WORKDIR /app
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
WORKDIR /data
EXPOSE 5520/udp
ENV RAM_MAX="4G"
ENTRYPOINT ["/entrypoint.sh"]
