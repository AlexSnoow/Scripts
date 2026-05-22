#!/bin/sh
#
# Script Name: backup_logs.sh
# Description: Архивирует и перемещает лог-файлы за указанный месяц
#              в директорию резервного копирования.
#
# Usage: backup_logs.sh [YYYYMM]
#        Если аргумент не передан, используется предыдущий месяц
#        (вычисляется через prev_month.pl)
#
# Arguments:
#        YYYYMM - год и месяц в формате YYYYMM (например, 202401)
#
# Exit Codes:
#        0 - Успешное выполнение
#        1 - Переменная PM пуста (ошибка получения месяца)
#        2 - Ошибка создания tar-архива
#        3 - Ошибка сжатия gzip
#
# Requirements:
#        - Perl-скрипт prev_month.pl должен находиться в той же директории
#        - Директории /uFolder/caFolder/, log_arc/ и /Folder_backup/ должны существовать
#
# Author: Auto-generated
# Date: Created based on legacy script
#

# Переход в рабочую директорию
WORK_DIR="/uFolder/caFolder"
if [ ! -d "$WORK_DIR" ]; then
    echo "$(date +%Y%m%d%H%M) - Error: Working directory $WORK_DIR does not exist."
    exit 1
fi

cd "$WORK_DIR" || exit 1

# Получение текущей даты для логирования
cur_date=$(date +%Y%m%d%H%M)

# Определение периода (PM) - год и месяц для архивации
if [ $# -eq 0 ]; then
    # Если аргументы не переданы, используем prev_month.pl
    if [ ! -f "prev_month.pl" ]; then
        echo "$cur_date - Error: prev_month.pl not found in $WORK_DIR"
        exit 1
    fi
    PM=$(perl prev_month.pl)
else
    PM="$1"
fi

echo "$cur_date - Starting script."

# Проверка, что переменная PM не пустая
if [ -z "$PM" ]; then
    echo "$cur_date - Error: variable PM is empty."
    exit 1
fi

echo "$cur_date - PM = $PM"

# Проверка наличия файлов для архивации
file_pattern="log/*.$PM??"
file_count=$(ls $file_pattern 2>/dev/null | wc -l)

if [ "$file_count" -eq 0 ]; then
    echo "$cur_date - Warning: No files found matching pattern $file_pattern"
    exit 0
fi

echo "$cur_date - Found $file_count files to archive."
ls -la $file_pattern

# Создание tar-архива
tar cvf log_arc/logsFolder$PM.tar $file_pattern
tar_status=$?

if [ $tar_status -ne 0 ]; then
    echo "$cur_date - Tar errors! (exit code: $tar_status)"
    rm -f log_arc/logsFolder$PM.tar
    exit 2
fi

# Удаление исходных файлов после успешного создания архива
rm $file_pattern
echo "$cur_date - Logs of $PM successfully backuped."

# Сжатие архива
gzip --best log_arc/logsFolder$PM.tar
gzip_status=$?

if [ $gzip_status -ne 0 ]; then
    echo "$cur_date - Gzip errors! (exit code: $gzip_status)"
    exit 3
fi

# Перемещение архива в директорию резервного копирования
if [ ! -d "/Folder_backup" ]; then
    echo "$cur_date - Error: Backup directory /Folder_backup does not exist."
    exit 1
fi

mv log_arc/logsFolder$PM.tar.gz /Folder_backup/
mv_status=$?

if [ $mv_status -ne 0 ]; then
    echo "$cur_date - Error moving archive to /Folder_backup/ (exit code: $mv_status)"
    exit 1
fi

echo "$cur_date - Archive successfully moved to /Folder_backup/logsFolder$PM.tar.gz"
echo "$cur_date - Script completed successfully."

exit 0
