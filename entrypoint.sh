#!/bin/sh

# Configuración
RCLONE_REMOTE="${RCLONE_REMOTE:-myremote}"
RCLONE_BUCKET="${RCLONE_PATH:-hytale/universe}"
PIPE_INPUT="/tmp/hytale_input"

echo "--- 🚀 Iniciando Wrapper de Hytale (Modo: Spy & Secure Backup) ---"

# 1. RESTAURAR BACKUP
if [ -f "/config/rclone.conf" ]; then
    echo "📥 [Rclone] Restaurando..."
    # Usamos --update para no sobreescribir archivos locales si son más nuevos
    rclone copy "$RCLONE_REMOTE:$RCLONE_BUCKET" /data/universe \
        --config /config/rclone.conf \
        --transfers=4 \
        --checkers=8 \
        --update \
        -v \
        --stats 5s
fi

# Variables globales
child=""
monitor_pid=""
spy_pid=""

# Función de apagado (CORREGIDA PARA EVITAR BLOQUEOS)
shutdown_handler() {
    echo "🛑 [System] Señal de parada recibida."
    
    # 1. Matar monitores primero
    if [ -n "$monitor_pid" ]; then kill "$monitor_pid" 2>/dev/null; fi
    if [ -n "$spy_pid" ]; then kill "$spy_pid" 2>/dev/null; fi

    # 2. Cerrar Java y ESPERAR a que muera
    if [ -n "$child" ]; then
        echo "stop" > "$PIPE_INPUT" 2>/dev/null
        kill -TERM "$child" 2>/dev/null
        
        echo "⏳ Esperando cierre total de Java..."
        i=0
        # Esperamos hasta 30 segundos
        while kill -0 "$child" 2>/dev/null && [ $i -lt 30 ]; do
            sleep 1
            i=$((i + 1))
        done

        # Si sigue vivo, forzamos cierre
        if kill -0 "$child" 2>/dev/null; then
            echo "💀 Forzando cierre (kill -9)..."
            kill -9 "$child" 2>/dev/null
        else
            echo "✅ Servidor cerrado correctamente."
        fi
        
        # PAUSA DE SEGURIDAD: Vital para que el disco libere el 'lock' de los archivos
        sleep 2
    fi
    
    # 3. SUBIR BACKUP (Ahora es seguro porque Java ya no existe)
    if [ -f "/config/rclone.conf" ]; then
        echo "📤 [Rclone] Guardando backup..."
        # --ignore-errors evita que se trabe si falla un archivo temporal
        rclone copy /data/universe "$RCLONE_REMOTE:$RCLONE_BUCKET" \
            --config /config/rclone.conf \
            -v \
            --stats 5s \
            --ignore-errors
        echo "✅ [Rclone] Backup finalizado."
    fi
    exit 0
}

trap "shutdown_handler" SIGTERM SIGINT

# Preparar tubería
rm -f "$PIPE_INPUT"
mkfifo "$PIPE_INPUT"
sleep infinity > "$PIPE_INPUT" & 

echo "🎮 [Hytale] Iniciando servidor..."

# --- EJECUCIÓN LIMPIA (SIN REDIRECCIONES) ---
# Al no poner '>' ni '|', Java detecta una terminal real (TTY).
# Esto soluciona el problema del "Modo Debug" y el chat roto.
java -Xmx${RAM_MAX} -XX:AOTCache=/app/HytaleServer.aot -jar /app/HytaleServer.jar --assets /app/Assets.zip --bind 0.0.0.0:5520 < "$PIPE_INPUT" &
child=$!
echo "✅ Java iniciado con PID: $child"

# Esperamos un momento para que el sistema de archivos proc se inicie para este proceso
sleep 2

# --- MONITORIZACIÓN "ESPÍA" (/proc) + LOG DE JUEGO ---
# 1. Buscamos el log normal para el chat y eventos del juego
logfile=$(find . -name "*.log" -type f -mmin -1 2>/dev/null | head -n 1)

# 2. Definimos qué vigilar.
# Vigilar el log del juego (si existe) Y ADEMÁS espiar el canal de error (fd/2) del proceso.
# Esto captura los crashes de Java sin necesidad de redirigir la salida.
FILES_TO_WATCH="/proc/$child/fd/2"
if [ -n "$logfile" ]; then
    echo "✅ Monitorizando Log de juego: $logfile y STDERR directo."
    FILES_TO_WATCH="$logfile /proc/$child/fd/2"
else
    echo "⚠️ Log de juego no encontrado aún, monitorizando solo STDERR (/proc)."
fi

# Usamos tail -F para seguir ambos flujos
(tail -F -q $FILES_TO_WATCH 2>/dev/null | while read -r line; do
    
    # Ignorar comandos propios
    if echo "$line" | grep -q "Console executed command"; then continue; fi

    # Si detectamos un crash de Java (que sale por /proc/.../fd/2), lo mostramos en docker logs
    if echo "$line" | grep -iqE "Exception|at |Caused by|STDERR"; then
        echo "🔥 [CRASH TRACE] $line"
    fi
    
    # Lógica de Errores (Conteo y Reinicio)
    if echo "$line" | grep -iqE "java.lang|exception|throwable"; then
        count=$(cat /tmp/error_count 2>/dev/null || echo 0)
        count=$((count + 1))
        echo "$count" > /tmp/error_count
        
        # Avisar al juego
        echo "say ⚠️ Error detectado ($count)" > "$PIPE_INPUT"
        
        if [ "$count" -ge 10 ] && [ ! -f "/tmp/reboot_pending" ]; then
            echo "say 🚨 Límite de errores. Reinicio en 60s." > "$PIPE_INPUT"
            touch "/tmp/reboot_pending"
            (
                sleep 60
                if [ -f "/tmp/reboot_pending" ]; then
                    echo "say 💀 Reiniciando..." > "$PIPE_INPUT"
                    sleep 2
                    echo "stop" > "$PIPE_INPUT"
                fi
            ) &
        fi
    fi
    
    # Lógica Aborto
    if echo "$line" | grep -iq "aborto"; then
        if [ -f "/tmp/reboot_pending" ]; then
            echo "say 🛑 REINICIO CANCELADO." > "$PIPE_INPUT"
            rm -f "/tmp/reboot_pending"
            pkill -f "sleep 60"
        fi
    fi
done) &
monitor_pid=$!

# Bucle interactivo
echo "✅ Consola lista."
while kill -0 "$child" 2>/dev/null; do
    if read -r -t 0.5 cmd; then
        echo "$cmd" > "$PIPE_INPUT"
    fi
done

shutdown_handler
