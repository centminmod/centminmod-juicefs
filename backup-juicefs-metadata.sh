#!/bin/bash

# Update PATH to include /usr/local/bin
export PATH=$PATH:/usr/local/bin

# Variables
DAYS_TO_KEEP=30
BACKUP_DIR="/home/juicefs_metadata_backups"
BACKUP_FILE_NAME="meta-dump"
COMPRESSION="pigz"  # change to "zstd" for zstd compression
PIGZ_COMP_LEVEL='-4'
ZSTD_COMP_LEVEL='-1'

# Check if metadata source argument is passed
if [ $# -eq 0 ]
  then
    echo "No arguments supplied. Please provide the metadata source as an argument."
    echo
    echo "Examples:"
    echo
    echo "$0 sqlite3:///home/juicefs/myjuicefs.db"
    echo "$0 redis://:password@localhost:6479/1"
    exit 1
fi

METADATA_SOURCE=$1

# Create the backup directory if it does not exist
mkdir -p $BACKUP_DIR

# Timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Backup
BACKUP_FILE=$BACKUP_DIR/$BACKUP_FILE_NAME-$TIMESTAMP.json
juicefs dump $METADATA_SOURCE $BACKUP_FILE

# Check if the backup was successful
if [ $? -eq 0 ]; then
    echo "Backup successful!"
    
    # Compress the backup file
    case $COMPRESSION in
        "pigz")
            pigz $PIGZ_COMP_LEVEL $BACKUP_FILE
            BACKUP_FILE=$BACKUP_FILE.gz
            ;;
        "zstd")
            zstd $ZSTD_COMP_LEVEL $BACKUP_FILE
            BACKUP_FILE=$BACKUP_FILE.zst
            ;;
        *)
            echo "Invalid compression method. Please set COMPRESSION to either 'pigz' or 'zstd'."
            exit 1
            ;;
    esac

    # Delete files older than DAYS_TO_KEEP days
    find $BACKUP_DIR -type f -name "$BACKUP_FILE_NAME-*.json.*" -mtime +$DAYS_TO_KEEP -exec rm {} \;
    echo "Deleted backups older than $DAYS_TO_KEEP days."
    echo "Backup metadata file: $BACKUP_FILE"

else
    echo "Backup failed!"
fi
