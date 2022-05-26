# JuiceFS Setup

Installing [JuiceFS](https://juicefs.com/docs/community/introduction/) high performanced POSIX compatible shared file system on Centmin Mod LEMP stack using [JuiceFS caching](https://juicefs.com/docs/community/cache_management) with [Cloudflare R2](https://blog.cloudflare.com/r2-open-beta/) - S3 compatible object storage and local sqlite3 Metadata Engine.

JuiceFS implements an architecture that seperates "data" and "metadata" storage. When using JuiceFS to store data, the data itself is persisted in [object storage](https://juicefs.com/docs/community/how_to_setup_object_storage/) (e.g., Amazon S3, OpenStack Swift, Ceph, Azure Blob or MinIO), and the corresponding metadata can be persisted in various databases ([Metadata Engines](https://juicefs.com/docs/community/databases_for_metadata/)) such as Redis, Amazon MemoryDB, MariaDB, MySQL, TiKV, etcd, SQLite, KeyDB, PostgreSQL, BadgerDB, or FoundationDB.

* [Install JuiceFS binary](#install-juicefs-binary)
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
* [Destroying JuiceFS Filesystem](#destroying-juicefs-filesystem)

# Install JuiceFS binary

```
cd /svr-setup

JFS_LATEST_TAG=$(curl -s https://api.github.com/repos/juicedata/juicefs/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v')

wget "https://github.com/juicedata/juicefs/releases/download/v${JFS_LATEST_TAG}/juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz"

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
    --trash-days 1 \
    --block-size 4096 \
    sqlite3://myjuicefs.db myjuicefs
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
juicefs mount sqlite3://myjuicefs.db /home/juicefs_mount \
--cache-dir /home/juicefs_cache \
--cache-size 102400 \
--buffer-size 1024 \
--open-cache 0 \
--attr-cache 1 \
--entry-cache 1 \
--dir-entry-cache 1 \
--cache-partial-only false \
--free-space-ratio 0.1 \
--writeback true \
--backup-meta 1h \
--no-usage-report \
--max-uploads 10 \
--max-deletes 2 \
--backup-meta 1h \
--log /var/log/juicefs.log \
--get-timeout 300 \
--put-timeout 900 \
--io-retries 90 \
--prefetch 4 -d
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
  "sqlite3://myjuicefs.db" \
  /home/juicefs_mount \
  --no-usage-report \
  --writeback true \
  --cache-size 102400 \
  --cache-dir /home/juicefs_cache \
  --buffer-size 1024 \
  --open-cache 0 \
  --attr-cache 1 \
  --entry-cache 1 \
  --dir-entry-cache 1 \
  --cache-partial-only false \
  --free-space-ratio 0.1 \
  --max-uploads 10 \
  --max-deletes 2 \
  --backup-meta 1h \
  --log /var/log/juicefs.log \
  --get-timeout 300 \
  --put-timeout 900 \
  --io-retries 90 \
  --prefetch 4

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
           └─26947 /usr/local/bin/juicefs mount sqlite3://myjuicefs.db /home/juicefs_mount --no-usage-report --writeback --cache-size 102400 --cache-dir /home/juicefs_cache --free-space-ratio 0.1 --max-uploads 10 --max-deletes 2 --backup-meta 1h --log /var/log/juicefs.log -                                                                                  

May 25 04:26:33 hostname systemd[1]: Started JuiceFS.
May 25 04:26:33 hostname juicefs[26947]: 2022/05/25 04:26:33.125185 juicefs[26947] <INFO>: Meta address: sqlite3://myjuicefs.db [interface.go:385]
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
--writeback true \
--backup-meta 1h \
--no-usage-report \
--buffer-size 1024 sqlite3://myjuicefs.db localhost:3777
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
--writeback true \
--backup-meta 1h \
--no-usage-report \
--buffer-size 1024 sqlite3://myjuicefs.db 0.0.0.0:3777
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
  --writeback true \
  --cache-size 102400 \
  --cache-dir /home/juicefs_cache \
  --attr-cache 1 \
  --entry-cache 0 \
  --dir-entry-cache 1 \
  --prefetch 1 \
  --free-space-ratio 0.1 \
  --max-uploads 10 \
  --max-deletes 2 \
  --backup-meta 1h \
  --get-timeout 300 \
  --put-timeout 900 \
  --io-retries 90 \
  --buffer-size 1024 \
  "sqlite3://myjuicefs.db" \
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
           └─26957 /usr/local/bin/juicefs gateway --no-usage-report --writeback --cache-size 102400 --cache-dir /home/juicefs_cache --free-space-ratio 0.1 --max-uploads 10 --max-deletes 2 --backup-meta 1h --get-timeout 300 --put-timeout 900 --io-retries 90 --prefetch 4 --bu                                                    

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
juicefs status sqlite3://myjuicefs.db
2022/05/25 04:50:06.356669 juicefs[33155] <INFO>: Meta address: sqlite3://myjuicefs.db [interface.go:385]
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

# JuiceFS Benchmarks

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
uuid=$(juicefs status sqlite3://myjuicefs.db | jq -r '.Setting.UUID')
systemctl stop juicefs.service juicefs-gateway.service
echo y | juicefs destroy sqlite3://myjuicefs.db $uuid
rm -rf /home/juicefs_cache/*
rm -f /home/juicefs/myjuicefs.db
```

```
echo y | juicefs destroy sqlite3://myjuicefs.db $uuid
2022/05/25 04:22:02.572467 juicefs[25759] <INFO>: Meta address: sqlite3://myjuicefs.db [interface.go:385]
 volume name: myjuicefs
 volume UUID: 8e5d920c-1aee-4c9c-ac37-feb8c924f4a2
data storage: s3://juicefs/myjuicefs/
  used bytes: 13042229248
 used inodes: 1222
WARNING: The target volume will be destoried permanently, including:
WARNING: 1. ALL objects in the data storage: s3://juicefs/myjuicefs/
WARNING: 2. ALL entries in the metadata engine: sqlite3://myjuicefs.db
Proceed anyway? [y/N]: 
Deleted objects count: 4282   
2022/05/25 04:25:38.067123 juicefs[25759] <INFO>: The volume has been destroyed! You may need to delete cache directory manually. [destroy.go:211]
```