#!/usr/bin/env bash

###############################################################################
# SIMPLE SAFE BACKUP ENGINE (Solaris 11 / Linux)
###############################################################################

CONFIG_FILE="./backup.conf"

# -------------------------
# LOAD CONFIG
# -------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config not found: $CONFIG_FILE"
    exit 1
fi

. "$CONFIG_FILE"

###############################################################################
# GLOBALS
###############################################################################

DATE_NOW=$(date '+%Y%m%d_%H%M%S')
HOSTNAME_SHORT=$(hostname | awk -F. '{print $1}')

TMP_PATH="${TMP_PATH:-/tmp/backup_tmp}"
LOG_DIR="$LOG_PATH_ROOT"
GLOBAL_LOG="${LOG_DIR}/${HOSTNAME_SHORT}_${PARENT_JOB_NAME}_${DATE_NOW}.log"

TOTAL_ERRORS=0

mkdir -p "$TMP_PATH"
mkdir -p "$LOG_DIR"

###############################################################################
# LOG
###############################################################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$GLOBAL_LOG"
}

###############################################################################
# MAIN LOOP
###############################################################################

log "BACKUP START"

for JOB in $JOBS
do
    echo "================ JOB: $JOB ================"

    SRC=$(eval echo "\${${JOB}_SOURCE}")
    DST=$(eval echo "\${${JOB}_LOCAL_DEST}")
    RMT=$(eval echo "\${${JOB}_REMOTE_DEST}")
    MODE=$(eval echo "\${${JOB}_MODE}")
    PATTERN=$(eval echo "\${${JOB}_ARCHIVE_PATTERN}")

    mkdir -p "$DST"
    [ -n "$RMT" ] && mkdir -p "$RMT"

    # ---------------------------------------------------------
    # STEP 1: BUILD LIST
    # ---------------------------------------------------------
    LIST="${TMP_PATH}/${JOB}.lst"
    > "$LIST"

    case "$MODE" in
        archive_all)
            find "$SRC" -type f > "$LIST"
        ;;
        *)
            find "$SRC" -type f > "$LIST"
        ;;
    esac

    if [ ! -s "$LIST" ]; then
        log "ERROR: empty file list for $JOB"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        continue
    fi

    # ---------------------------------------------------------
    # STEP 2: CREATE TAR
    # ---------------------------------------------------------
    KEY=$(date '+%Y%m%d_%H%M%S')
    NAME=$(echo "$PATTERN" | \
        sed "s/{PCName}/$HOSTNAME_SHORT/g" | \
        sed "s/{JobName}/$JOB/g" | \
        sed "s/{DATE}/$KEY/g")

    TAR_FILE="${DST}/${NAME}.tar"

    tar -cf "$TAR_FILE" -T "$LIST"
    if [ $? -ne 0 ] || [ ! -f "$TAR_FILE" ]; then
        log "ERROR TAR FAILED $JOB"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        continue
    fi

    # VERIFY TAR
    tar -tf "$TAR_FILE" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR TAR CORRUPTED $JOB"
        rm -f "$TAR_FILE"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        continue
    fi

    # ---------------------------------------------------------
    # STEP 3: GZIP
    # ---------------------------------------------------------
    gzip -f "$TAR_FILE"
    if [ $? -ne 0 ]; then
        log "ERROR GZIP FAILED $JOB"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        continue
    fi

    GZ_FILE="${TAR_FILE}.gz"

    # VERIFY GZIP
    gzip -t "$GZ_FILE" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR GZIP CORRUPTED $JOB"
        rm -f "$GZ_FILE"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        continue
    fi

    # ---------------------------------------------------------
    # STEP 4: COPY + VERIFY
    # ---------------------------------------------------------
    if [ -n "$RMT" ]; then

        cp "$GZ_FILE" "$RMT/"
        if [ $? -ne 0 ]; then
            log "ERROR COPY FAILED $JOB"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            continue
        fi

        REMOTE_FILE="${RMT}/$(basename "$GZ_FILE")"

        if [ ! -f "$REMOTE_FILE" ]; then
            log "ERROR COPY NOT FOUND $JOB"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            continue
        fi

        # SIZE CHECK
        SRC_SIZE=$(wc -c < "$GZ_FILE")
        DST_SIZE=$(wc -c < "$REMOTE_FILE")

        if [ "$SRC_SIZE" -ne "$DST_SIZE" ]; then
            log "ERROR SIZE MISMATCH $JOB"
            rm -f "$REMOTE_FILE"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            continue
        fi

        # SHA256 CHECK (Solaris 11 native)
        SRC_HASH=$(digest -a sha256 "$GZ_FILE" 2>/dev/null)
        DST_HASH=$(digest -a sha256 "$REMOTE_FILE" 2>/dev/null)

        # FALLBACK (old Solaris):
        # SRC_HASH=$(cksum "$GZ_FILE" | awk '{print $1}')
        # DST_HASH=$(cksum "$REMOTE_FILE" | awk '{print $1}')

        if [ "$SRC_HASH" != "$DST_HASH" ]; then
            log "ERROR DIGEST MISMATCH $JOB"
            rm -f "$REMOTE_FILE"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            continue
        fi

    fi

    # ---------------------------------------------------------
    # STEP 5: DELETE SOURCE (ONLY AFTER SUCCESS)
    # ---------------------------------------------------------
    rm -f "$LIST"

    if [ -d "$SRC" ]; then
        find "$SRC" -type f -exec rm -f {} \;
    fi

    log "OK JOB $JOB ARCHIVE=$GZ_FILE"

done

###############################################################################
# SUMMARY
###############################################################################

echo "TOTAL ERRORS: $TOTAL_ERRORS"
log "TOTAL ERRORS: $TOTAL_ERRORS"

exit "$TOTAL_ERRORS"