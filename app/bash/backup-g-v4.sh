#!/usr/bin/env bash

###############################################################################
# SAFE BACKUP ENGINE (Solaris 11 / Linux)
# PIPELINE: LIST -> TAR -> VERIFY TAR -> GZIP -> VERIFY GZIP -> COPY -> VERIFY -> CLEANUP
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
# SAFE NAME RESOLVE
###############################################################################

resolve_name() {
    pattern="$1"
    pc="$2"
    job="$3"
    date="$4"
    name="$5"

    echo "$pattern" | \
        sed "s/{PCName}/$pc/g" | \
        sed "s/{JobName}/$job/g" | \
        sed "s/{DATE}/$date/g" | \
        sed "s/{LastWriteTime}/$date/g" | \
        sed "s/{SourceFileName}/$name/g" | \
        sed "s/{SourceFolderName}/$name/g"
}

###############################################################################
# COPY WITH VERIFICATION + SAFE OVERWRITE PROTECTION
###############################################################################

copy_remote() {
    src="$1"
    dst_dir="$2"

    [ -z "$dst_dir" ] && return 0

    mkdir -p "$dst_dir" 2>/dev/null

    base=$(basename "$src")
    dst="$dst_dir/$base"

    # anti overwrite
    if [ -f "$dst" ]; then
        i=1
        name="${base%.*}"
        ext="${base##*.}"

        # handle .tar.gz
        if echo "$base" | grep -q "\.tar\.gz$"; then
            name=$(echo "$base" | sed 's/\.tar\.gz$//')
            ext="tar.gz"
        fi

        while [ -f "$dst_dir/${name}_${i}.${ext}" ]; do
            i=$((i+1))
        done

        dst="$dst_dir/${name}_${i}.${ext}"
    fi

    # atomic copy
    cp "$src" "$dst.tmp"
    if [ $? -ne 0 ]; then
        log "ERROR COPY FAILED $src"
        rm -f "$dst.tmp"
        return 1
    fi

    mv "$dst.tmp" "$dst"

    # verify size
    src_size=$(wc -c < "$src")
    dst_size=$(wc -c < "$dst")

    if [ "$src_size" -ne "$dst_size" ]; then
        log "ERROR SIZE MISMATCH $src"
        rm -f "$dst"
        return 1
    fi

    # verify digest (Solaris 11 / Linux optional)
    if command -v digest >/dev/null 2>&1; then
        src_hash=$(digest -a sha256 "$src" 2>/dev/null)
        dst_hash=$(digest -a sha256 "$dst" 2>/dev/null)
    else
        src_hash=""
        dst_hash=""
    fi

    if [ -n "$src_hash" ] && [ -n "$dst_hash" ]; then
        if [ "$src_hash" != "$dst_hash" ]; then
            log "ERROR DIGEST MISMATCH $src"
            rm -f "$dst"
            return 1
        fi
    fi

    log "OK COPY VERIFIED $dst"
    return 0
}

###############################################################################
# ARCHIVE PIPELINE
###############################################################################

process_job() {

    JOB="$1"

    SRC=$(eval echo "\${${JOB}_SOURCE}")
    DST=$(eval echo "\${${JOB}_LOCAL_DEST}")
    RMT=$(eval echo "\${${JOB}_REMOTE_DEST}")
    MODE=$(eval echo "\${${JOB}_MODE}")
    PATTERN=$(eval echo "\${${JOB}_ARCHIVE_PATTERN}")

    JOB_OK=1

    mkdir -p "$DST"
    [ -n "$RMT" ] && mkdir -p "$RMT"

    LIST="${TMP_PATH}/${JOB}_$$.lst"
    > "$LIST"

    # -------------------------
    # STEP 1: LIST FILES
    # -------------------------
    find "$SRC" -type f | sort > "$LIST"

    if [ ! -s "$LIST" ]; then
        log "ERROR EMPTY LIST $JOB"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return
    fi

    # -------------------------
    # STEP 2: TAR
    # -------------------------
    KEY=$(date '+%Y%m%d_%H%M%S')
    NAME=$(resolve_name "$PATTERN" "$HOSTNAME_SHORT" "$JOB" "$KEY" "$KEY")

    TAR_FILE="${DST}/${NAME}.tar"

    tar -cf "$TAR_FILE" -T "$LIST"
    if [ $? -ne 0 ] || [ ! -f "$TAR_FILE" ]; then
        log "ERROR TAR FAIL $JOB"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        rm -f "$LIST"
        return
    fi

    tar -tf "$TAR_FILE" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR TAR CORRUPTED $JOB"
        rm -f "$TAR_FILE" "$LIST"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return
    fi

    # -------------------------
    # STEP 3: GZIP
    # -------------------------
    gzip -f "$TAR_FILE"
    if [ $? -ne 0 ]; then
        log "ERROR GZIP FAIL $JOB"
        rm -f "$LIST"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return
    fi

    GZ_FILE="${TAR_FILE}.gz"

    gzip -t "$GZ_FILE" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR GZIP CORRUPTED $JOB"
        rm -f "$GZ_FILE" "$LIST"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return
    fi

    # -------------------------
    # STEP 4: COPY REMOTE
    # -------------------------
    if [ -n "$RMT" ]; then
        copy_remote "$GZ_FILE" "$RMT"
        if [ $? -ne 0 ]; then
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            JOB_OK=0
        fi
    fi

    # -------------------------
    # STEP 5: CLEANUP SOURCE ONLY IF SUCCESS
    # -------------------------
    if [ "$JOB_OK" -eq 1 ]; then
        find "$SRC" -type f -exec rm -f {} \;
        log "OK JOB COMPLETE $JOB $GZ_FILE"
    else
        log "WARN JOB PARTIAL $JOB"
    fi

    rm -f "$LIST"
}

###############################################################################
# MAIN
###############################################################################

log "BACKUP START"

for JOB in $JOBS
do
    echo "================ JOB: $JOB ================"
    process_job "$JOB"
done

###############################################################################
# SUMMARY
###############################################################################

echo "TOTAL ERRORS: $TOTAL_ERRORS"
log "TOTAL ERRORS: $TOTAL_ERRORS"

exit "$TOTAL_ERRORS"