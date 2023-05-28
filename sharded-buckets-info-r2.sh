#!/bin/bash

# Update PATH to include /usr/local/bin
export PATH=$PATH:/usr/local/bin

# Check if metadata source argument is passed
if [ $# -eq 0 ]
  then
    echo "No arguments supplied. Please provide the following:"
    echo
    echo "aws cli profile name i.e. r2"
    echo "s3 sharded bucket prefix"
    echo "and shard count as an argument."
    echo "r2 endpoint-url i.e. https://your_cf_acount_id.r2.cloudflarestorage.com/"
    echo
    echo "Example if you're JuiceFS sharded bucket name prefix is:"
    echo "juicefs-shard-% for juicefs-shard-0, juicefs-shard-1 ... juicefs-shard-60 etc"
    echo
    echo "$0 r2 juicefs-shard- 60 https://your_cf_acount_id.r2.cloudflarestorage.com/"
    exit 1
fi

AWS_PROFILE=$1
BUCKET_PREFIX=$2
SHARD_COUNT=$(($3-1))
ENDPOINT=$4

LOG_FILE="bucket_info.log"
rm -f "$LOG_FILE"

# Initialize total counters
total_all_files=0
total_all_size=0

i=0
while [ $i -le $SHARD_COUNT ]
do
    # Fetch the data from AWS
    aws_output=$(aws s3 ls --recursive --profile "$AWS_PROFILE" --endpoint-url="$ENDPOINT" "s3://${BUCKET_PREFIX}$i")

    # Compute the total number of files
    total_files=$(echo "$aws_output" | wc -l)

    # Compute the total size of all files
    total_size=$(echo "$aws_output" | awk '{ total += $3 } END { print total }')

    # Output the results
    echo "Bucket: ${BUCKET_PREFIX}$i, Total Files: $total_files, Total Size: $total_size" | tee -a "$LOG_FILE"

    # Update total counters
    total_all_files=$((total_all_files + total_files))
    total_all_size=$((total_all_size + total_size))

    ((i++))
done

# Output total counters
echo "Total for all buckets, Total Files: $total_all_files, Total Size: $total_all_size" | tee -a $LOG_FILE
