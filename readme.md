# JuiceFS Setup

Installing [JuiceFS](https://juicefs.com/docs/community/introduction/) high performanced POSIX compatible shared file system on Centmin Mod LEMP stack using [JuiceFS caching](https://juicefs.com/docs/community/cache_management) with [Cloudflare R2](https://blog.cloudflare.com/r2-open-beta/) - S3 compatible object storage and local sqlite3 Metadata Engine. Check out JuiceFS Github discussion forum https://github.com/juicedata/juicefs/discussions if you have questions.

JuiceFS implements an architecture that seperates "data" and "metadata" storage. When using JuiceFS to store data, the data itself is persisted in [object storage](https://juicefs.com/docs/community/how_to_setup_object_storage/) (e.g., Amazon S3, OpenStack Swift, Ceph, Azure Blob or MinIO), and the corresponding metadata can be persisted in various databases ([Metadata Engines](https://juicefs.com/docs/community/databases_for_metadata/)) such as Redis, Amazon MemoryDB, MariaDB, MySQL, TiKV, etcd, SQLite, KeyDB, PostgreSQL, BadgerDB, or FoundationDB.

From https://juicefs.com/en/blog/usage-tips/juicefs-24-qas-for-beginners

**How is the performance of JuiceFS?**

JuiceFS is a distributed file system. The latency of metadata is determined by 1 to 2 network round trip(s) between the mount point and metadata service (generally 1-3 ms), and the latency of data depends on the object storage latency (generally 20-100ms). The throughput of sequential read and write can reachup to 2800 MiB/s (see Benchmark with fio), depending on the network bandwidth and whether the data can be easily compressed.

JuiceFS has a built-in multi-level cache (invalidated automatically). Once the cache is warmed up, latency and throughput can be very close to a local file system (although the use of FUSE may bring a small amount of overhead).

# Table Of Contents

* [Install JuiceFS binary](#install-juicefs-binary)
* [Upgrade JuiceFS binary](#upgrade-juicefs-binary)
* [Setup JuiceFS logrotation](#setup-juicefs-logrotation)
* [Format Cloudflare R2 S3 Storage](#format-cloudflare-r2-s3-storage)
* [Mount the JuiceFS Formatted R2 S3 Storage](#mount-the-juicefs-formatted-r2-s3-storage)
  * [Manual Mount](#manual-mount)
  * [systemd service Mount](#systemd-service-mount)
* [Setup JuiceFS S3 Gateway](#setup-juicefs-s3-gateway)
  * [Manually Starting JuiceFS S3 Gateway](#manually-starting-juicefs-s3-gateway)
  * [systemd service Starting JuiceFS S3 Gateway](#systemd-service-starting-juicefs-s3-gateway)
* [Working With Cloudflare R2 S3 Mounted Directory and JuiceFS S3 Gateway](#working-with-cloudflare-r2-s3-mounted-directory-and-juicefs-s3-gateway)
  * [Mount Info](#mount-info)
  * [Inspecting JuiceFS metadata engine status](#inspecting-juicefs-metadata-engine-status)
  * [Warmup Local Cache](#warmup-local-cache)
  * [Check Disk Size](#check-disk-size)
* [JuiceFS Benchmarks](#juicefs-benchmarks)
  * [Sharded R2 Mount On Intel Xeon E-2276G 6C/12T, 32GB memory and 2x 960GB NVMe raid 1](#sharded-r2-mount-on-intel-xeon-e-2276g-6c12t-32gb-memory-and-2x-960gb-nvme-raid-1)
  * [On Intel Xeon E-2276G 6C/12T, 32GB memory and 2x 960GB NVMe raid 1](#on-intel-xeon-e-2276g-6c12t-32gb-memory-and-2x-960gb-nvme-raid-1)
    * [with R2 bucket created with location hint North American East](#with-r2-bucket-created-with-location-hint-north-american-east)
    * [with R2 bucket created with location hint North American West](#with-r2-bucket-created-with-location-hint-north-american-west)
    * [with R2 bucket created on server](#with-r2-bucket-created-on-server)
      * [File copy tests](#file-copy-tests)
      * [fio test for E-2276G server](#fio-test-for-e-2276g-server)
  * [On Intel Core i7 4790K 4C/8T, 32GB memory and 2x 240GB SSD raid 1](#on-intel-core-i7-4790k-4c8t-32gb-memory-and-2x-240gb-ssd-raid-1)
    * [fio tests](#fio-test)
* [Destroying JuiceFS Filesystem](#destroying-juicefs-filesystem)

# Install JuiceFS binary

```
cd /svr-setup

JFS_LATEST_TAG=$(curl -s https://api.github.com/repos/juicedata/juicefs/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v')

wget "https://github.com/juicedata/juicefs/releases/download/v${JFS_LATEST_TAG}/juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz" -O juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz

tar -zxf "juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz"

install juicefs /usr/local/bin
\cp -af /usr/local/bin/juicefs /sbin/mount.juicefs
```
```
juicefs -V
juicefs version 1.0.0-beta3+2022-05-05.0fb9155
```
```
juicefs --help
NAME:
   juicefs - A POSIX file system built on Redis and object storage.

USAGE:
   juicefs [global options] command [command options] [arguments...]

VERSION:
   1.0.0-beta3+2022-05-05.0fb9155

COMMANDS:
   ADMIN:
     format   Format a volume
     config   Change configuration of a volume
     destroy  Destroy an existing volume
     gc       Garbage collector of objects in data storage
     fsck     Check consistency of a volume
     dump     Dump metadata into a JSON file
     load     Load metadata from a previously dumped JSON file
   INSPECTOR:
     status   Show status of a volume
     stats    Show real time performance statistics of JuiceFS
     profile  Show profiling of operations completed in JuiceFS
     info     Show internal information of a path or inode
   SERVICE:
     mount    Mount a volume
     umount   Unmount a volume
     gateway  Start an S3-compatible gateway
     webdav   Start a WebDAV server
   TOOL:
     bench   Run benchmark on a path
     warmup  Build cache for target directories/files
     rmr     Remove directories recursively
     sync    Sync between two storages

GLOBAL OPTIONS:
   --verbose, --debug, -v  enable debug log (default: false)
   --quiet, -q             only warning and errors (default: false)
   --trace                 enable trace log (default: false)
   --no-agent              disable pprof (:6060) and gops (:6070) agent (default: false)
   --no-color              disable colors (default: false)
   --help, -h              show help (default: false)
   --version, -V           print only the version (default: false)

COPYRIGHT:
   Apache License 2.0
```

# Upgrade JuiceFS Binary

Following instructions for upgrading JuiceFS client [here](https://github.com/juicedata/juicefs/blob/main/docs/en/faq.md#how-to-upgrade-juicefs-client) involves:

1. Unmounting the JuiceFS mount. If you setup using [systemd JuiceFS service file](#mount-the-juicefs-formatted-r2-s3-storage), then it's just a service stop for it and the [JuiceFS S3 Gateway service](#systemd-service-starting-juicefs-s3-gateway).

Upgrading to [JuiceFS v1.0.0](https://github.com/juicedata/juicefs/releases/tag/v1.0.0):

```
systemctl stop juicefs.service juicefs-gateway.service
```

2. Updating JuiceFS binary

```
cd /svr-setup

JFS_LATEST_TAG=$(curl -s https://api.github.com/repos/juicedata/juicefs/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v')

wget "https://github.com/juicedata/juicefs/releases/download/v${JFS_LATEST_TAG}/juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz" -O juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz

tar -zxf "juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz"

install juicefs /usr/local/bin
\cp -af /usr/local/bin/juicefs /sbin/mount.juicefs
```

3. Starting JuiceFS and JuiceFS S3 Gateway services

```
systemctl start juicefs.service juicefs-gateway.service
systemctl status juicefs.service juicefs-gateway.service --no-pager
```

4. Checking updated JuiceFS binary and mount.

```
juicefs -V
juicefs version 1.0.4+2023-04-06.f1c475d

df -hT /home/juicefs_mount
Filesystem        Type          Size  Used Avail Use% Mounted on
JuiceFS:myjuicefs fuse.juicefs  1.0P     0  1.0P   0% /home/juicefs_mount
```

```
mkdir -p /home/juicefs
cd /home/juicefs

juicefs status sqlite3:///home/juicefs/myjuicefs.db
2022/06/21 13:54:45.570232 juicefs[28472] <INFO>: Meta address: sqlite3:///home/juicefs/myjuicefs.db [interface.go:397]
{
  "Setting": {
    "Name": "myjuicefs",
    "UUID": "2109366a-5f4f-4449-8723-dfec21f48e8f",
    "Storage": "s3",
    "Bucket": "https://juicefs.cfaccountid.r2.cloudflarestorage.com",
    "AccessKey": "cfaccesskey",
    "SecretKey": "removed",
    "BlockSize": 4096,
    "Compression": "none",
    "Shards": 0,
    "HashPrefix": false,
    "Capacity": 0,
    "Inodes": 0,
    "KeyEncrypted": true,
    "TrashDays": 0,
    "MetaVersion": 1,
    "MinClientVersion": "",
    "MaxClientVersion": ""
  },
  "Sessions": [
    {
      "Sid": 19,
      "Expire": "2022-08-12T12:58:32Z",
      "Version": "1.0.4+2023-04-06.f1c475d",
      "HostName": "host.domain.com",
      "MountPoint": "/home/juicefs_mount",
      "ProcessID": 28376
    },
    {
      "Sid": 20,
      "Expire": "2022-08-12T12:58:32Z",
      "Version": "1.0.4+2023-04-06.f1c475d",
      "HostName": "host.domain.com",
      "MountPoint": "s3gateway",
      "ProcessID": 28387
    }
  ]
}
```

## Setup JuiceFS logrotation

```
cat > "/etc/logrotate.d/juicefs" <<END
/var/log/juicefs.log {
        daily
        dateext
        missingok
        rotate 10
        maxsize 500M
        compress
        delaycompress
        notifempty
}
END
```
```
logrotate -d /etc/logrotate.d/juicefs
reading config file /etc/logrotate.d/juicefs
Allocating hash table for state file, size 15360 B

Handling 1 logs

rotating pattern: /var/log/juicefs.log  after 1 days (10 rotations)
empty log files are not rotated, log files >= 524288000 are rotated earlier, old logs are removed
considering log /var/log/juicefs.log
  log does not need rotating (log has been rotated at 2022-5-25 3:0, that is not day ago yet)
```

# Format Cloudflare R2 S3 Storage

Fill in variables for your Cloudflare account id, R2 bucket access key and secret key and the R2 bucket name - create the R2 bucket before hand. The sqlite3 database will be saved at `/home/juicefs/myjuicefs.db`. 

* JuiceFS supports compression algorithms which can be enabled via `--compress` option which have 3 available options - lz4, zstd or none (default).
* `--trash-days` - number of days after which removed files will be permanently deleted. Default = 1.
* `--block-size` - size of block in KiB
* Other various format options listed at https://juicefs.com/docs/community/command_reference#options.

```
cfaccountid='CF_ACCOUNT_ID'
cfaccesskey=''
cfsecretkey=''
cfbucketname='juicefs'

mkdir -p /home/juicefs
cd /home/juicefs

juicefs format --storage s3 \
    --bucket https://${cfbucketname}.${cfaccountid}.r2.cloudflarestorage.com \
    --access-key $cfaccesskey \
    --secret-key $cfsecretkey \
    --compress none \
    --trash-days 0 \
    --block-size 4096 \
    sqlite3:///home/juicefs/myjuicefs.db myjuicefs
```

# Mount the JuiceFS Formatted R2 S3 Storage

Create the mount directory and cache directories.

```
mkdir -p /home/juicefs_mount /home/juicefs_cache
```

## Manual Mount

There are additional JuiceFS mounting options outlined at https://juicefs.com/docs/community/command_reference#options-1

Manually mount the R2 S3 storage at `/home/juicefs_mount`

```
juicefs mount sqlite3:///home/juicefs/myjuicefs.db /home/juicefs_mount \
--cache-dir /home/juicefs_cache \
--cache-size 102400 \
--buffer-size 2048 \
--open-cache 0 \
--attr-cache 1 \
--entry-cache 1 \
--dir-entry-cache 1 \
--cache-partial-only false \
--free-space-ratio 0.1 \
--writeback \
--no-usage-report \
--max-uploads 20 \
--max-deletes 10 \
--backup-meta 1h \
--log /var/log/juicefs.log \
--get-timeout 300 \
--put-timeout 900 \
--io-retries 90 \
--prefetch 1 -d
```

## systemd service Mount

Or instead of manually mounting, setup systemd service file to manage mounting and unmounting the directory

`/usr/lib/systemd/system/juicefs.service`

```
[Unit]
Description=JuiceFS
AssertPathIsDirectory=/home/juicefs_mount
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/juicefs
ExecStart=/usr/local/bin/juicefs mount \
  "sqlite3:///home/juicefs/myjuicefs.db" \
  /home/juicefs_mount \
  --no-usage-report \
  --writeback \
  --cache-size 102400 \
  --cache-dir /home/juicefs_cache \
  --buffer-size 2048 \
  --open-cache 0 \
  --attr-cache 1 \
  --entry-cache 1 \
  --dir-entry-cache 1 \
  --cache-partial-only false \
  --free-space-ratio 0.1 \
  --max-uploads 20 \
  --max-deletes 10 \
  --backup-meta 1h \
  --log /var/log/juicefs.log \
  --get-timeout 300 \
  --put-timeout 900 \
  --io-retries 90 \
  --prefetch 1

ExecStop=/usr/local/bin/juicefs umount /home/juicefs_mount
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```
```
mkdir -p /etc/systemd/system/juicefs.service.d

cat > "/etc/systemd/system/juicefs.service.d/openfileslimit.conf" <<TDG
[Service]
LimitNOFILE=524288
TDG
```

```
systemctl daemon-reload
systemctl start juicefs
systemctl enable juicefs
systemctl status juicefs
journalctl -u juicefs --no-pager | tail -50
```

```
systemctl status juicefs | sed -e "s|$(hostname)|hostname|g"
● juicefs.service - JuiceFS
   Loaded: loaded (/usr/lib/systemd/system/juicefs.service; enabled; vendor preset: disabled)
  Drop-In: /etc/systemd/system/juicefs.service.d
           └─openfileslimit.conf
   Active: active (running) since Wed 2022-05-25 04:26:33 UTC; 14min ago
  Process: 25661 ExecStop=/usr/local/bin/juicefs umount /home/juicefs_mount (code=exited, status=0/SUCCESS)
 Main PID: 26947 (juicefs)
    Tasks: 17
   Memory: 18.7M
   CGroup: /system.slice/juicefs.service
           └─26947 /usr/local/bin/juicefs mount sqlite3:///home/juicefs/myjuicefs.db /home/juicefs_mount --no-usage-report --writeback --cache-size 102400 --cache-dir /home/juicefs_cache --free-space-ratio 0.1 --max-uploads 20 --max-deletes 10 --backup-meta 1h --log /var/log/juicefs.log -                                                                                  

May 25 04:26:33 hostname systemd[1]: Started JuiceFS.
May 25 04:26:33 hostname juicefs[26947]: 2022/05/25 04:26:33.125185 juicefs[26947] <INFO>: Meta address: sqlite3:///home/juicefs/myjuicefs.db [interface.go:385]
May 25 04:26:33 hostname juicefs[26947]: 2022/05/25 04:26:33.126772 juicefs[26947] <INFO>: Data use s3://juicefs/myjuicefs/ [mount.go:289]
May 25 04:26:33 hostname juicefs[26947]: 2022/05/25 04:26:33.127088 juicefs[26947] <INFO>: Disk cache (/home/juicefs_cache/3c874e07-a62c-42a9-ae67-5865491dd4a8/): capacity (102400 MB), free ratio (10%), max pending pages (51) [disk_cache.go:90]
May 25 04:26:33 hostname juicefs[26947]: 2022/05/25 04:26:33.138212 juicefs[26947] <INFO>: create session 1 OK [base.go:185]
May 25 04:26:33 hostname juicefs[26947]: 2022/05/25 04:26:33.138802 juicefs[26947] <INFO>: Prometheus metrics listening on 127.0.0.1:9567 [mount.go:157]
May 25 04:26:33 hostname juicefs[26947]: 2022/05/25 04:26:33.138890 juicefs[26947] <INFO>: Mounting volume myjuicefs at /home/juicefs_mount ... [mount_unix.go:177]
May 25 04:26:33 hostname juicefs[26947]: 2022/05/25 04:26:33.628570 juicefs[26947] <INFO>: OK, myjuicefs is ready at /home/juicefs_mount [mount_unix.go:45]
May 25 04:32:19 hostname juicefs[26947]: 2022/05/25 04:32:19.284310 juicefs[26947] <WARNING>: Secret key is removed for the sake of safety [sql.go:2770]
May 25 04:32:20 hostname juicefs[26947]: 2022/05/25 04:32:20.804652 juicefs[26947] <INFO>: backup metadata succeed, used 1.527736137s [backup.go:69]
```

Using AWS CLI profile for r2 user to check underlying JuiceFS metadata:

```
cfbucketname='juicefs'

aws s3 ls --recursive --profile r2 --endpoint-url=$url s3://$cfbucketname/
2022-05-25 04:26:25         36 myjuicefs/juicefs_uuid
2022-05-25 04:32:20        598 myjuicefs/meta/dump-2022-05-25-043219.json.gz
```

# Setup JuiceFS S3 Gateway

Setup [JuiceFS S3 Gateway](https://juicefs.com/docs/community/s3_gateway#use-the-aws-cli) and setup AWS CLI profile `juicefs` using my [awscli-get.sh](https://awscli-get.centminmod.com/) script to configure the profile.

Install `awscli-get.sh`:

```
curl -4s https://awscli-get.centminmod.com/awscli-get.sh -o awscli-get.sh
chmod +x awscli-get.sh
```

Change `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD` variable values to your descired S3 Gateway access and secret keys. Make sure they're different from your Cloudflare R2 access and secret key credentials.

Setup AWS CLI profile using `awscli-get.sh`:

```
export MINIO_ROOT_USER=AKIAIOSFODNN7EXAMPLE
export MINIO_ROOT_PASSWORD=12345678

# https://awscli-get.centminmod.com/
export AWS_ACCESS_KEY_ID=$MINIO_ROOT_USER
export AWS_SECRET_ACCESS_KEY=$MINIO_ROOT_PASSWORD
export AWS_DEFAULT_REGION=auto
export AWS_DEFAULT_OUTPUT=text
./awscli-get.sh install juicefs
```

Example output from [awscli-get.sh](https://awscli-get.centminmod.com/) script installing AWS CLI profile named `juicefs`:

```
./awscli-get.sh install juicefs

existing config file detected: /root/.aws/config
existing credential file detected: /root/.aws/credentials

configure aws-cli profile: juicefs
configure aws cli for Cloudflare R2
aws configure set s3.max_concurrent_requests 2 --profile juicefs
aws configure set s3.multipart_threshold 50MB --profile juicefs
aws configure set s3.multipart_chunksize 50MB --profile juicefs
aws configure set s3.addressing_style path --profile juicefs

aws-cli profile: juicefs set:

aws_access_key_id: AKIAIOSFODNN7EXAMPLE
aws_secret_access_key: 12345678
default.region: auto
default output format: text

list aws-cli profiles:

default
r2
juicefs
```

## Manually Starting JuiceFS S3 Gateway

Manually starting created JuiceFS S3 Gateway

Private local access only:

```
# local private access
juicefs gateway \
--cache-dir /home/juicefs_cache \
--cache-size 102400 \
--attr-cache 1 \
--entry-cache 0 \
--dir-entry-cache 1 \
--prefetch 1 \
--free-space-ratio 0.1 \
--writeback \
--backup-meta 1h \
--no-usage-report \
--buffer-size 2048 sqlite3:///home/juicefs/myjuicefs.db localhost:3777
```

Public net accessible mode:

```
# public access
juicefs gateway \
--cache-dir /home/juicefs_cache \
--cache-size 102400 \
--attr-cache 1 \
--entry-cache 0 \
--dir-entry-cache 1 \
--prefetch 1 \
--free-space-ratio 0.1 \
--writeback \
--backup-meta 1h \
--no-usage-report \
--buffer-size 2048 sqlite3:///home/juicefs/myjuicefs.db 0.0.0.0:3777
```

## systemd service Starting JuiceFS S3 Gateway

Or instead of manually creating JuiceFS S3 Gateway, use systemd service file.

Below is using private local access only.

`/usr/lib/systemd/system/juicefs-gateway.service`

```
[Unit]
Description=JuiceFS Gateway
After=network-online.target

[Service]
Environment='MINIO_ROOT_USER=AKIAIOSFODNN7EXAMPLE'
Environment='MINIO_ROOT_PASSWORD=12345678'
Type=simple
WorkingDirectory=/home/juicefs
ExecStart=/usr/local/bin/juicefs gateway \
  --no-usage-report \
  --writeback \
  --cache-size 102400 \
  --cache-dir /home/juicefs_cache \
  --attr-cache 1 \
  --entry-cache 0 \
  --dir-entry-cache 1 \
  --prefetch 1 \
  --free-space-ratio 0.1 \
  --max-uploads 20 \
  --max-deletes 10 \
  --backup-meta 1h \
  --get-timeout 300 \
  --put-timeout 900 \
  --io-retries 90 \
  --buffer-size 2048 \
  "sqlite3:///home/juicefs/myjuicefs.db" \
  localhost:3777

Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```
```
mkdir -p /etc/systemd/system/juicefs-gateway.service.d

cat > "/etc/systemd/system/juicefs-gateway.service.d/openfileslimit.conf" <<TDG
[Service]
LimitNOFILE=524288
TDG
```
```
systemctl start juicefs-gateway
systemctl enable juicefs-gateway
systemctl status juicefs-gateway
journalctl -u juicefs-gateway --no-pager | tail -50
```

```
systemctl status juicefs-gateway | sed -e "s|$(hostname)|hostname|g"
● juicefs-gateway.service - JuiceFS Gateway
   Loaded: loaded (/usr/lib/systemd/system/juicefs-gateway.service; enabled; vendor preset: disabled)
  Drop-In: /etc/systemd/system/juicefs-gateway.service.d
           └─openfileslimit.conf
   Active: active (running) since Wed 2022-05-25 04:26:33 UTC; 18min ago
 Main PID: 26957 (juicefs)
    Tasks: 13
   Memory: 18.3M
   CGroup: /system.slice/juicefs-gateway.service
           └─26957 /usr/local/bin/juicefs gateway --no-usage-report --writeback --cache-size 102400 --cache-dir /home/juicefs_cache --free-space-ratio 0.1 --max-uploads 20 --max-deletes 10 --backup-meta 1h --get-timeout 300 --put-timeout 900 --io-retries 90 --prefetch 1 --bu                                                    

May 25 04:26:33 hostname juicefs[26957]: 2022/05/25 04:26:33.159004 juicefs[26957] <INFO>: Prometheus metrics listening on 127.0.0.1:10037 [mount.go:157]
May 25 04:26:33 hostname juicefs[26957]: Endpoint: http://localhost:3777
May 25 04:26:33 hostname juicefs[26957]: Browser Access:
May 25 04:26:33 hostname juicefs[26957]: http://localhost:3777
May 25 04:26:33 hostname juicefs[26957]: Object API (Amazon S3 compatible):
May 25 04:26:33 hostname juicefs[26957]: Go:         https://docs.min.io/docs/golang-client-quickstart-guide
May 25 04:26:33 hostname juicefs[26957]: Java:       https://docs.min.io/docs/java-client-quickstart-guide
May 25 04:26:33 hostname juicefs[26957]: Python:     https://docs.min.io/docs/python-client-quickstart-guide
May 25 04:26:33 hostname juicefs[26957]: JavaScript: https://docs.min.io/docs/javascript-client-quickstart-guide
May 25 04:26:33 hostname juicefs[26957]: .NET:       https://docs.min.io/docs/dotnet-client-quickstart-guide
```

# Working With Cloudflare R2 S3 Mounted Directory and JuiceFS S3 Gateway

Using AWS CLI `r2` profile to inspect underlying JuiceFS metadata engine data.

```
url=${cfaccountid}.r2.cloudflarestorage.com

echo 1 > /home/juicefs_mount/file1.txt

aws s3 ls --recursive --profile r2 --endpoint-url=$url s3://$cfbucketname/

2022-05-25 04:48:46          2 myjuicefs/chunks/0/0/1_0_2
2022-05-25 04:26:25         36 myjuicefs/juicefs_uuid
2022-05-25 04:32:20        598 myjuicefs/meta/dump-2022-05-25-043219.json.gz
```

Using AWS CLI `juicefs` profile to inspect the JuiceFS S3 Gateway.

```
aws --endpoint-url http://localhost:3777 s3 ls --recursive myjuicefs
2022-05-25 04:48:45          2 file1.txt
```

## Mount Info

```
juicefs info /home/juicefs_mount/
/home/juicefs_mount/ :
 inode: 1
 files: 1
 dirs:  1
 length:        2
 size:  8192
```

## Inspecting JuiceFS metadata engine status

```
juicefs status sqlite3:///home/juicefs/myjuicefs.db
2022/05/25 04:50:06.356669 juicefs[33155] <INFO>: Meta address: sqlite3:///home/juicefs/myjuicefs.db [interface.go:385]
{
  "Setting": {
    "Name": "myjuicefs",
    "UUID": "3c874e07-a62c-42a9-ae67-5865491dd4a8",
    "Storage": "s3",
    "Bucket": "https://juicefs.cfaccountid.r2.cloudflarestorage.com",
    "AccessKey": "cfaccesskey",
    "SecretKey": "removed",
    "BlockSize": 4096,
    "Compression": "none",
    "Shards": 0,
    "HashPrefix": false,
    "Capacity": 0,
    "Inodes": 0,
    "KeyEncrypted": true,
    "TrashDays": 1,
    "MetaVersion": 1,
    "MinClientVersion": "",
    "MaxClientVersion": ""
  },
  "Sessions": [
    {
      "Sid": 1,
      "Expire": "2022-05-25T04:50:59Z",
      "Version": "1.0.0-beta3+2022-05-05.0fb9155",
      "HostName": "host.domain.com",
      "MountPoint": "/home/juicefs_mount",
      "ProcessID": 26947
    },
    {
      "Sid": 2,
      "Expire": "2022-05-25T04:51:03Z",
      "Version": "1.0.0-beta3+2022-05-05.0fb9155",
      "HostName": "host.domain.com",
      "MountPoint": "s3gateway",
      "ProcessID": 26957
    }
  ]
}
```

## Warmup Local Cache

```
juicefs warmup -p 2 /home/juicefs_mount
Warmed up paths count: 1 / 1 [==============================================================]  done      
2022/05/25 05:29:18.497915 juicefs[43684] <INFO>: Successfully warmed up 1 paths [warmup.go:209]
```

## Check Disk Size

```
df -hT /home/juicefs_mount
Filesystem        Type          Size  Used Avail Use% Mounted on
JuiceFS:myjuicefs fuse.juicefs  1.0P  4.0K  1.0P   1% /home/juicefs_mount
```

## Metrics

```
curl -s http://localhost:9567/metrics
```

checking blockcache metrics

```
curl -s http://localhost:9567/metrics | grep blockcache | egrep -v '\#|hist'

juicefs_blockcache_blocks{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_blockcache_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_blockcache_drops{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_blockcache_evicts{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_blockcache_hit_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.62144e+07
juicefs_blockcache_hits{mp="/home/juicefs_mount",vol_name="myjuicefs"} 200
juicefs_blockcache_miss{mp="/home/juicefs_mount",vol_name="myjuicefs"} 647
juicefs_blockcache_miss_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.680160256e+09
juicefs_blockcache_write_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.173698048e+09
juicefs_blockcache_writes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 712
```

filtered metrics

```
curl -s http://localhost:9567/metrics | egrep -v '\#|hist|bucket'

juicefs_blockcache_blocks{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_blockcache_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_blockcache_drops{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_blockcache_evicts{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_blockcache_hit_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.62144e+07
juicefs_blockcache_hits{mp="/home/juicefs_mount",vol_name="myjuicefs"} 200
juicefs_blockcache_miss{mp="/home/juicefs_mount",vol_name="myjuicefs"} 647
juicefs_blockcache_miss_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.680160256e+09
juicefs_blockcache_write_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.173698048e+09
juicefs_blockcache_writes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 712
juicefs_cpu_usage{mp="/home/juicefs_mount",vol_name="myjuicefs"} 21.072261
juicefs_fuse_open_handlers{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_fuse_read_size_bytes_sum{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.173698048e+09
juicefs_fuse_read_size_bytes_count{mp="/home/juicefs_mount",vol_name="myjuicefs"} 16584
juicefs_fuse_written_size_bytes_sum{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.173698048e+09
juicefs_fuse_written_size_bytes_count{mp="/home/juicefs_mount",vol_name="myjuicefs"} 16584
juicefs_go_build_info{checksum="",mp="/home/juicefs_mount",path="github.com/juicedata/juicefs",version="(devel)",vol_name="myjuicefs"} 1
juicefs_go_gc_duration_seconds{mp="/home/juicefs_mount",vol_name="myjuicefs",quantile="0"} 2.4418e-05
juicefs_go_gc_duration_seconds{mp="/home/juicefs_mount",vol_name="myjuicefs",quantile="0.25"} 4.3148e-05
juicefs_go_gc_duration_seconds{mp="/home/juicefs_mount",vol_name="myjuicefs",quantile="0.5"} 5.6996e-05
juicefs_go_gc_duration_seconds{mp="/home/juicefs_mount",vol_name="myjuicefs",quantile="0.75"} 0.000106379
juicefs_go_gc_duration_seconds{mp="/home/juicefs_mount",vol_name="myjuicefs",quantile="1"} 0.000342952
juicefs_go_gc_duration_seconds_sum{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0.001999786
juicefs_go_gc_duration_seconds_count{mp="/home/juicefs_mount",vol_name="myjuicefs"} 22
juicefs_go_goroutines{mp="/home/juicefs_mount",vol_name="myjuicefs"} 62
juicefs_go_info{mp="/home/juicefs_mount",version="go1.17.8",vol_name="myjuicefs"} 1
juicefs_go_memstats_alloc_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.8662952e+07
juicefs_go_memstats_alloc_bytes_total{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.377878736e+09
juicefs_go_memstats_buck_hash_sys_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.537716e+06
juicefs_go_memstats_frees_total{mp="/home/juicefs_mount",vol_name="myjuicefs"} 4.703242e+06
juicefs_go_memstats_gc_cpu_fraction{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.1818653907586683e-05
juicefs_go_memstats_gc_sys_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 4.8828976e+07
juicefs_go_memstats_heap_alloc_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.8662952e+07
juicefs_go_memstats_heap_idle_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.28196608e+09
juicefs_go_memstats_heap_inuse_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 3.3079296e+07
juicefs_go_memstats_heap_objects{mp="/home/juicefs_mount",vol_name="myjuicefs"} 53970
juicefs_go_memstats_heap_released_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.278754816e+09
juicefs_go_memstats_heap_sys_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.315045376e+09
juicefs_go_memstats_last_gc_time_seconds{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.6535426808430629e+09
juicefs_go_memstats_lookups_total{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_go_memstats_mallocs_total{mp="/home/juicefs_mount",vol_name="myjuicefs"} 4.757212e+06
juicefs_go_memstats_mcache_inuse_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 9600
juicefs_go_memstats_mcache_sys_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 16384
juicefs_go_memstats_mspan_inuse_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 312256
juicefs_go_memstats_mspan_sys_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.736128e+06
juicefs_go_memstats_next_gc_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 5.738088e+07
juicefs_go_memstats_other_sys_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.769556e+06
juicefs_go_memstats_stack_inuse_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.0354688e+07
juicefs_go_memstats_stack_sys_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.0354688e+07
juicefs_go_memstats_sys_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.380288824e+09
juicefs_go_threads{mp="/home/juicefs_mount",vol_name="myjuicefs"} 271
juicefs_memory{mp="/home/juicefs_mount",vol_name="myjuicefs"} 9.64608e+07
juicefs_object_request_data_bytes{method="GET",mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.147483648e+09
juicefs_object_request_data_bytes{method="PUT",mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.205155328e+09
juicefs_object_request_errors{mp="/home/juicefs_mount",vol_name="myjuicefs"} 337
juicefs_process_cpu_seconds_total{mp="/home/juicefs_mount",vol_name="myjuicefs"} 21.06
juicefs_process_max_fds{mp="/home/juicefs_mount",vol_name="myjuicefs"} 524288
juicefs_process_open_fds{mp="/home/juicefs_mount",vol_name="myjuicefs"} 23
juicefs_process_resident_memory_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 9.64608e+07
juicefs_process_start_time_seconds{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.65354147984e+09
juicefs_process_virtual_memory_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 2.159013888e+09
juicefs_process_virtual_memory_max_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1.8446744073709552e+19
juicefs_staging_block_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_staging_blocks{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_store_cache_size_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_transaction_restart{mp="/home/juicefs_mount",vol_name="myjuicefs"} 368
juicefs_uptime{mp="/home/juicefs_mount",vol_name="myjuicefs"} 1246.457965465
juicefs_used_buffer_size_bytes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 7.471104e+06
juicefs_used_inodes{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
juicefs_used_space{mp="/home/juicefs_mount",vol_name="myjuicefs"} 0
```

# JuiceFS Benchmarks

## Sharded R2 Mount On Intel Xeon E-2276G 6C/12T, 32GB memory and 2x 960GB NVMe raid 1

The server runs on 2x mismatched 960GB NVMe drives in raid 1 so bare in my the potential peak read and write performance of the resulting benchmarks:

* Samsung SSD PM983 960GB 2.5 U.2 Gen 3.0 x4 PCIe NVMe
  * Up to 3,000MB/s Read, 1,050MB/s Write
  * 4K random read/write 400,000/40,000 IOPS
  * 1366 TBW / 1.3 DWPD
  * Power: 4 Watt (idle) 8.6 Watt (read) 8.1 Watt (write)
* Kingston DC1500M U.2 Enterprise SSD Gen 3.0 x4 PCIe NVME
  * Up to 3,100MB/s Read, 1,700MB/s Write
  * Steady-state 4k read/write 440,000/150,000 IOPS
  * 1681 TBW (1 DWPD/5yrs) (1.6 DWPD/3yrs)
  * Power: Idle: 6.30W Average read: 6.21W Average write: 11.40W Max read: 6.60W Max write: 12.24W

Benchmark with [`--shard`](https://juicefs.com/docs/community/how_to_setup_object_storage#enable-data-sharding) mount option for [sharded Cloudflare R2 mounted JuiceFS](https://juicefs.com/docs/community/how_to_setup_object_storage#enable-data-sharding) over 5x sharded R2 object storage locations - `juicefs-shard-0`,`juicefs-shard-`,`juicefs-shard-1`,`juicefs-shard-3`, and `juicefs-shard-4` with location hint North American East.

```
cfaccountid='CF_ACCOUNT_ID'
cfaccesskey=''
cfsecretkey=''
cfbucketname='juicefs-shard'

mkdir -p /home/juicefs
cd /home/juicefs

juicefs format --storage s3 \
    --shards 5 \
    --bucket https://${cfbucketname}-%d.${cfaccountid}.r2.cloudflarestorage.com \
    --access-key $cfaccesskey \
    --secret-key $cfsecretkey \
    --compress none \
    --trash-days 0 \
    --block-size 4096 \
    sqlite3:///home/juicefs/myjuicefs.db myjuicefs
```

output

```
2023/05/24 17:45:14.116161 juicefs[3701895] <INFO>: Meta address: sqlite3:///home/juicefs/myjuicefs.db [interface.go:401]
2023/05/24 17:45:14.117248 juicefs[3701895] <INFO>: Data use shard5://s3://juicefs-shard-0/myjuicefs/ [format.go:434]
2023/05/24 17:45:18.423901 juicefs[3701895] <ERROR>: Can't list s3://juicefs-shard-0/: InvalidMaxKeys: MaxKeys params must be positive integer <= 1000.
        status code: 400, request id: , host id:  [sharding.go:85]
2023/05/24 17:45:18.423955 juicefs[3701895] <WARNING>: List storage shard5://s3://juicefs-shard-0/myjuicefs/ failed: list s3://juicefs-shard-0/: InvalidMaxKeys: MaxKeys params must be positive integer <= 1000.
        status code: 400, request id: , host id:  [format.go:452]
2023/05/24 17:45:18.709793 juicefs[3701895] <INFO>: Volume is formatted as {
  "Name": "myjuicefs",
  "UUID": "UUID-UUID-UUID-UUID",
  "Storage": "s3",
  "Bucket": "https://juicefs-shard-%d.CF_ACCOUNT_ID.r2.cloudflarestorage.com",
  "AccessKey": "CF_ACCESS_KEY",
  "SecretKey": "removed",
  "BlockSize": 4096,
  "Compression": "none",
  "Shards": 5,
  "KeyEncrypted": true,
  "MetaVersion": 1
} [format.go:471]
```

JuiceFS mount info

```
juicefs info /home/juicefs_mount/
/home/juicefs_mount/ :
  inode: 1
  files: 0
   dirs: 1
 length: 0 Bytes
   size: 4.00 KiB (4096 Bytes)
   path: /
```

JuiceFS sharded Cloudflare R2 benchmark with location hint North American East and 1024MB big file size.

```
juicefs bench -p 4 /home/juicefs_mount/
  Write big blocks count: 4096 / 4096 [===========================================================]  done      
   Read big blocks count: 4096 / 4096 [===========================================================]  done      
Write small blocks count: 400 / 400 [=============================================================]  done      
 Read small blocks count: 400 / 400 [=============================================================]  done      
  Stat small files count: 400 / 400 [=============================================================]  done      
Benchmark finished!
BlockSize: 1 MiB, BigFileSize: 1024 MiB, SmallFileSize: 128 KiB, SmallFileCount: 100, NumThreads: 4
Time used: 30.2 s, CPU: 103.5%, Memory: 1364.5 MiB
+------------------+------------------+--------------+
|       ITEM       |       VALUE      |     COST     |
+------------------+------------------+--------------+
|   Write big file |     960.47 MiB/s |  4.26 s/file |
|    Read big file |     174.17 MiB/s | 23.52 s/file |
| Write small file |    777.4 files/s | 5.15 ms/file |
|  Read small file |   7940.0 files/s | 0.50 ms/file |
|        Stat file |  29344.7 files/s | 0.14 ms/file |
|   FUSE operation | 71597 operations |   2.67 ms/op |
|      Update meta |  6041 operations |   4.09 ms/op |
|       Put object |  1136 operations | 428.27 ms/op |
|       Get object |  1049 operations | 299.50 ms/op |
|    Delete object |    60 operations | 120.73 ms/op |
| Write into cache |  1424 operations |  83.12 ms/op |
|  Read from cache |   400 operations |   0.05 ms/op |
+------------------+------------------+--------------+
```

JuiceFS sharded Cloudflare R2 benchmark with location hint North American East and 1MB big file size.

```
juicefs bench -p 4 /home/juicefs_mount/ --big-file-size 1
  Write big blocks count: 4 / 4 [==============================================================]  done      
   Read big blocks count: 4 / 4 [==============================================================]  done      
Write small blocks count: 400 / 400 [=============================================================]  done      
 Read small blocks count: 400 / 400 [=============================================================]  done      
  Stat small files count: 400 / 400 [=============================================================]  done      
Benchmark finished!
BlockSize: 1 MiB, BigFileSize: 1 MiB, SmallFileSize: 128 KiB, SmallFileCount: 100, NumThreads: 4
Time used: 1.6 s, CPU: 102.4%, Memory: 164.9 MiB
+------------------+-----------------+--------------+
|       ITEM       |      VALUE      |     COST     |
+------------------+-----------------+--------------+
|   Write big file |    448.20 MiB/s |  0.01 s/file |
|    Read big file |   1376.38 MiB/s |  0.00 s/file |
| Write small file |   792.5 files/s | 5.05 ms/file |
|  Read small file |  7827.1 files/s | 0.51 ms/file |
|        Stat file | 24308.1 files/s | 0.16 ms/file |
|   FUSE operation | 5750 operations |   0.38 ms/op |
|      Update meta | 5740 operations |   0.74 ms/op |
|       Put object |   94 operations | 286.35 ms/op |
|       Get object |    0 operations |   0.00 ms/op |
|    Delete object |   59 operations | 117.93 ms/op |
| Write into cache |  404 operations |   0.12 ms/op |
|  Read from cache |  408 operations |   0.05 ms/op |
+------------------+-----------------+--------------+
```

Inspecting Cloudflare R2 sharded storage buckets after JuiceFS benchmark run with location hint North American East

```
aws s3 ls --recursive --profile r2 --endpoint-url=$url s3://juicefs-shard-0
2023-05-24 18:46:01     131072 myjuicefs/chunks/0/0/980_0_131072
2023-05-24 18:46:03     131072 myjuicefs/chunks/0/1/1146_0_131072
2023-05-24 18:46:30     131072 myjuicefs/chunks/0/1/1540_0_131072

aws s3 ls --recursive --profile r2 --endpoint-url=$url s3://juicefs-shard-1
2023-05-24 18:46:03     131072 myjuicefs/chunks/0/1/1154_0_131072
2023-05-24 18:46:29     131072 myjuicefs/chunks/0/1/1386_0_131072
2023-05-24 18:46:31     131072 myjuicefs/chunks/0/1/1688_0_131072
2023-05-24 17:45:18         36 myjuicefs/juicefs_uuid

aws s3 ls --recursive --profile r2 --endpoint-url=$url s3://juicefs-shard-2
2023-05-24 17:52:09     131072 myjuicefs/chunks/0/0/574_0_131072
2023-05-24 18:46:01     131072 myjuicefs/chunks/0/1/1000_0_131072
2023-05-24 18:46:03     131072 myjuicefs/chunks/0/1/1142_0_131072

aws s3 ls --recursive --profile r2 --endpoint-url=$url s3://juicefs-shard-3
2023-05-24 18:46:03     131072 myjuicefs/chunks/0/1/1130_0_131072
2023-05-24 18:46:03     131072 myjuicefs/chunks/0/1/1150_0_131072
2023-05-24 18:46:05     131072 myjuicefs/chunks/0/1/1226_0_131072
2023-05-24 18:46:28     131072 myjuicefs/chunks/0/1/1382_0_131072
2023-05-24 18:46:30     131072 myjuicefs/chunks/0/1/1532_0_131072
2023-05-24 18:46:30     131072 myjuicefs/chunks/0/1/1552_0_131072
2023-05-24 18:46:31     131072 myjuicefs/chunks/0/1/1560_0_131072
2023-05-24 18:46:30     131072 myjuicefs/chunks/0/1/1564_0_131072
2023-05-24 18:46:31     131072 myjuicefs/chunks/0/1/1568_0_131072
2023-05-24 18:46:32     131072 myjuicefs/chunks/0/1/1728_0_131072
2023-05-24 17:53:44        581 myjuicefs/meta/dump-2023-05-24-225343.json.gz

aws s3 ls --recursive --profile r2 --endpoint-url=$url s3://juicefs-shard-4
2023-05-24 18:46:01     131072 myjuicefs/chunks/0/0/988_0_131072
2023-05-24 18:46:03     131072 myjuicefs/chunks/0/1/1134_0_131072
2023-05-24 18:46:03     131072 myjuicefs/chunks/0/1/1138_0_131072
2023-05-24 18:46:28     131072 myjuicefs/chunks/0/1/1390_0_131072
2023-05-24 18:46:28     131072 myjuicefs/chunks/0/1/1394_0_131072
2023-05-24 18:46:30     131072 myjuicefs/chunks/0/1/1556_0_131072
```

### fio sharded Cloudflare R2 test for E-2276G server with location hint North American East

fio Sequential Write
```
mkdir -p /home/juicefs_mount/fio

fio --name=sequential-write --directory=/home/juicefs_mount/fio --rw=write --refill_buffers --bs=4M --size=1G --end_fsync=1
sequential-write: (g=0): rw=write, bs=(R) 4096KiB-4096KiB, (W) 4096KiB-4096KiB, (T) 4096KiB-4096KiB, ioengine=psync, iodepth=1
fio-3.19
Starting 1 process
sequential-write: Laying out IO file (1 file / 1024MiB)
Jobs: 1 (f=1)
sequential-write: (groupid=0, jobs=1): err= 0: pid=3704701: Wed May 24 19:01:25 2023
  write: IOPS=279, BW=1119MiB/s (1173MB/s)(1024MiB/915msec); 0 zone resets
    clat (usec): min=2221, max=7356, avg=2961.60, stdev=807.86
     lat (usec): min=2222, max=7357, avg=2962.43, stdev=808.05
    clat percentiles (usec):
     |  1.00th=[ 2245],  5.00th=[ 2311], 10.00th=[ 2376], 20.00th=[ 2442],
     | 30.00th=[ 2540], 40.00th=[ 2638], 50.00th=[ 2704], 60.00th=[ 2802],
     | 70.00th=[ 2966], 80.00th=[ 3163], 90.00th=[ 4424], 95.00th=[ 4948],
     | 99.00th=[ 5735], 99.50th=[ 6718], 99.90th=[ 7373], 99.95th=[ 7373],
     | 99.99th=[ 7373]
   bw (  MiB/s): min= 1067, max= 1067, per=95.35%, avg=1067.08, stdev= 0.00, samples=1
   iops        : min=  266, max=  266, avg=266.00, stdev= 0.00, samples=1
  lat (msec)   : 4=89.84%, 10=10.16%
  cpu          : usr=16.19%, sys=38.95%, ctx=8195, majf=0, minf=9
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=0,256,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
  WRITE: bw=1119MiB/s (1173MB/s), 1119MiB/s-1119MiB/s (1173MB/s-1173MB/s), io=1024MiB (1074MB), run=915-915msec
```
```
ls -lah /home/juicefs_mount/fio
total 1.1G
drwxr-xr-x 2 root root 4.0K May 24 19:01 .
drwxrwxrwx 3 root root 4.0K May 24 19:01 ..
-rw-r--r-- 1 root root 1.0G May 24 19:01 sequential-write.0.0
```
```
juicefs warmup -p 4 /home/juicefs_mount/fio                              
Warming up count: 5                             0.06/s        
Warming up bytes: 5.00 GiB (5368709120 Bytes)   57.32 MiB/s   
2023/05/24 19:37:02.236625 juicefs[3705549] <INFO>: Successfully warmed up 5 files (5368709120 bytes) [warmup.go:233]
```

fio Sequential Read

```
fio --name=sequential-read --directory=/home/juicefs_mount/fio --rw=read --refill_buffers --bs=4M --size=1G --numjobs=4
sequential-read: (g=0): rw=read, bs=(R) 4096KiB-4096KiB, (W) 4096KiB-4096KiB, (T) 4096KiB-4096KiB, ioengine=psync, iodepth=1
...
fio-3.19
Starting 4 processes
Jobs: 4 (f=4): [R(4)][-.-%][r=2270MiB/s][r=567 IOPS][eta 00m:00s]
sequential-read: (groupid=0, jobs=1): err= 0: pid=3705616: Wed May 24 19:37:25 2023
  read: IOPS=132, BW=532MiB/s (557MB/s)(1024MiB/1926msec)
    clat (usec): min=2368, max=15013, avg=7167.80, stdev=1697.61
     lat (usec): min=2368, max=15013, avg=7169.52, stdev=1697.67
    clat percentiles (usec):
     |  1.00th=[ 2540],  5.00th=[ 5473], 10.00th=[ 5735], 20.00th=[ 6063],
     | 30.00th=[ 6390], 40.00th=[ 6652], 50.00th=[ 6915], 60.00th=[ 7242],
     | 70.00th=[ 7504], 80.00th=[ 7898], 90.00th=[ 9110], 95.00th=[10421],
     | 99.00th=[13304], 99.50th=[13829], 99.90th=[15008], 99.95th=[15008],
     | 99.99th=[15008]
   bw (  KiB/s): min=457227, max=573440, per=24.57%, avg=534320.67, stdev=66767.53, samples=3
   iops        : min=  111, max=  140, avg=130.00, stdev=16.46, samples=3
  lat (msec)   : 4=2.34%, 10=92.19%, 20=5.47%
  cpu          : usr=0.52%, sys=62.55%, ctx=3056, majf=0, minf=1036
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=3705617: Wed May 24 19:37:25 2023
  read: IOPS=132, BW=531MiB/s (557MB/s)(1024MiB/1929msec)
    clat (usec): min=1536, max=18497, avg=7181.80, stdev=1753.73
     lat (usec): min=1536, max=18500, avg=7183.40, stdev=1753.80
    clat percentiles (usec):
     |  1.00th=[ 2343],  5.00th=[ 5211], 10.00th=[ 5669], 20.00th=[ 6063],
     | 30.00th=[ 6456], 40.00th=[ 6718], 50.00th=[ 7046], 60.00th=[ 7373],
     | 70.00th=[ 7701], 80.00th=[ 8225], 90.00th=[ 8979], 95.00th=[10552],
     | 99.00th=[12518], 99.50th=[12649], 99.90th=[18482], 99.95th=[18482],
     | 99.99th=[18482]
   bw (  KiB/s): min=450877, max=572295, per=24.23%, avg=526742.67, stdev=66141.94, samples=3
   iops        : min=  110, max=  139, avg=128.33, stdev=15.95, samples=3
  lat (msec)   : 2=0.78%, 4=2.34%, 10=91.41%, 20=5.47%
  cpu          : usr=0.47%, sys=62.14%, ctx=3051, majf=0, minf=1037
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=3705618: Wed May 24 19:37:25 2023
  read: IOPS=133, BW=536MiB/s (562MB/s)(1024MiB/1911msec)
    clat (usec): min=4751, max=13813, avg=7109.46, stdev=1330.79
     lat (usec): min=4754, max=13815, avg=7111.26, stdev=1330.78
    clat percentiles (usec):
     |  1.00th=[ 5014],  5.00th=[ 5342], 10.00th=[ 5800], 20.00th=[ 6128],
     | 30.00th=[ 6390], 40.00th=[ 6652], 50.00th=[ 6849], 60.00th=[ 7111],
     | 70.00th=[ 7439], 80.00th=[ 7832], 90.00th=[ 8586], 95.00th=[ 9503],
     | 99.00th=[12125], 99.50th=[12518], 99.90th=[13829], 99.95th=[13829],
     | 99.99th=[13829]
   bw (  KiB/s): min=476279, max=589824, per=25.24%, avg=548858.00, stdev=63028.99, samples=3
   iops        : min=  116, max=  144, avg=133.67, stdev=15.37, samples=3
  lat (msec)   : 10=96.48%, 20=3.52%
  cpu          : usr=0.63%, sys=64.08%, ctx=3023, majf=0, minf=1036
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=3705619: Wed May 24 19:37:25 2023
  read: IOPS=134, BW=536MiB/s (562MB/s)(1024MiB/1910msec)
    clat (usec): min=4812, max=13160, avg=7107.62, stdev=1252.07
     lat (usec): min=4814, max=13163, avg=7109.17, stdev=1252.09
    clat percentiles (usec):
     |  1.00th=[ 4883],  5.00th=[ 5473], 10.00th=[ 5669], 20.00th=[ 6063],
     | 30.00th=[ 6456], 40.00th=[ 6652], 50.00th=[ 6980], 60.00th=[ 7242],
     | 70.00th=[ 7635], 80.00th=[ 7963], 90.00th=[ 8586], 95.00th=[ 9503],
     | 99.00th=[11469], 99.50th=[11731], 99.90th=[13173], 99.95th=[13173],
     | 99.99th=[13173]
   bw (  KiB/s): min=476279, max=598016, per=25.24%, avg=548863.33, stdev=64161.96, samples=3
   iops        : min=  116, max=  146, avg=133.67, stdev=15.70, samples=3
  lat (msec)   : 10=96.88%, 20=3.12%
  cpu          : usr=0.31%, sys=63.75%, ctx=3115, majf=0, minf=1036
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
   READ: bw=2123MiB/s (2227MB/s), 531MiB/s-536MiB/s (557MB/s-562MB/s), io=4096MiB (4295MB), run=1910-1929msec
```

directory fio test

```
ls -lah /home/juicefs_mount/fio
total 5.1G
drwxr-xr-x 2 root root 4.0K May 24 19:08 .
drwxrwxrwx 3 root root 4.0K May 24 19:01 ..
-rw-r--r-- 1 root root 1.0G May 24 19:08 sequential-read.0.0
-rw-r--r-- 1 root root 1.0G May 24 19:08 sequential-read.1.0
-rw-r--r-- 1 root root 1.0G May 24 19:08 sequential-read.2.0
-rw-r--r-- 1 root root 1.0G May 24 19:08 sequential-read.3.0
-rw-r--r-- 1 root root 1.0G May 24 19:01 sequential-write.0.0
```

## On Intel Xeon E-2276G 6C/12T, 32GB memory and 2x 960GB NVMe raid 1

Cloudflare R2 buckets are not yet geographically dispersed like Amazon AWS S3 and only operate in some geographical regions so performance of Cloudflare R2 and thuse JuiceFS can be impacted. 

For example, R2 created with location hint North American East versus R2 created on Dallas located dedicated server where Cloudflare automatically determines where R2 bucket gets created and their differences.

For JuiceFS mounted storage at `/home/juicefs_mount/`

| ITEM | VALUE (North American East) | COST (North American East) | VALUE (Server Location) | COST (Server Location) |
| --- | --- | --- | --- | --- |
| Write big file | 1374.08 MiB/s | 2.98 s/file | 973.94 MiB/s | 4.21 s/file |
| Read big file | 152.23 MiB/s | 26.91 s/file | 66.39 MiB/s | 61.69 s/file |
| Write small file | 780.3 files/s | 5.13 ms/file | 783.3 files/s | 5.11 ms/file |
| Read small file | 8000.9 files/s | 0.50 ms/file | 5335.7 files/s | 0.75 ms/file |
| Stat file | 27902.2 files/s | 0.14 ms/file | 22921.0 files/s | 0.17 ms/file |
| FUSE operation | 71649 operations | 3.06 ms/op | 72092 operations | 6.83 ms/op |
| Update meta | 6057 operations | 2.50 ms/op | 6213 operations | 3.92 ms/op |
| Put object | 1106 operations | 547.32 ms/op | 1065 operations | 1207.74 ms/op |
| Get object | 1030 operations | 301.80 ms/op | 1077 operations | 785.13 ms/op |
| Delete object | 29 operations | 234.02 ms/op | 27 operations | 250.50 ms/op |
| Write into cache | 1424 operations | 12.91 ms/op | 1424 operations | 18.18 ms/op |
| Read from cache | 400 operations | 0.04 ms/op | 400 operations | 0.05 ms/op |

For direct R2 object storage benchmarks without cache acceleration of JuiceFS

| ITEM | VALUE (North American East) | COST (North American East) | VALUE (Server Location) | COST (Server Location) |
| --- | --- | --- | --- | --- |
| Upload objects | 7.56 MiB/s | 528.88 ms/object | 3.26 MiB/s | 1228.16 ms/object |
| Download objects | 12.41 MiB/s | 322.35 ms/object | 4.22 MiB/s | 946.83 ms/object |
| Put small objects | 2.6 objects/s | 390.11 ms/object | 1.3 objects/s | 768.52 ms/object |
| Get small objects | 5.8 objects/s | 171.27 ms/object | 2.0 objects/s | 503.87 ms/object |
| List objects | 873.36 objects/s | 114.50 ms/op | 325.12 objects/s | 307.58 ms/op |
| Head objects | 13.4 objects/s | 74.84 ms/object | 4.3 objects/s | 231.59 ms/object |
| Delete objects | 4.3 objects/s | 230.17 ms/object | 3.5 objects/s | 283.57 ms/object |
| Change permissions | Not supported | Not supported | Not supported | Not supported |
| Change owner/group | Not supported | Not supported | Not supported | Not supported |
| Update mtime | Not supported | Not supported | Not supported | Not supported |

### with R2 bucket created with location hint North American East

with R2 bucket created on Cloudflare dashboard with location hint North American East

```
juicefs bench -p 4 /home/juicefs_mount/                                  
  Write big blocks count: 4096 / 4096 [===========================================================]  done      
   Read big blocks count: 4096 / 4096 [===========================================================]  done      
Write small blocks count: 400 / 400 [=============================================================]  done      
 Read small blocks count: 400 / 400 [=============================================================]  done      
  Stat small files count: 400 / 400 [=============================================================]  done      
Benchmark finished!
BlockSize: 1 MiB, BigFileSize: 1024 MiB, SmallFileSize: 128 KiB, SmallFileCount: 100, NumThreads: 4
Time used: 32.4 s, CPU: 97.4%, Memory: 527.6 MiB
+------------------+------------------+--------------+
|       ITEM       |       VALUE      |     COST     |
+------------------+------------------+--------------+
|   Write big file |    1374.08 MiB/s |  2.98 s/file |
|    Read big file |     152.23 MiB/s | 26.91 s/file |
| Write small file |    780.3 files/s | 5.13 ms/file |
|  Read small file |   8000.9 files/s | 0.50 ms/file |
|        Stat file |  27902.2 files/s | 0.14 ms/file |
|   FUSE operation | 71649 operations |   3.06 ms/op |
|      Update meta |  6057 operations |   2.50 ms/op |
|       Put object |  1106 operations | 547.32 ms/op |
|       Get object |  1030 operations | 301.80 ms/op |
|    Delete object |    29 operations | 234.02 ms/op |
| Write into cache |  1424 operations |  12.91 ms/op |
|  Read from cache |   400 operations |   0.04 ms/op |
+------------------+------------------+--------------+
```

direct Cloudflare R2 storage object benchmark with location hint North American East

```
juicefs objbench --storage s3 --access-key $cfaccesskey --secret-key $cfsecretkey https://${cfbucketname}.${cfaccountid}.r2.cloudflarestorage.com -p 1
Start Functional Testing ...
+----------+---------------------+--------------------------------------------------+
| CATEGORY |         TEST        |                      RESULT                      |
+----------+---------------------+--------------------------------------------------+
|    basic |     create a bucket |                                             pass |
|    basic |       put an object |                                             pass |
|    basic |       get an object |                                             pass |
|    basic |       get non-exist |                                             pass |
|    basic |  get partial object | failed to get object with the offset out of r... |
|    basic |      head an object |                                             pass |
|    basic |    delete an object |                                             pass |
|    basic |    delete non-exist |                                             pass |
|    basic |        list objects |                 the result for list is incorrect |
|    basic |         special key | list encode file failed SerializationError: f... |
|     sync |    put a big object |                                             pass |
|     sync | put an empty object |                                             pass |
|     sync |    multipart upload |                                             pass |
|     sync |  change owner/group |                                      not support |
|     sync |   change permission |                                      not support |
|     sync |        change mtime |                                      not support |
+----------+---------------------+--------------------------------------------------+

Start Performance Testing ...
2023/05/23 04:38:31.529817 juicefs[3658965] <ERROR>: The keys are out of order: marker "", last "19" current "1" [sync.go:132]
2023/05/23 04:38:31.641211 juicefs[3658965] <ERROR>: The keys are out of order: marker "", last "19" current "1" [sync.go:132]
2023/05/23 04:38:42.854394 juicefs[3658965] <ERROR>: The keys are out of order: marker "", last "19" current "1" [sync.go:132]
put small objects count: 100 / 100 [==============================================================]  done      
get small objects count: 100 / 100 [==============================================================]  done      
   upload objects count: 256 / 256 [==============================================================]  done      
 download objects count: 256 / 256 [==============================================================]  done      
     list objects count: 100 / 100 [==============================================================]  done      
     head objects count: 100 / 100 [==============================================================]  done      
   delete objects count: 100 / 100 [==============================================================]  done      
Benchmark finished! block-size: 4096 KiB, big-object-size: 1024 MiB, small-object-size: 128 KiB, small-objects: 100, NumThreads: 1
+--------------------+------------------+------------------+
|        ITEM        |       VALUE      |       COST       |
+--------------------+------------------+------------------+
|     upload objects |       7.56 MiB/s | 528.88 ms/object |
|   download objects |      12.41 MiB/s | 322.35 ms/object |
|  put small objects |    2.6 objects/s | 390.11 ms/object |
|  get small objects |    5.8 objects/s | 171.27 ms/object |
|       list objects | 873.36 objects/s |     114.50 ms/op |
|       head objects |   13.4 objects/s |  74.84 ms/object |
|     delete objects |    4.3 objects/s | 230.17 ms/object |
| change permissions |      not support |      not support |
| change owner/group |      not support |      not support |
|       update mtime |      not support |      not support |
+--------------------+------------------+------------------+
```

### with R2 bucket created with location hint North American West

with R2 bucket created on Cloudflare dashboard with location hint North American West and default 1024MB big file.

```
juicefs bench -p 4 /home/juicefs_mount/                                  
  Write big blocks count: 4096 / 4096 [===========================================================]  done      
   Read big blocks count: 4096 / 4096 [===========================================================]  done      
Write small blocks count: 400 / 400 [=============================================================]  done      
 Read small blocks count: 400 / 400 [=============================================================]  done      
  Stat small files count: 400 / 400 [=============================================================]  done      
Benchmark finished!
BlockSize: 1 MiB, BigFileSize: 1024 MiB, SmallFileSize: 128 KiB, SmallFileCount: 100, NumThreads: 4
Time used: 44.1 s, CPU: 70.9%, Memory: 646.6 MiB
+------------------+------------------+--------------+
|       ITEM       |       VALUE      |     COST     |
+------------------+------------------+--------------+
|   Write big file |    1382.61 MiB/s |  2.96 s/file |
|    Read big file |     106.13 MiB/s | 38.60 s/file |
| Write small file |    742.0 files/s | 5.39 ms/file |
|  Read small file |   5259.6 files/s | 0.76 ms/file |
|        Stat file |  25240.3 files/s | 0.16 ms/file |
|   FUSE operation | 71790 operations |   4.33 ms/op |
|      Update meta |  6123 operations |   2.24 ms/op |
|       Put object |  1072 operations | 787.82 ms/op |
|       Get object |  1057 operations | 320.67 ms/op |
|    Delete object |    10 operations | 426.32 ms/op |
| Write into cache |  1424 operations |  16.86 ms/op |
|  Read from cache |   400 operations |   0.05 ms/op |
+------------------+------------------+--------------+
```

with R2 bucket created on Cloudflare dashboard with location hint North American West and default 1MB big file.

```
juicefs bench -p 4 /home/juicefs_mount/ --big-file-size 1
  Write big blocks count: 4 / 4 [==============================================================]  done      
   Read big blocks count: 4 / 4 [==============================================================]  done      
Write small blocks count: 400 / 400 [=============================================================]  done      
 Read small blocks count: 400 / 400 [=============================================================]  done      
  Stat small files count: 400 / 400 [=============================================================]  done      
Benchmark finished!
BlockSize: 1 MiB, BigFileSize: 1 MiB, SmallFileSize: 128 KiB, SmallFileCount: 100, NumThreads: 4
Time used: 1.7 s, CPU: 102.6%, Memory: 154.9 MiB
+------------------+-----------------+--------------+
|       ITEM       |      VALUE      |     COST     |
+------------------+-----------------+--------------+
|   Write big file |    230.82 MiB/s |  0.02 s/file |
|    Read big file |   1276.38 MiB/s |  0.00 s/file |
| Write small file |   675.7 files/s | 5.92 ms/file |
|  Read small file |  7833.1 files/s | 0.51 ms/file |
|        Stat file | 28226.1 files/s | 0.14 ms/file |
|   FUSE operation | 5756 operations |   0.41 ms/op |
|      Update meta | 5770 operations |   0.70 ms/op |
|       Put object |  118 operations | 242.35 ms/op |
|       Get object |    0 operations |   0.00 ms/op |
|    Delete object |   95 operations |  83.94 ms/op |
| Write into cache |  404 operations |   0.14 ms/op |
|  Read from cache |  408 operations |   0.06 ms/op |
+------------------+-----------------+--------------+
```

### with R2 bucket created on server

with R2 bucket created on server, the R2 location is automatically chosen by Cloudflare

```
juicefs bench -p 4 /home/juicefs_mount/
  Write big blocks count: 4096 / 4096 [===========================================================]  done      
   Read big blocks count: 4096 / 4096 [===========================================================]  done      
Write small blocks count: 400 / 400 [=============================================================]  done      
 Read small blocks count: 400 / 400 [=============================================================]  done      
  Stat small files count: 400 / 400 [=============================================================]  done      
Benchmark finished!
BlockSize: 1 MiB, BigFileSize: 1024 MiB, SmallFileSize: 128 KiB, SmallFileCount: 100, NumThreads: 4
Time used: 68.4 s, CPU: 48.6%, Memory: 557.8 MiB
+------------------+------------------+---------------+
|       ITEM       |       VALUE      |      COST     |
+------------------+------------------+---------------+
|   Write big file |     973.94 MiB/s |   4.21 s/file |
|    Read big file |      66.39 MiB/s |  61.69 s/file |
| Write small file |    783.3 files/s |  5.11 ms/file |
|  Read small file |   5335.7 files/s |  0.75 ms/file |
|        Stat file |  22921.0 files/s |  0.17 ms/file |
|   FUSE operation | 72092 operations |    6.83 ms/op |
|      Update meta |  6213 operations |    3.92 ms/op |
|       Put object |  1065 operations | 1207.74 ms/op |
|       Get object |  1077 operations |  785.13 ms/op |
|    Delete object |    27 operations |  250.50 ms/op |
| Write into cache |  1424 operations |   18.18 ms/op |
|  Read from cache |   400 operations |    0.05 ms/op |
+------------------+------------------+---------------+
```

direct Cloudflare R2 storage object benchmark with R2 location is automatically chosen by Cloudflare

```
juicefs objbench --storage s3 --access-key $cfaccesskey --secret-key $cfsecretkey https://${cfbucketname}.${cfaccountid}.r2.cloudflarestorage.com -p 1

Start Functional Testing ...
+----------+---------------------+--------------------------------------------------+
| CATEGORY |         TEST        |                      RESULT                      |
+----------+---------------------+--------------------------------------------------+
|    basic |     create a bucket |                                             pass |
|    basic |       put an object |                                             pass |
|    basic |       get an object |                                             pass |
|    basic |       get non-exist |                                             pass |
|    basic |  get partial object | failed to get object with the offset out of r... |
|    basic |      head an object |                                             pass |
|    basic |    delete an object |                                             pass |
|    basic |    delete non-exist |                                             pass |
|    basic |        list objects |                 the result for list is incorrect |
|    basic |         special key | list encode file failed SerializationError: f... |
|     sync |    put a big object |                                             pass |
|     sync | put an empty object |                                             pass |
|     sync |    multipart upload |                                             pass |
|     sync |  change owner/group |                                      not support |
|     sync |   change permission |                                      not support |
|     sync |        change mtime |                                      not support |
+----------+---------------------+--------------------------------------------------+

Start Performance Testing ...
2023/05/21 21:20:52.072515 juicefs[3620125] <ERROR>: The keys are out of order: marker "", last "19" current "1" [sync.go:132]
2023/05/21 21:20:52.361774 juicefs[3620125] <ERROR>: The keys are out of order: marker "", last "19" current "1" [sync.go:132]

2023/05/21 21:21:22.543272 juicefs[3620125] <ERROR>: The keys are out of order: marker "", last "19" current "1" [sync.go:132]
put small objects count: 100 / 100 [==============================================================]  done      
get small objects count: 100 / 100 [==============================================================]  done      
   upload objects count: 256 / 256 [==============================================================]  done      
 download objects count: 256 / 256 [==============================================================]  done      
     list objects count: 100 / 100 [==============================================================]  done      
     head objects count: 100 / 100 [==============================================================]  done      
   delete objects count: 100 / 100 [==============================================================]  done      
Benchmark finished! block-size: 4096 KiB, big-object-size: 1024 MiB, small-object-size: 128 KiB, small-objects: 100, NumThreads: 1
+--------------------+------------------+-------------------+
|        ITEM        |       VALUE      |        COST       |
+--------------------+------------------+-------------------+
|     upload objects |       3.26 MiB/s | 1228.16 ms/object |
|   download objects |       4.22 MiB/s |  946.83 ms/object |
|  put small objects |    1.3 objects/s |  768.52 ms/object |
|  get small objects |    2.0 objects/s |  503.87 ms/object |
|       list objects | 325.12 objects/s |      307.58 ms/op |
|       head objects |    4.3 objects/s |  231.59 ms/object |
|     delete objects |    3.5 objects/s |  283.57 ms/object |
| change permissions |      not support |       not support |
| change owner/group |      not support |       not support |
|       update mtime |      not support |       not support |
+--------------------+------------------+-------------------+
```

### File copy tests

Comparing JuiceFS mount with R2 storage `/home/juicefs_mount/` versus direct R2 storage bucket `s3://${cfbucketname_raw}` for read and writes.


Writes tests

```
wget https://www.php.net/distributions/php-8.2.6.tar.gz

ls -lah php-8.2.6.tar.gz
-rw-r--r-- 1 root root 19M May  9 11:10 php-8.2.6.tar.gz

1st run
sync && echo 3 > /proc/sys/vm/drop_caches
time \cp -f php-8.2.6.tar.gz  /home/juicefs_mount/

real    0m0.040s
user    0m0.001s
sys     0m0.012s

2nd run
time \cp -f php-8.2.6.tar.gz  /home/juicefs_mount/

real    0m0.024s
user    0m0.000s
sys     0m0.012s

1st run
sync && echo 3 > /proc/sys/vm/drop_caches
time aws s3 cp --profile r2 --endpoint-url=$url php-8.2.6.tar.gz s3://${cfbucketname_raw}
upload: ./php-8.2.6.tar.gz to s3://${cfbucketname_raw}/php-8.2.6.tar.gz      

real    0m2.343s
user    0m0.430s
sys     0m0.082s

2nd run
time aws s3 cp --profile r2 --endpoint-url=$url php-8.2.6.tar.gz s3://${cfbucketname_raw}
upload: ./php-8.2.6.tar.gz to s3://${cfbucketname_raw}/php-8.2.6.tar.gz      

real    0m1.350s
user    0m0.431s
sys     0m0.058s
```

Read tests

```
1st run
sync && echo 3 > /proc/sys/vm/drop_caches
time \cp -f /home/juicefs_mount/php-8.2.6.tar.gz .

real    0m2.334s
user    0m0.001s
sys     0m0.016s

# 2nd run
time \cp -f /home/juicefs_mount/php-8.2.6.tar.gz .

real    0m0.025s
user    0m0.000s
sys     0m0.016s

1st run
sync && echo 3 > /proc/sys/vm/drop_caches
time aws s3 cp --profile r2 --endpoint-url=$url s3://${cfbucketname_raw}/php-8.2.6.tar.gz .
download: s3://${cfbucketname_raw}/php-8.2.6.tar.gz to ./php-8.2.6.tar.gz     

real    0m1.449s
user    0m0.432s
sys     0m0.084s

2nd run
time aws s3 cp --profile r2 --endpoint-url=$url s3://${cfbucketname_raw}/php-8.2.6.tar.gz .
download: s3://${cfbucketname_raw}/php-8.2.6.tar.gz to ./php-8.2.6.tar.gz   

real    0m0.959s
user    0m0.405s
sys     0m0.075s
```

| Test | File Size/Time (MB/s) | Time (Seconds) |
| ---- | --------------------- | -------------- |
| **Write to JuiceFS mounted S3 (1st run)** | 19MB/0.040s = 475 MB/s | 0.040 |
| **Write to JuiceFS mounted S3 (2nd run)** | 19MB/0.024s = 791.67 MB/s | 0.024 |
| **Write to S3 (1st run)** | 19MB/2.343s = 8.11 MB/s | 2.343 |
| **Write to S3 (2nd run)** | 19MB/1.350s = 14.07 MB/s | 1.350 |
| **Read from JuiceFS mounted S3 (1st run)** | 19MB/2.334s = 8.14 MB/s | 2.334 |
| **Read from JuiceFS mounted S3 (2nd run)** | 19MB/0.025s = 760 MB/s | 0.025 |
| **Read from S3 (1st run)** | 19MB/1.449s = 13.11 MB/s | 1.449 |
| **Read from S3 (2nd run)** | 19MB/0.959s = 19.81 MB/s | 0.959 |

### fio test for E-2276G server

Pre-warmed up cache directory fio test

```
ls -lah /home/juicefs_mount/fio
total 4.1G
drwxr-xr-x 2 root root 4.0K May 21 22:38 .
drwxrwxrwx 3 root root 4.0K May 21 22:37 ..
-rw-r--r-- 1 root root 1.0G May 21 22:38 sequential-read.0.0
-rw-r--r-- 1 root root 1.0G May 21 22:38 sequential-read.1.0
-rw-r--r-- 1 root root 1.0G May 21 22:38 sequential-read.2.0
-rw-r--r-- 1 root root 1.0G May 21 22:38 sequential-read.3.0
```
```
juicefs warmup -p 4 /home/juicefs_mount/fio
Warming up count: 4                             0.02/s        
Warming up bytes: 4.00 GiB (4294967296 Bytes)   16.59 MiB/s   
2023/05/21 22:47:02.773883 juicefs[3622249] <INFO>: Successfully warmed up 4 files (4294967296 bytes) [warmup.go:233]
```
```
fio --name=sequential-read --directory=/home/juicefs_mount/fio --rw=read --refill_buffers --bs=4M --size=1G --numjobs=4
sequential-read: (g=0): rw=read, bs=(R) 4096KiB-4096KiB, (W) 4096KiB-4096KiB, (T) 4096KiB-4096KiB, ioengine=psync, iodepth=1
...
fio-3.19
Starting 4 processes
Jobs: 3 (f=3): [_(1),R(3)][-.-%][r=2291MiB/s][r=572 IOPS][eta 00m:00s]
sequential-read: (groupid=0, jobs=1): err= 0: pid=3622348: Sun May 21 22:47:28 2023
  read: IOPS=135, BW=542MiB/s (568MB/s)(1024MiB/1890msec)
    clat (usec): min=4835, max=13800, avg=7004.83, stdev=1154.13
     lat (usec): min=4836, max=13801, avg=7006.45, stdev=1154.05
    clat percentiles (usec):
     |  1.00th=[ 5080],  5.00th=[ 5473], 10.00th=[ 5735], 20.00th=[ 6063],
     | 30.00th=[ 6390], 40.00th=[ 6587], 50.00th=[ 6849], 60.00th=[ 7111],
     | 70.00th=[ 7439], 80.00th=[ 7832], 90.00th=[ 8356], 95.00th=[ 8979],
     | 99.00th=[11076], 99.50th=[11731], 99.90th=[13829], 99.95th=[13829],
     | 99.99th=[13829]
   bw (  KiB/s): min=493799, max=589824, per=25.20%, avg=553928.67, stdev=52399.21, samples=3
   iops        : min=  120, max=  144, avg=135.00, stdev=13.08, samples=3
  lat (msec)   : 10=98.83%, 20=1.17%
  cpu          : usr=0.64%, sys=64.69%, ctx=3015, majf=0, minf=1036
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=3622349: Sun May 21 22:47:28 2023
  read: IOPS=134, BW=538MiB/s (564MB/s)(1024MiB/1905msec)
    clat (usec): min=3199, max=11916, avg=7060.50, stdev=1274.27
     lat (usec): min=3199, max=11916, avg=7062.11, stdev=1274.34
    clat percentiles (usec):
     |  1.00th=[ 3687],  5.00th=[ 5407], 10.00th=[ 5669], 20.00th=[ 6128],
     | 30.00th=[ 6456], 40.00th=[ 6718], 50.00th=[ 6980], 60.00th=[ 7242],
     | 70.00th=[ 7504], 80.00th=[ 7832], 90.00th=[ 8455], 95.00th=[ 9110],
     | 99.00th=[11600], 99.50th=[11731], 99.90th=[11863], 99.95th=[11863],
     | 99.99th=[11863]
   bw (  KiB/s): min=481137, max=581632, per=24.88%, avg=546977.33, stdev=57045.78, samples=3
   iops        : min=  117, max=  142, avg=133.33, stdev=14.15, samples=3
  lat (msec)   : 4=1.17%, 10=95.70%, 20=3.12%
  cpu          : usr=0.84%, sys=64.29%, ctx=2994, majf=0, minf=1036
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=3622350: Sun May 21 22:47:28 2023
  read: IOPS=134, BW=538MiB/s (564MB/s)(1024MiB/1905msec)
    clat (usec): min=3188, max=15334, avg=7060.55, stdev=1465.48
     lat (usec): min=3189, max=15337, avg=7062.32, stdev=1465.47
    clat percentiles (usec):
     |  1.00th=[ 3523],  5.00th=[ 5211], 10.00th=[ 5669], 20.00th=[ 6063],
     | 30.00th=[ 6390], 40.00th=[ 6652], 50.00th=[ 6849], 60.00th=[ 7177],
     | 70.00th=[ 7439], 80.00th=[ 7832], 90.00th=[ 8455], 95.00th=[ 9765],
     | 99.00th=[12518], 99.50th=[13042], 99.90th=[15270], 99.95th=[15270],
     | 99.99th=[15270]
   bw (  KiB/s): min=468476, max=594449, per=24.69%, avg=542724.33, stdev=65937.74, samples=3
   iops        : min=  114, max=  145, avg=132.33, stdev=16.26, samples=3
  lat (msec)   : 4=1.17%, 10=94.14%, 20=4.69%
  cpu          : usr=0.53%, sys=64.29%, ctx=2892, majf=0, minf=1036
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=3622351: Sun May 21 22:47:28 2023
  read: IOPS=134, BW=537MiB/s (563MB/s)(1024MiB/1908msec)
    clat (usec): min=1314, max=18340, avg=7077.81, stdev=1606.56
     lat (usec): min=1314, max=18341, avg=7079.39, stdev=1606.52
    clat percentiles (usec):
     |  1.00th=[ 2507],  5.00th=[ 5211], 10.00th=[ 5669], 20.00th=[ 6128],
     | 30.00th=[ 6259], 40.00th=[ 6652], 50.00th=[ 6980], 60.00th=[ 7308],
     | 70.00th=[ 7570], 80.00th=[ 7963], 90.00th=[ 8586], 95.00th=[ 9503],
     | 99.00th=[11994], 99.50th=[12518], 99.90th=[18220], 99.95th=[18220],
     | 99.99th=[18220]
   bw (  KiB/s): min=474806, max=573440, per=24.54%, avg=539421.67, stdev=55984.95, samples=3
   iops        : min=  115, max=  140, avg=131.33, stdev=14.15, samples=3
  lat (msec)   : 2=0.78%, 4=1.95%, 10=93.75%, 20=3.52%
  cpu          : usr=0.63%, sys=63.56%, ctx=2996, majf=0, minf=1036
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
   READ: bw=2147MiB/s (2251MB/s), 537MiB/s-542MiB/s (563MB/s-568MB/s), io=4096MiB (4295MB), run=1890-1908msec
```

## On Intel Core i7 4790K 4C/8T, 32GB memory and 2x 240GB SSD raid 1

```
juicefs bench -p 4 /home/juicefs_mount/                        
  Write big blocks count: 4096 / 4096 [======================================================]  done      
   Read big blocks count: 4096 / 4096 [======================================================]  done      
Write small blocks count: 400 / 400 [========================================================]  done      
 Read small blocks count: 400 / 400 [========================================================]  done      
  Stat small files count: 400 / 400 [========================================================]  done      
Benchmark finished!
BlockSize: 1 MiB, BigFileSize: 1024 MiB, SmallFileSize: 128 KiB, SmallFileCount: 100, NumThreads: 4
Time used: 29.5 s, CPU: 51.7%, Memory: 1317.1 MiB
+------------------+------------------+---------------+
|       ITEM       |       VALUE      |      COST     |
+------------------+------------------+---------------+
|   Write big file |     253.86 MiB/s |  16.13 s/file |
|    Read big file |     418.69 MiB/s |   9.78 s/file |
| Write small file |    312.3 files/s | 12.81 ms/file |
|  Read small file |   5727.4 files/s |  0.70 ms/file |
|        Stat file |  29605.6 files/s |  0.14 ms/file |
|   FUSE operation | 71271 operations |    1.95 ms/op |
|      Update meta |  1289 operations |   74.78 ms/op |
|       Put object |   204 operations | 1214.46 ms/op |
|       Get object |   143 operations | 1032.30 ms/op |
|    Delete object |     0 operations |    0.00 ms/op |
| Write into cache |  1567 operations | 1808.73 ms/op |
|  Read from cache |  1286 operations |   62.66 ms/op |
+------------------+------------------+---------------+
```
```
juicefs stats /home/juicefs_mount
------usage------ ----------fuse--------- ----meta--- -blockcache ---object--
 cpu   mem   buf | ops   lat   read write| ops   lat | read write| get   put 
 0.0%   33M    0 |   0     0     0     0 |   0     0 |   0     0 |   0     0 
 0.1%   33M    0 |   0     0     0     0 |   0     0 |   0     0 |   0     0 
 0.2%   34M    0 |   1  0.21     0     0 |   1  0.20 |   0     0 |   0     0 
 2.1%   34M    0 |   5  1.68     0     0 |   5  1.67 |   0     0 |   0     0 
 0.2%   34M    0 |   1  0.73     0     0 |   1  0.73 |   0     0 |   0     0 
 114%  176M   64M|4533  0.06     0   564M|  18  4.32 |   0   560M|   0     0 
 195% 1119M 1028M|  10K 0.37     0  1332M|   2   400 |   0  1328M|   0     0 
27.6% 1138M 1056M| 277  10.5     0    34M|   1  1811 |   0    32M|   0    36M
84.2% 1147M 1028M|6455  0.73     0   806M|   2   301 |   0   812M|   0    28M
19.3% 1153M 1056M| 619  4.38     0    77M|   0     0 |   0    80M|   0  8192K
38.6% 1157M 1060M| 561  9.76     0    70M|   1   301 |   0    64M|   0    48M
25.5% 1163M 1056M| 260  10.6     0    32M|   1  5486 |   0    32M|   0    24M
62.3% 1175M  892M|3173  1.63     0   396M|   2  3413 |   0   392M|   0    44M
54.3% 1177M 1032M|3834  0.61     0   479M|   1  5033 |   0   488M|   0    20M
40.5% 1190M 1032M| 554  9.79     0    69M|   3  3926 |   0    64M|   0    36M
22.8% 1195M 1040M| 266  10.5     0    33M|   1  6543 |   0    36M|   0    28M
41.5% 1203M  804M|1595  2.23     0   199M|   1   300 |   0   208M|   0    36M
11.2% 1204M  364M|   0     0     0     0 |   2  2520 |   0     0 |   0    24M
20.4% 1204M  252M|   1   300     0     0 |   2  2847 |   0     0 |   0    36M
 9.6% 1205M   48M|   0     0     0     0 |   1  6478 |   0     0 |   0    24M
 8.3% 1206M   40M|   1   301     0     0 |   2  3465 |   0     0 |   0    36M
11.3% 1207M   48M|   8  2465     0     0 |  48  7895 |   0     0 |   0    20M
15.9% 1214M  144M| 336  0.91    40M    0 |  22  0.47 |  40M    0 |   0    36M
20.8% 1218M  152M|  67  73.2  8192K    0 |   3  0.23 |   0    32M|  32M   24M
32.4% 1222M  196M| 546  18.6    68M    0 |   2  0.19 |   0    88M|  88M   32M
40.8% 1224M  200M| 869  11.1   108M    0 |   8  0.21 |   0    88M|  88M 8192K
37.0% 1226M  200M| 674  8.98    84M    0 |   3  0.22 |   0   104M| 104M   28M
35.3% 1229M  196M| 804  11.8   100M    0 |   8  0.23 |8192K   88M|  88M   16M
78.0% 1232M  192M|3917  2.04   488M    0 |  10  0.25 | 400M  108M| 108M   24M
45.2% 1235M  200M|2330  3.53   291M    0 |   9  0.22 | 196M   60M|  60M   24M
------usage------ ----------fuse--------- ----meta--- -blockcache ---object--
 cpu   mem   buf | ops   lat   read write| ops   lat | read write| get   put 
 115% 1240M  168M|9542  0.89  1191M    0 |  21  0.26 |1164M 4096K|4096K   32M
95.8% 1244M  168M|8292  0.66  1036M    0 |  21  0.21 |1036M    0 |   0    28M
 105% 1263M   48M|6479  0.47   680M   21M| 699  2.63 | 680M   21M|   0    44M
47.1% 1280M   48M|1372  1.60     0    28M| 913  2.34 |   0    28M|   0    24M
56.4% 1310M   48M|2959  0.19    50M    0 |2141  0.25 |  50M    0 |   0    40M
19.9% 1317M   48M| 286  0.61     0     0 | 285  0.61 |   0     0 |   0    36M
 9.4% 1318M   48M|   1  0.21     0     0 |   1  0.21 |   0     0 |   0    36M
 9.2% 1319M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    36M
 9.6% 1319M   48M|   1  0.21     0     0 |   2  0.24 |   0     0 |   0    32M
 9.8% 1321M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    40M
11.0% 1321M   48M|   1  0.66     0     0 |   1  0.64 |   0     0 |   0    40M
 9.4% 1322M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    36M
11.0% 1323M   48M|   1  0.20     0     0 |   1  0.20 |   0     0 |   0    44M
 9.4% 1324M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    36M
 8.8% 1325M   48M|   1  0.21     0     0 |   1  0.20 |   0     0 |   0    32M
10.5% 1326M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    40M
10.5% 1327M   48M|   1  0.22     0     0 |   1  0.21 |   0     0 |   0    40M
11.3% 1328M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    44M
10.5% 1328M   48M|   1  0.22     0     0 |   2  0.23 |   0     0 |   0    40M
10.4% 1329M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    40M
10.3% 1330M   48M|   1  0.23     0     0 |   1  0.23 |   0     0 |   0    40M
10.7% 1331M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    40M
10.3% 1332M   48M|   1  0.22     0     0 |   1  0.22 |   0     0 |   0    40M
10.2% 1333M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    40M
 9.4% 1335M   48M|   1  0.22     0     0 |   1  0.21 |   0     0 |   0    36M
10.3% 1335M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    40M
10.3% 1336M   48M|   1  0.22     0     0 |   1  0.21 |   0     0 |   0    40M
 9.6% 1337M   48M|   0     0     0     0 |   1  0.27 |   0     0 |   0    36M
10.3% 1338M   48M|   1  0.21     0     0 |   1  0.20 |   0     0 |   0    40M
 7.0% 1338M   48M|   0     0     0     0 |   0     0 |   0     0 |   0    32M
```

### fio test

Pre-warmed up cache directory fio test

```
ls -lah /home/juicefs_mount/fio                                
total 4.1G
drwxr-xr-x 2 root root 4.0K May 26 01:23 .
drwxrwxrwx 3 root root 4.0K May 26 01:15 ..
-rw-r--r-- 1 root root 1.0G May 26 01:16 sequential-read.0.0
-rw-r--r-- 1 root root 1.0G May 26 01:20 sequential-read.1.0
-rw-r--r-- 1 root root 1.0G May 26 01:24 sequential-read.2.0
-rw-r--r-- 1 root root 1.0G May 26 01:23 sequential-read.3.0
```
```
juicefs warmup -p 2 /home/juicefs_mount/fio                    
Warmed up paths count: 1 / 1 [==============================================================]  done      
2022/05/26 01:38:00.362641 juicefs[45285] <INFO>: Successfully warmed up 1 paths [warmup.go:209]
```
```
fio --name=sequential-read --directory=/home/juicefs_mount/fio --rw=read --refill_buffers --bs=4M --size=1G --numjobs=4

sequential-read: (g=0): rw=read, bs=(R) 4096KiB-4096KiB, (W) 4096KiB-4096KiB, (T) 4096KiB-4096KiB, ioengine=psync, iodepth=1
...
fio-3.7
Starting 4 processes
Jobs: 4 (f=4)
sequential-read: (groupid=0, jobs=1): err= 0: pid=47804: Thu May 26 01:38:12 2022
   read: IOPS=179, BW=716MiB/s (751MB/s)(1024MiB/1430msec)
    clat (usec): min=1688, max=15592, avg=5571.03, stdev=1390.95
     lat (usec): min=1689, max=15592, avg=5572.39, stdev=1390.89
    clat percentiles (usec):
     |  1.00th=[ 2278],  5.00th=[ 3884], 10.00th=[ 4359], 20.00th=[ 4621],
     | 30.00th=[ 4948], 40.00th=[ 5276], 50.00th=[ 5473], 60.00th=[ 5669],
     | 70.00th=[ 5932], 80.00th=[ 6325], 90.00th=[ 6783], 95.00th=[ 7439],
     | 99.00th=[ 9241], 99.50th=[14615], 99.90th=[15533], 99.95th=[15533],
     | 99.99th=[15533]
   bw (  KiB/s): min=704512, max=720896, per=24.30%, avg=712704.00, stdev=11585.24, samples=2
   iops        : min=  172, max=  176, avg=174.00, stdev= 2.83, samples=2
  lat (msec)   : 2=0.78%, 4=4.69%, 10=93.75%, 20=0.78%
  cpu          : usr=0.14%, sys=46.61%, ctx=2730, majf=0, minf=1055
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=47805: Thu May 26 01:38:12 2022
   read: IOPS=180, BW=721MiB/s (756MB/s)(1024MiB/1420msec)
    clat (usec): min=2722, max=12203, avg=5530.93, stdev=1193.63
     lat (usec): min=2723, max=12204, avg=5532.24, stdev=1193.64
    clat percentiles (usec):
     |  1.00th=[ 3490],  5.00th=[ 4080], 10.00th=[ 4359], 20.00th=[ 4686],
     | 30.00th=[ 4948], 40.00th=[ 5145], 50.00th=[ 5407], 60.00th=[ 5604],
     | 70.00th=[ 5866], 80.00th=[ 6128], 90.00th=[ 6849], 95.00th=[ 7635],
     | 99.00th=[11994], 99.50th=[12125], 99.90th=[12256], 99.95th=[12256],
     | 99.99th=[12256]
   bw (  KiB/s): min=696320, max=737280, per=24.44%, avg=716800.00, stdev=28963.09, samples=2
   iops        : min=  170, max=  180, avg=175.00, stdev= 7.07, samples=2
  lat (msec)   : 4=3.52%, 10=95.31%, 20=1.17%
  cpu          : usr=0.00%, sys=47.71%, ctx=2751, majf=0, minf=1054
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=47806: Thu May 26 01:38:12 2022
   read: IOPS=179, BW=716MiB/s (751MB/s)(1024MiB/1430msec)
    clat (usec): min=1880, max=13391, avg=5570.19, stdev=1200.55
     lat (usec): min=1881, max=13393, avg=5571.52, stdev=1200.50
    clat percentiles (usec):
     |  1.00th=[ 2540],  5.00th=[ 4113], 10.00th=[ 4424], 20.00th=[ 4752],
     | 30.00th=[ 5014], 40.00th=[ 5211], 50.00th=[ 5473], 60.00th=[ 5735],
     | 70.00th=[ 5997], 80.00th=[ 6259], 90.00th=[ 6849], 95.00th=[ 7177],
     | 99.00th=[ 8717], 99.50th=[12387], 99.90th=[13435], 99.95th=[13435],
     | 99.99th=[13435]
   bw (  KiB/s): min=688128, max=737280, per=24.30%, avg=712704.00, stdev=34755.71, samples=2
   iops        : min=  168, max=  180, avg=174.00, stdev= 8.49, samples=2
  lat (msec)   : 2=0.39%, 4=3.52%, 10=95.31%, 20=0.78%
  cpu          : usr=0.56%, sys=46.61%, ctx=2806, majf=0, minf=1055
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1
sequential-read: (groupid=0, jobs=1): err= 0: pid=47807: Thu May 26 01:38:12 2022
   read: IOPS=179, BW=719MiB/s (754MB/s)(1024MiB/1425msec)
    clat (usec): min=2478, max=11410, avg=5550.24, stdev=1014.45
     lat (usec): min=2480, max=11411, avg=5551.59, stdev=1014.37
    clat percentiles (usec):
     |  1.00th=[ 3392],  5.00th=[ 4146], 10.00th=[ 4424], 20.00th=[ 4817],
     | 30.00th=[ 5080], 40.00th=[ 5276], 50.00th=[ 5473], 60.00th=[ 5669],
     | 70.00th=[ 5866], 80.00th=[ 6259], 90.00th=[ 6718], 95.00th=[ 7111],
     | 99.00th=[ 8225], 99.50th=[ 9241], 99.90th=[11469], 99.95th=[11469],
     | 99.99th=[11469]
   bw (  KiB/s): min=720896, max=761856, per=25.28%, avg=741376.00, stdev=28963.09, samples=2
   iops        : min=  176, max=  186, avg=181.00, stdev= 7.07, samples=2
  lat (msec)   : 4=4.30%, 10=95.31%, 20=0.39%
  cpu          : usr=0.14%, sys=46.98%, ctx=2771, majf=0, minf=1054
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=256,0,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
   READ: bw=2864MiB/s (3003MB/s), 716MiB/s-721MiB/s (751MB/s-756MB/s), io=4096MiB (4295MB), run=1420-1430msec
```

# Destroying JuiceFS Filesystem

Need to get the metadata engine's UUID via jq JSON tool piped query and pass it to `juicefs destroy` command.

```
uuid=$(juicefs status sqlite3:///home/juicefs/myjuicefs.db | jq -r '.Setting.UUID')
systemctl stop juicefs.service juicefs-gateway.service
echo y | juicefs destroy sqlite3:///home/juicefs/myjuicefs.db $uuid
rm -rf /home/juicefs_cache/*
rm -f /home/juicefs/myjuicefs.db
```
```
# remove Cloudflare R2 bucket meta data from bucket s://juicefs/myjuicefs
aws s3 rm --recursive --profile r2 --endpoint-url=$url s3://$cfbucketname/myjuicefs
```

```
echo y | juicefs destroy sqlite3:///home/juicefs/myjuicefs.db $uuid
2022/05/25 04:22:02.572467 juicefs[25759] <INFO>: Meta address: sqlite3:///home/juicefs/myjuicefs.db [interface.go:385]
 volume name: myjuicefs
 volume UUID: 8e5d920c-1aee-4c9c-ac37-feb8c924f4a2
data storage: s3://juicefs/myjuicefs/
  used bytes: 13042229248
 used inodes: 1222
WARNING: The target volume will be destoried permanently, including:
WARNING: 1. ALL objects in the data storage: s3://juicefs/myjuicefs/
WARNING: 2. ALL entries in the metadata engine: sqlite3:///home/juicefs/myjuicefs.db
Proceed anyway? [y/N]: 
Deleted objects count: 4282   
2022/05/25 04:25:38.067123 juicefs[25759] <INFO>: The volume has been destroyed! You may need to delete cache directory manually. [destroy.go:211]
```