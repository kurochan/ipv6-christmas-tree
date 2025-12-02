# IPv6 Christmas Tree (日本語)

Terraform で Ubuntu EC2 に /80 の IPv6 プレフィックスを割り当て、32 ホップの IPv6 ルーター鎖を作り、DNS AAAA レコードで ASCII のクリスマスツリーを描きます。`christmas_tree.txt` の各行がホスト名となり、/80 内の連番アドレスに紐づきます。`traceroute` すると光るツリーが見えます。

## 生成されるもの
- IPv6 有効の VPC とパブリックサブネット、インターネットゲートウェイ、IPv4/IPv6 のデフォルトルート。
- ICMP/ICMPv6 と IPv6 UDP 33000–35000 を許可するセキュリティグループ。
- EC2 用 ENI に固定 /80 IPv6 プレフィックスを付与。
- Ubuntu 24.04 EC2 (デフォルト t3.micro) が実行すること:
  - netplan で /80 を設定 (`${ipv6_prefix}1/80`)。
  - S3 から `multihop.sh` を取得して実行。
  - `multihop.sh` が 32 個のネットワーク名前空間 (`r1`–`r32`) を直列に接続し、全ホップの静的ルートを追加し、ICMPv6 Echo を rate-limit する nftables ルールを設定。
- S3 バケット 2 つ: Terraform state 用とスクリプト配布用。
- Cloudflare AAAA レコード:
  - `xmas.<domain>` はチェーン終端。
  - `christmas_tree.txt` の各行が `<line>.<domain>` として次の IPv6 アドレスに割り当てられ、ツリーを構成。

## 前提条件
- Terraform 1.6+
- VPC/EC2/IAM/S3 を作成できる AWS 資格情報
- ゾーンの DNS 編集権限を持つ Cloudflare API トークン
- Ruby (任意) — `multihop.rb` から `multihop.sh.tftpl` を再生成したい場合

## 設定
`terraform.tfvars` などで値を指定します (例):

```hcl
bucket               = "ipv6-christmas-tree-tfstate-<unique-suffix>" # Terraform backend 用 S3 バケット
cloudflare_api_token = "<cloudflare_api_token>"
zone_id              = "<cloudflare_zone_id>"
domain               = "example.com"
```

backend のバケットは init 時に必要です。次のように渡します:

```sh
terraform init -backend-config="bucket=<your-tfstate-bucket>"
```

## デプロイ
```sh
terraform init -backend-config="bucket=<your-tfstate-bucket>"
terraform apply
```

主な出力:
- `tfstate_bucket_name` – state 用 S3 バケット名
- `script_bucket_name` – `multihop.sh` を置くバケット名
- `ipv6_ec2_prefix` / `ipv6_ec2` – EC2 に付く IPv6 プレフィックスと最初のアドレス
- `ipv6_vpc_block`, `ipv6_subnet_block` – 割り当てられた IPv6 ブロック

Apply 後、Cloudflare に `xmas.<domain>` と `christmas_tree.txt` 各行のレコードが作成されます。これらへ ping / traceroute すると多段経路を通ってツリーが光ります。

## multihop スクリプトの再生成
`multihop.sh.tftpl` は `multihop.rb` から生成できます (`HOPS` を変更すると長さが変わります):

```sh
ruby multihop.rb > multihop.sh.tftpl
```

## クリーンアップ
```sh
terraform destroy
```

## 注意点とコスト
- 課金対象: EC2 1 台、S3 バケット 2 つ、Cloudflare の DNS レコード。終わったら destroy を推奨。
- EC2 の netplan は `${ipv6_prefix}1/80` を使い、スクリプトは連番アドレスを順に消費します。プレフィックスを他用途と共有しないでください。
- nftables で大きな Echo Request を破棄し、/56 単位で ping を rate-limit しています。公開後の過負荷を抑制するための設定です。
