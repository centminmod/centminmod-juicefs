#!/bin/bash
CPUS=$(nproc)
MAX_CONCURRENT=$(($CPUS*2))

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

AWS_DEFAULT_CONCURRENT_REQUESTS=$(aws configure get s3.max_concurrent_requests --profile $AWS_PROFILE)
aws configure set s3.max_concurrent_requests $MAX_CONCURRENT --profile $AWS_PROFILE
AWS_OPTIMAL_CONCURRENT_REQUESTS=$(aws configure get s3.max_concurrent_requests --profile $AWS_PROFILE)

echo "Default s3.max_concurrent_requests: $AWS_DEFAULT_CONCURRENT_REQUESTS"
echo "Optimally set s3.max_concurrent_requests: $AWS_OPTIMAL_CONCURRENT_REQUESTS"

i=0
while [ $i -le $SHARD_COUNT ]
do
   # Check if the bucket exists
   if aws s3api head-bucket --bucket ${BUCKET_PREFIX}$i --profile "$AWS_PROFILE" --endpoint-url=${ENDPOINT} > /dev/null 2>&1
   then
       aws s3 rm s3://${BUCKET_PREFIX}$i/myjuicefs --recursive --profile "$AWS_PROFILE" --endpoint-url=${ENDPOINT}
   else
       echo "Bucket s3://${BUCKET_PREFIX}$i does not exist or you do not have permission to access it."
   fi
   ((i++))
done

aws configure set s3.max_concurrent_requests $AWS_DEFAULT_CONCURRENT_REQUESTS --profile $AWS_PROFILE
echo "Reset to default s3.max_concurrent_requests: $AWS_DEFAULT_CONCURRENT_REQUESTS"
