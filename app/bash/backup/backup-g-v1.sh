#!/usr/bin/env bash

###############################################################################
# SIMPLE BACKUP ENGINE (Linux + Solaris 11 compatible)
###############################################################################

CONFIG_FILE="./backup.conf"

###############################################################################
# LOAD CONFIG
###############################################################################

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config not found: $CONFIG_FILE"
    exit 1
fi

# shellcheck disable=SC1090
. "$CONFIG_FILE"

###############################################################################
# GLOBAL VARIABLES
###############################################################################

DATE_NOW=$(date '+%Y%m%d_%H%M%S')
HOSTNAME_SHORT=$(hostname | awk -F. '{print $1}')

TMP_PATH="${TMP_PATH:-/tmp/backup_tmp}"
GLOBAL_LOG="${LOG_PATH_ROOT}/${HOSTNAME_SHORT}_${JOB_NAME}_${DATE_NOW}.log"

TOTAL_ERRORS=0

mkdir -p "$LOG_PATH_ROOT"
mkdir -p "$TMP_PATH"

###############################################################################
# LOG FUNCTION
###############################################################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$GLOBAL_LOG"
}

###############################################################################
# GET JOB VARIABLE
###############################################################################

get_job_var() {
    job="$1"
    var="$2"
    eval echo "\${${job}_${var}}"
}

###############################################################################
# NAME RESOLVE
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
        sed "s/{LastWriteTime}/$date/g" | \
        sed "s/{DATE}/$date/g" | \
        sed "s/{SourceFileName}/$name/g" | \
        sed "s/{SourceFolderName}/$name/g"
}

###############################################################################
# ARCHIVE (tar.gz)
###############################################################################

create_archive() {
    archive="$1"
    listfile="$2"

    if [ ! -f "$listfile" ]; then
        return 1
    fi

    tar -cf - -T "$listfile" 2>/dev/null | gzip > "$archive"
    return $?
}

###############################################################################
# COPY REMOTE
###############################################################################

copy_remote() {
    src="$1"
    dst="$2"

    if [ -z "$dst" ]; then
        return
    fi

    mkdir -p "$dst" 2>/dev/null
    cp "$src" "$dst/" 2>/dev/null
}

###############################################################################
# CLEAN OLD FILES
###############################################################################

remove_old_files() {
    path="$1"
    days="$2"

    if [ -z "$path" ]; then
        return
    fi

    if [ ! -d "$path" ]; then
        return
    fi

    find "$path" -type f -mtime +"$days" -exec rm -f {} \;
}

###############################################################################
# TEST MODE
###############################################################################

test_mode() {

    echo "TEST MODE START"

    ERRORS=0

    for JOB in $JOBS
    do
        SRC=$(get_job_var "$JOB" "SOURCE")
        DST=$(get_job_var "$JOB" "LOCAL_DEST")
        RMT=$(get_job_var "$JOB" "REMOTE_DEST")

        echo "JOB: $JOB"

        if [ ! -d "$SRC" ]; then
            echo "ERROR: SOURCE NOT FOUND $SRC"
            ERRORS=$((ERRORS + 1))
        fi

        mkdir -p "$DST" 2>/dev/null

        if [ ! -w "$DST" ]; then
            echo "ERROR: NO WRITE ACCESS $DST"
            ERRORS=$((ERRORS + 1))
        fi

        if [ -n "$RMT" ]; then
            mkdir -p "$RMT" 2>/dev/null
        fi

    done

    echo "TEST MODE ERRORS: $ERRORS"
    log "TEST MODE ERRORS: $ERRORS"

    exit "$ERRORS"
}

###############################################################################
# MODE: archive_all
###############################################################################

archive_all() {

    JOB="$1"

    SRC=$(get_job_var "$JOB" "SOURCE")
    DST=$(get_job_var "$JOB" "LOCAL_DEST")
    PATTERN=$(get_job_var "$JOB" "ARCHIVE_PATTERN")

    mkdir -p "$DST"

    LIST="${TMP_PATH}/${JOB}_all.lst"
    find "$SRC" -type f > "$LIST"

    KEY=$(date '+%Y%m%d_%H%M%S')

    NAME=$(resolve_name "$PATTERN" "$HOSTNAME_SHORT" "$JOB" "$KEY" "$KEY")
    ARCHIVE="${DST}/${NAME}"

    log "START archive_all $ARCHIVE"

    create_archive "$ARCHIVE" "$LIST"

    if [ $? -ne 0 ]; then
        echo "ERROR archive_all $JOB"
        log "FAIL archive_all $ARCHIVE"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    else
        log "OK archive_all $ARCHIVE"
        copy_remote "$ARCHIVE" "$(get_job_var "$JOB" "REMOTE_DEST")"
    fi
}

