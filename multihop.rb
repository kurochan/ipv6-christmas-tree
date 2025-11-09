HOPS = 30

puts "#!/bin/bash"
puts "set -eux"

puts ""
puts "# setup multihop"
puts ""

puts "# r1"
puts "sysctl -w net.ipv6.conf.all.forwarding=1"
puts "sysctl -w net.ipv6.conf.default.forwarding=1"
puts "ip netns add r1"
puts "ip netns exec r1 sysctl -w net.ipv6.conf.all.forwarding=1"
puts "ip netns exec r1 sysctl -w net.ipv6.conf.default.forwarding=1"
puts "ip link add veth-h-r1 type veth peer name veth-r1-h"
puts "ip link set veth-h-r1 up"
puts "ip link set veth-r1-h netns r1"
puts "ip -n r1 link set veth-r1-h up"
puts "ip -6 addr add ${ipv6_prefix}2/127 dev veth-h-r1"
puts "ip -6 -n r1 addr add ${ipv6_prefix}3/127 dev veth-r1-h"
puts "ip -6 -n r1 route add default dev veth-r1-h via ${ipv6_prefix}2"

(HOPS - 1).times do |i|
  r = i + 2
  rt = "r#{r}"
  rtp = "r#{r - 1}"

  puts ""
  puts "# #{rt}"
  puts "ip netns add #{rt}"
  puts "ip netns exec #{rt} sysctl -w net.ipv6.conf.all.forwarding=1"
  puts "ip netns exec #{rt} sysctl -w net.ipv6.conf.default.forwarding=1"
  puts "ip link add veth-#{rtp}-#{rt} type veth peer name veth-#{rt}-#{rtp}"
  puts "ip link set veth-#{rtp}-#{rt} netns #{rtp}"
  puts "ip -n #{rtp} link set veth-#{rtp}-#{rt} up"
  puts "ip link set veth-#{rt}-#{rtp} netns #{rt}"
  puts "ip -n #{rt} link set veth-#{rt}-#{rtp} up"
  puts "ip -6 -n #{rtp} addr add ${ipv6_prefix}#{(r * 2).to_s(16)}/127 dev veth-#{rtp}-#{rt}"
  puts "ip -6 -n #{rt} addr add ${ipv6_prefix}#{(r * 2 + 1).to_s(16)}/127 dev veth-#{rt}-#{rtp}"

  puts "ip -6 -n #{rt} route add default dev veth-#{rt}-#{rtp} via ${ipv6_prefix}#{(r * 2).to_s(16)}"
end

puts ""
puts "# static routes"

puts "# r1"
(HOPS - 1).times do |i|
  r = i + 2
  puts "ip -6 route add ${ipv6_prefix}#{(r * 2).to_s(16)}/127 dev veth-h-r1 via ${ipv6_prefix}3 # r#{r}"
end

HOPS.times do |i|
  r = i + 1
  rt = "r#{r}"
  rtn = "r#{r + 1}"

  next if (HOPS - r - 1) <= 0

  puts ""
  puts "# #{rt}"

  (HOPS - r - 1).times do |j|
    rr = r + j + 2
    rrt = "r#{rr}"
    puts "ip -6 -n #{rt} route add ${ipv6_prefix}#{(rr * 2).to_s(16)}/127 dev veth-#{rt}-#{rtn} via ${ipv6_prefix}#{(r * 2 + 3).to_s(16)} # #{rrt}"
  end
end
