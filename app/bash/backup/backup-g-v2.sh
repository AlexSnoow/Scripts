#!/usr/bin/env bash

###############################################################################
# SIMPLE SAFE BACKUP ENGINE (Solaris / Linux)
###############################################################################

CONFIG_FILE="./backup.conf"

[ ! -f "$CONFIG_FILE" ] && echo "CONFIG NOT FOUND" && exit 1

. "$CONFIG_FILE"

###############################################################################
# GLOBALS
###############################################################################

DATE_NOW=$(date '+%Y%m%d_%H%M%S')
HOSTNAME_SHORT=$(hostname | awk -F. '{print $1}')

TMP_PATH="${TMP_PATH:-/tmp/backup_tmp}"
mkdir -p "$TMP_PATH"
mkdir -p "$LOG_PATH_ROOT"

GLOBAL_LOG="${LOG_PATH_ROOT}/${HOSTNAME_SHORT}_${PARENT_JOB_NAME}_${DATE_NOW}.log"

TOTAL_ERRORS=0

###############################################################################
# LOGGING
###############################################################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" >> "$GLOBAL_LOG"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >> "$GLOBAL_LOG"
}

###############################################################################
# CONFIG ACCESS
###############################################################################

get_job_var() {
    job="$1"
    var="$2"
    eval "echo \${${job}_${var}}"
}

###############################################################################
# NAME BUILDER
###############################################################################

resolve_name() {
    echo "$1" | sed \
        -e "s/{PCName}/$2/g" \
        -e "s/{JobName}/$3/g" \
        -e "s/{DATE}/$4/g" \
        -e "s/{SourceFileName}/$5/g" \
        -e "s/{SourceFolderName}/$5/g"
}

###############################################################################
# ARCHIVE ENGINE (SAFE tar.gz)
###############################################################################

create_archive() {
    archive="$1"
    listfile="$2"

    [ ! -f "$listfile" ] && return 1

    tar -cf "${archive}.tar" -T "$listfile"
    rc=$?

    [ "$rc" -ne 0 ] && return "$rc"

    gzip -f "${archive}.tar"
}

###############################################################################
# CLEAN OLD FILES
###############################################################################

remove_old_files() {
    path="$1"
    days="$2"

    [ -z "$path" ] && return
    [ -z "$days" ] && return
    [ ! -d "$path" ] && return

    find "$path" -type f -mtime +"$days" -exec rm -f {} \;
}

###############################################################################
# COPY REMOTE
###############################################################################

copy_remote() {
    src="$1"
    dst="$2"

    [ -z "$dst" ] && return 0

    mkdir -p "$dst" 2>/dev/null

    if [ ! -f "$src.gz" ]; then
        log_error "REMOTE COPY FAILED: source not found $src.gz"
        return 1
    fi

    cp "$src.gz" "$dst/"
    rc=$?

    if [ "$rc" -ne 0 ]; then
        log_error "REMOTE COPY FAILED: cp error $src.gz"
        return 1
    fi

    # -------------------------
    # CHECK 1: file exists
    # -------------------------
    if [ ! -f "$dst/$(basename "$src.gz")" ]; then
        log_error "REMOTE COPY FAILED: file not present in destination"
        return 1
    fi

    # -------------------------
    # CHECK 2: size compare
    # -------------------------
    src_size=$(wc -c < "$src.gz" 2>/dev/null)
    dst_size=$(wc -c < "$dst/$(basename "$src.gz")" 2>/dev/null)

    if [ "$src_size" != "$dst_size" ]; then
        log_error "REMOTE COPY FAILED: size mismatch ($src_size != $dst_size)"
        return 1
    fi

    log "REMOTE COPY OK: $(basename "$src.gz")"
    return 0
}

###############################################################################
# STEP 1: PREPARE
###############################################################################

prepare_list() {

    JOB="$1"
    SRC="$2"
    MODE="$3"
    FILTER="$4"

    [ -z "$FILTER" ] && FILTER="*"

    case "$MODE" in

        archive_all|archive_by_date)
            find "$SRC" -type f
        ;;

        individual_files)
            find "$SRC" -type f -name "$FILTER"
        ;;

        individual_folders)
            find "$SRC" -mindepth 1 -maxdepth 1 -type d
        ;;

        *)
            log_error "UNKNOWN MODE: $MODE"
            return 1
        ;;
    esac
}

###############################################################################
# STEP 2–4 PIPELINE EXECUTION
###############################################################################

process_job() {

    JOB="$1"

    MODE=$(get_job_var "$JOB" "MODE")
    SRC=$(get_job_var "$JOB" "SOURCE")
    DST=$(get_job_var "$JOB" "LOCAL_DEST")
    FILTER=$(get_job_var "$JOB" "SOURCE_FILTER")
    PATTERN=$(get_job_var "$JOB" "ARCHIVE_PATTERN")
    REMOTE=$(get_job_var "$JOB" "REMOTE_DEST")
    DAYS=$(get_job_var "$JOB" "LOCAL_DAYS_OLD")

    echo "JOB: $JOB"

    [ ! -d "$SRC" ] && log_error "SOURCE NOT FOUND $SRC" && TOTAL_ERRORS=$((TOTAL_ERRORS+1)) && return

    mkdir -p "$DST"

    PLAN="${TMP_PATH}/${JOB}_${$}.lst"

    prepare_list "$JOB" "$SRC" "$MODE" "$FILTER" > "$PLAN"

    while IFS= read -r ITEM
    do
        [ -z "$ITEM" ] && continue

        KEY=$(date '+%Y%m%d_%H%M%S')
        BASE=$(basename "$ITEM")

        NAME=$(resolve_name "$PATTERN" "$HOSTNAME_SHORT" "$JOB" "$KEY" "$BASE")

        ARCHIVE="${DST}/${NAME}"
        LIST="${TMP_PATH}/${JOB}_${BASE}_${$}.lst"

        echo "$ITEM" > "$LIST"

        create_archive "$ARCHIVE" "$LIST"
        rc=$?

        if [ "$rc" -ne 0 ]; then
            log_error "FAIL $ITEM"
            TOTAL_ERRORS=$((TOTAL_ERRORS+1))
        else
            log "OK $ITEM"
            copy_remote "$ARCHIVE" "$REMOTE"
        fi

    done < "$PLAN"

    remove_old_files "$DST" "$DAYS"

    log "JOB END $JOB"
}

###############################################################################
# MAIN
###############################################################################

log "BACKUP START"

if [ "$1" = "--test" ]; then
    echo "TEST MODE NOT IMPLEMENTED IN SIMPLE VERSION"
    exit 0
fi

for JOB in $JOBS
do
    process_job "$JOB"
done

log "TOTAL ERRORS: $TOTAL_ERRORS"
echo "TOTAL ERRORS: $TOTAL_ERRORS"

exit "$TOTAL_ERRORS"