###############################################################################
# MODE: individual_files
###############################################################################

archive_individual_files() {

    JOB="$1"

    SRC=$(get_job_var "$JOB" "SOURCE")
    DST=$(get_job_var "$JOB" "LOCAL_DEST")
    FILTER=$(get_job_var "$JOB" "SOURCE_FILTER")
    PATTERN=$(get_job_var "$JOB" "ARCHIVE_PATTERN")

    mkdir -p "$DST"

    if [ -z "$FILTER" ]; then
        FILTER="*"
    fi

    find "$SRC" -type f -name "$FILTER" | while read FILE
    do
        BASE=$(basename "$FILE")

        LIST="${TMP_PATH}/${JOB}_file.lst"
        echo "$FILE" > "$LIST"

        KEY=$(date '+%Y%m%d_%H%M%S')

        NAME=$(resolve_name "$PATTERN" "$HOSTNAME_SHORT" "$JOB" "$KEY" "$BASE")
        ARCHIVE="${DST}/${NAME}"

        create_archive "$ARCHIVE" "$LIST"

        if [ $? -ne 0 ]; then
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            log "FAIL file $FILE"
        else
            log "OK file $FILE"
            copy_remote "$ARCHIVE" "$(get_job_var "$JOB" "REMOTE_DEST")"
        fi
    done
}

###############################################################################
# MODE: archive_by_date
###############################################################################

archive_by_date() {

    JOB="$1"

    SRC=$(get_job_var "$JOB" "SOURCE")
    DST=$(get_job_var "$JOB" "LOCAL_DEST")
    PATTERN=$(get_job_var "$JOB" "ARCHIVE_PATTERN")

    mkdir -p "$DST"

    LIST="${TMP_PATH}/${JOB}_date.lst"
    find "$SRC" -type f > "$LIST"

    KEY=$(date '+%Y%m%d_%H%M%S')

    NAME=$(resolve_name "$PATTERN" "$HOSTNAME_SHORT" "$JOB" "$KEY" "$KEY")
    ARCHIVE="${DST}/${NAME}"

    create_archive "$ARCHIVE" "$LIST"

    if [ $? -ne 0 ]; then
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        log "FAIL archive_by_date $JOB"
    else
        log "OK archive_by_date $JOB"
    fi
}

###############################################################################
# MODE: individual_folders
###############################################################################

archive_individual_folders() {

    JOB="$1"

    SRC=$(get_job_var "$JOB" "SOURCE")
    DST=$(get_job_var "$JOB" "LOCAL_DEST")
    PATTERN=$(get_job_var "$JOB" "ARCHIVE_PATTERN")

    mkdir -p "$DST"

    for DIR in "$SRC"/*
    do
        if [ ! -d "$DIR" ]; then
            continue
        fi

        FOLDER=$(basename "$DIR")

        LIST="${TMP_PATH}/${JOB}_${FOLDER}.lst"
        find "$DIR" -type f > "$LIST"

        KEY=$(date '+%Y%m%d_%H%M%S')

        NAME=$(resolve_name "$PATTERN" "$HOSTNAME_SHORT" "$JOB" "$KEY" "$FOLDER")
        ARCHIVE="${DST}/${NAME}"

        create_archive "$ARCHIVE" "$LIST"

        if [ $? -ne 0 ]; then
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            log "FAIL folder $FOLDER"
        else
            log "OK folder $FOLDER"
        fi
    done
}

###############################################################################
# JOB RUNNER
###############################################################################

process_job() {

    JOB="$1"
    MODE=$(get_job_var "$JOB" "MODE")

    echo "================ JOB: $JOB ================"

    case "$MODE" in
        archive_all)
            archive_all "$JOB"
            ;;
        individual_files)
            archive_individual_files "$JOB"
            ;;
        archive_by_date)
            archive_by_date "$JOB"
            ;;
        individual_folders)
            archive_individual_folders "$JOB"
            ;;
        *)
            echo "ERROR: UNKNOWN MODE $MODE"
            ;;
    esac

    remove_old_files "$(get_job_var "$JOB" "LOCAL_DEST")" "$(get_job_var "$JOB" "LOCAL_DAYS_OLD")"
}

###############################################################################
# MAIN
###############################################################################

log "BACKUP START"

if [ "$1" = "--test" ]; then
    test_mode
fi

for JOB in $JOBS
do
    process_job "$JOB"
done

###############################################################################
# SUMMARY
###############################################################################

echo "TOTAL ERRORS: $TOTAL_ERRORS"
log "TOTAL ERRORS: $TOTAL_ERRORS"

###############################################################################
# EXIT
###############################################################################

exit "$TOTAL_ERRORS"