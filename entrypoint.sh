#!/bin/sh

# Configuración
RCLONE_REMOTE="${RCLONE_REMOTE:-myremote}"
RCLONE_BUCKET="${RCLONE_PATH:-hytale/universe}"
PIPE_INPUT="/tmp/hytale_input"

# Configuración de Backups Locales Incrementales
BACKUP_ROOT="/data/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
CURRENT_STATE="$BACKUP_ROOT/current"
HISTORY_DIR="$BACKUP_ROOT/history/$TIMESTAMP"

echo "--- 🚀 Iniciando Wrapper de Hytale (Modo: Incremental Versionado) ---"

if [ -n "$HYTALE_SERVER_SESSION_TOKEN" ] && [ -n "$HYTALE_SERVER_IDENTITY_TOKEN" ]; then
    echo "🔑 [Auth] Tokens detectados en variables de entorno."
    echo "🔑 [Auth] El servidor intentará iniciar sesión automáticamente."
else
    echo "⚠️ [Auth] No se detectaron tokens en el .env."
    echo "⚠️ [Auth] El servidor iniciará en modo NO AUTENTICADO (o pedirá /auth login)."
fi

# 1. BACKUP DE SEGURIDAD INCREMENTAL (Antes de sincronizar la nube)
if [ -d "/data/universe" ]; then
    echo "📦 [Backup] Verificando cambios para backup incremental..."
    
    # Creamos estructura de carpetas
    mkdir -p "$CURRENT_STATE"
    
    # EXPLICACIÓN DEL COMANDO MÁGICO:
    # sync: Hace que 'current' sea idéntico a 'universe'.
    # --backup-dir: Antes de sobrescribir o borrar algo en 'current', mueve la versión vieja a 'history/...'.
    # Resultado: 'current' siempre tiene la última versión, 'history' tiene lo antiguo.
    rclone sync /data/universe "$CURRENT_STATE" \
        --backup-dir "$HISTORY_DIR" \
        --transfers=4 \
        --checkers=8 \
        -v \
        --stats 5s
        
    # Si se creó una carpeta de historial (hubo cambios), avisamos
    if [ -d "$HISTORY_DIR" ]; then
        echo "✅ [Backup] Cambios detectados. Versión anterior guardada en: $HISTORY_DIR"
    else
        echo "✅ [Backup] No hubo cambios locales respecto al último backup."
    fi

    # LIMPIEZA AUTOMÁTICA (Opcional)
    # Borra carpetas de historial de más de 14 días para no llenar el disco infinitamente
    echo "🧹 [Limpieza] Buscando backups antiguos (+14 días)..."
    rclone delete "$BACKUP_ROOT/history" --min-age 14d --rmdirs 2>/dev/null
fi

# 2. SINCRONIZAR DESDE LA NUBE (RESTAURAR)
if [ -f "/config/rclone.conf" ]; then
    echo "📥 [Rclone] Sincronizando cambios de la nube (Multi-PC)..."
    
    # Usamos --update para respetar archivos locales más nuevos
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

# Función de apagado
shutdown_handler() {
    echo "🛑 [System] Señal de parada recibida."
    
    if [ -n "$monitor_pid" ]; then kill "$monitor_pid" 2>/dev/null; fi
    if [ -n "$spy_pid" ]; then kill "$spy_pid" 2>/dev/null; fi

    if [ -n "$child" ]; then
        echo "stop" > "$PIPE_INPUT" 2>/dev/null
        kill -TERM "$child" 2>/dev/null
        
        echo "⏳ Esperando cierre total de Java..."
        i=0
        while kill -0 "$child" 2>/dev/null && [ $i -lt 30 ]; do
            sleep 1
            i=$((i + 1))
        done

        if kill -0 "$child" 2>/dev/null; then
            echo "💀 Forzando cierre (kill -9)..."
            kill -9 "$child" 2>/dev/null
        else
            echo "✅ Servidor cerrado correctamente."
        fi
        sleep 2
    fi
    
    # 3. SUBIR CAMBIOS A LA NUBE
    if [ -f "/config/rclone.conf" ]; then
        echo "📤 [Rclone] Subiendo cambios a la nube..."
        rclone copy /data/universe "$RCLONE_REMOTE:$RCLONE_BUCKET" \
            --config /config/rclone.conf \
            -v \
            --stats 5s \
            --update \
            --ignore-errors
        echo "✅ [Rclone] Sincronización finalizada."
    fi
    exit 0
}

trap "shutdown_handler" SIGTERM SIGINT

# Preparar tubería
rm -f "$PIPE_INPUT"
mkfifo "$PIPE_INPUT"
sleep infinity > "$PIPE_INPUT" & 

echo "🎮 [Hytale] Iniciando servidor..."

# Ejecución limpia (Sin redirecciones)
java -Xmx${RAM_MAX} -XX:AOTCache=/app/HytaleServer.aot -jar /app/HytaleServer.jar --assets /app/Assets.zip --bind 0.0.0.0:5520 < "$PIPE_INPUT" &
child=$!
echo "✅ Java iniciado con PID: $child"

sleep 2

# Monitorización Espía
logfile=$(find . -name "*.log" -type f -mmin -1 2>/dev/null | head -n 1)
FILES_TO_WATCH="/proc/$child/fd/2"

if [ -n "$logfile" ]; then
    echo "✅ Monitorizando Log: $logfile + STDERR"
    FILES_TO_WATCH="$logfile /proc/$child/fd/2"
fi

(tail -F -q $FILES_TO_WATCH 2>/dev/null | while read -r line; do
    if echo "$line" | grep -q "Console executed command"; then continue; fi

    if echo "$line" | grep -iqE "Exception|at |Caused by|STDERR"; then
        echo "🔥 [CRASH TRACE] $line"
    fi
    
    if echo "$line" | grep -iqE "java.lang|exception|throwable"; then
        count=$(cat /tmp/error_count 2>/dev/null || echo 0)
        count=$((count + 1))
        echo "$count" > /tmp/error_count
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
    
    if echo "$line" | grep -iq "aborto"; then
        if [ -f "/tmp/reboot_pending" ]; then
            echo "say 🛑 REINICIO CANCELADO." > "$PIPE_INPUT"
            rm -f "/tmp/reboot_pending"
            pkill -f "sleep 60"
        fi
    fi
done) &
monitor_pid=$!

echo "✅ Consola lista."
while kill -0 "$child" 2>/dev/null; do
    if read -r -t 0.5 cmd; then
        echo "$cmd" > "$PIPE_INPUT"
    fi
done

shutdown_handler
