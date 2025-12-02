# IPv6 Christmas Tree

```
$ traceroute6 -I xmas.example.com
traceroute6 to xmas.example.com (xxxx:xxxx::19) from xxxx:xxxx::, 64 hops max, 20 byte packets
 1  xxxx:xxxx::1  8.391 ms  5.644 ms  5.918 ms
 2  xxxx:xxxx::1  6.514 ms  5.528 ms  6.288 ms
 3  xxxx:xxxx::1  6.729 ms  7.026 ms  7.309 ms
 4  xxxx:xxxx::1  9.664 ms  14.524 ms  14.464 ms
 5  xxxx:xxxx::1  7.590 ms  6.153 ms  6.862 ms
 6  xxxx:xxxx::1  9.130 ms  9.031 ms  8.883 ms
 7  xxxx:xxxx::1  9.227 ms  10.300 ms  8.819 ms
 8  xxxx:xxxx::1  7.512 ms  6.667 ms  7.284 ms
 9  xxxx:xxxx::1  10.555 ms  33.063 ms  78.847 ms
10  0-----------------0.example.com  8.739 ms  6.950 ms  7.994 ms
11  0--------x--------0.example.com  9.037 ms  8.270 ms  7.797 ms
12  0-------ooo-------0.example.com  8.212 ms  8.040 ms  8.353 ms
13  0------oo0oo------0.example.com  9.030 ms  11.587 ms  7.980 ms
14  0-----o0o-o0o-----0.example.com  7.795 ms  7.918 ms  7.897 ms
15  0----oo0ooo0oo----0.example.com  8.520 ms  7.969 ms  8.056 ms
16  0---o0ooo-ooo0o---0.example.com  7.617 ms  8.111 ms  9.826 ms
17  0--oo0ooooooo0oo--0.example.com  9.249 ms  8.238 ms  7.926 ms
18  0-oooooo0oooooooo-0.example.com  9.306 ms  11.779 ms  8.018 ms
19  0------iiiii------0.example.com  8.117 ms  7.733 ms  9.737 ms
20  0------ii-ii------0.example.com  11.239 ms  10.079 ms  8.980 ms
21  0------iicii------0.example.com  11.435 ms  8.265 ms  9.978 ms
22  1-----------------1.example.com  9.648 ms  7.411 ms  8.135 ms

```

Terraform stack that builds a single Ubuntu EC2 instance with a /80 IPv6 prefix, then turns it into a 32‑hop IPv6 router chain to draw an ASCII Christmas tree on DNS. Cloudflare AAAA records point each “pixel” in `christmas_tree.txt` at a successive IPv6 address so you can traceroute through the lights.

## What gets created
- VPC with IPv6, one public subnet, internet gateway, and default routes for IPv4/IPv6.
- Security group that allows ICMP/ICMPv6 (for ping/traceroute) and UDP 33000–35000 over IPv6.
- Dedicated ENI with a fixed IPv6 /80 prefix assigned to the EC2 instance.
- Ubuntu 24.04 EC2 (t3.micro by default) that:
  - Configures the /80 via netplan.
  - Downloads and runs `multihop.sh` from a private S3 bucket.
  - `multihop.sh` creates 32 Linux network namespaces (`r1`–`r32`) and links them in series, adds static routes for every hop, and installs nftables rules to rate-limit ICMPv6 echo requests.
- Two S3 buckets: one for Terraform state (remote backend) and one to host the generated script.
- Cloudflare AAAA records:
  - `xmas.<domain>` points to the end of the chain.
  - Each line in `christmas_tree.txt` becomes a hostname (e.g., `0-----------------0.<domain>`) mapped to the next IPv6 address in the /80, forming the tree.

## Prerequisites
- Terraform 1.6+.
- AWS credentials with rights to create VPC/EC2/IAM/S3.
- Cloudflare API token with DNS edit permission for your zone.
- Ruby (optional) if you want to regenerate `multihop.sh.tftpl` from `multihop.rb`.

## Configuration
Create `terraform.tfvars` (or set equivalent environment variables) with your values:

```hcl
bucket               = "ipv6-christmas-tree-tfstate-<unique-suffix>" # S3 bucket for the Terraform backend
cloudflare_api_token = "<cloudflare_api_token>"
zone_id              = "<cloudflare_zone_id>"
domain               = "example.com"
```

The backend block expects the bucket name at init time. Pass it explicitly:

```sh
terraform init -backend-config="bucket=<your-tfstate-bucket>"
```

## Deploy
```sh
terraform init -backend-config="bucket=<your-tfstate-bucket>"
terraform apply
```

Key outputs:
- `tfstate_bucket_name` – created/expected S3 bucket for state.
- `script_bucket_name` – S3 bucket hosting `multihop.sh`.
- `ipv6_ec2_prefix` / `ipv6_ec2` – IPv6 prefix and first address on the instance.
- `ipv6_vpc_block`, `ipv6_subnet_block` – assigned IPv6 ranges.

After apply, Cloudflare will contain `xmas.<domain>` and one record per line in `christmas_tree.txt`. Pinging or tracerouting those names walks the multi-hop chain to light up the tree.

## Regenerating the multihop script
`multihop.sh.tftpl` is generated from `multihop.rb` (set `HOPS` to change the length):

```sh
ruby multihop.rb > multihop.sh.tftpl
```

## Cleanup
```sh
terraform destroy
```

## Notes and limits
- Costs: One EC2 instance, two S3 buckets, and Cloudflare DNS records. Destroy when done.
- The EC2 netplan assigns `${ipv6_prefix}1/80`; the script consumes sequential addresses for each hop, so avoid reusing the prefix elsewhere.
- nftables rules drop oversized echo requests and rate-limit pings per /56 source prefix to keep the host stable under public probing.
