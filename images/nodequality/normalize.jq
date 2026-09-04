# Fold four check results and one price list into the document the worker
# renders.
#
# The checks answer in their own shapes and their own units — fio reports KiB/s,
# the IP check reports booleans and short English words, the hardware check
# reports bytes. The page wants rows with a label, a value and a tone. This is
# where that translation happens, once, in the container that ran them, so the
# worker only ever renders and the published JSON is readable by the person
# who has to edit it.
#
# Two conventions the renderer depends on:
#
#   "@key"   is looked up in the worker's language table, so the label switches
#            with the page. Anything else is printed as it stands.
#   tone     is one of ink/sub/mute/acc/ok/warn/bad/none — never a colour.
#
# Values that come back as a fixed vocabulary (a boolean, "Yes", "Failed") are
# mapped to "@keys" so they switch language too. Values that are prose or a
# proper noun — an AS name, a city — stay as the check wrote them, which is why
# collection defaults to English.

def blank: . == null or . == "" or . == "null" or . == "N/A" or . == "-";

# Both speed tables arrive in bits per second — Net.sh's own report divides by
# a million to print "588 Mbps" from 588313440, and the page says Mbps in its
# column head. Printing the raw figure was putting a nine-digit number in a
# column three characters wide. Truncated, not rounded, so the page and the
# report it came from agree: 659032 b/s is "0" in both.
def mbps: if blank then "" else ((tostring | tonumber?) as $n
  | if $n == null then "" else ($n / 1000000 | floor | tostring) end) end;

# The speed tones the design uses, read off the mockup: a link under 100 Mbps
# to a Chinese city is the bad case, under 500 is the middling one.
def speed_tone: (tostring | tonumber?) as $n
  | if $n == null then "sub" elif $n < 100000000 then "bad"
    elif $n < 500000000 then "warn" else "ok" end;
def clean: if blank then null else . end;

# A row that disappears rather than printing "null" at a customer.
def row($k; $v; $tone): ($v | clean) as $x
  | if $x == null then empty else { k: $k, v: ($x | tostring), tone: $tone } end;
def row($k; $v): row($k; $v; "ink");

def yesno: if . == true then "@v_yes" elif . == false then "@v_no" else "@v_none" end;
def enabled: if . == true then "@v_enabled" elif . == false then "@v_no" else null end;
def tone_bool: if . == true then "warn" else "none" end;

def round1: if . == null then null else (. * 10 | round) / 10 end;

def bytes_h: if . == null then null
  else (. / 1073741824) | round1 | tostring + " GiB" end;

# fio reports bandwidth in KiB/s.
def bw_h: if . == null then null
  else (. * 1024) as $b
  | if $b >= 1000000000 then (($b / 1000000000) | round1 | tostring) + " GB/s"
    else (($b / 1000000) | round1 | tostring) + " MB/s" end
  end;

def iops_h: if . == null then null
  elif . >= 1000 then ((. / 1000) | round1 | tostring) + "k"
  else (. | round | tostring) end;

# A percentage for the risk bars. The checks answer either a bare number or
# something like "0.07%", and the scales differ per database, so the bar is
# capped rather than pretending they are comparable.
def pct: if . == null then null
  else (tostring | sub("%$"; "") | tonumber? // null)
  | if . == null then null elif . > 100 then 100 elif . < 2 then 2 else . end
  end;


# ------------------------------------------------------------------- routes
#
# nexttrace returns a list of probes per TTL; the first that answered is the
# hop. RTT is nanoseconds.
def route_hops: [ (.hops // [])[]
  | ( [ .[] | select(.Success == true) ][0] ) as $p
  | if $p == null then
      { ttl: null, ip: "*", asn: "", country: "", prov: "", city: "", owner: "", rtt: null }
    else
      { ttl: $p.TTL,
        ip: ($p.Address.IP // "*"),
        asn: ((($p.Geo.asnumber // "") | tostring) as $a
              | if $a == "" then "" else "AS" + $a end),
        country: ($p.Geo.country // ""),
        prov:    ($p.Geo.prov // ""),
        city:    ($p.Geo.city // ""),
        owner:   (($p.Geo.owner // "") | ltrimstr(" ") | rtrimstr(" ")),
        rtt: $p.RTT }
    end ];

# Mainland, which for a backhaul route means not Hong Kong, Macau or Taiwan.
def is_cn: ((.country // "") | test("中国|China"))
       and ((((.country // "") + (.prov // "") + (.city // ""))
             | test("香港|澳门|台湾|Hong Kong|Macau|Taiwan")) | not);

# Net.sh's naming table, transcribed rather than approximated. $h is the hop
# list and $i the index of the first mainland hop.
def route_name($h; $i):
  ([ $h[] | .asn ] | join(" ")) as $all
  | (if (($h[$i].asn) // "") == "AS17676" then $i + 1 else $i end) as $j
  | (($h[$j].asn) // "") as $a
  # CN2 is GIA unless the first hop past the CN2 block is a 202.97 address.
  | ([ $h[$j:][] | select(.asn != "AS4809" and .asn != "AS23764") ][0]) as $after
  | ((($after.ip) // "") | startswith("202.97")) as $gt
  | if   $a == "AS4134"  then "163"
    elif $a == "AS4837"  then (if $j > 0 and (($h[$j-1].asn) // "") == "AS10099"
                               then "10099" else "4837" end)
    elif $a == "AS58453" then "CMI"
    elif $a == "AS58807" then "CMIN2"
    elif $a == "AS9808"  then (if ($all | test("AS58807")) then "CMIN2" else "CMI" end)
    elif $a == "AS9929"  then "9929"
    elif $a == "AS10099" then (if ($all | test("AS9929")) then "9929" else "10099" end)
    elif $a == "AS4809"  then (if ($all | test("AS23764")) then "CTGGIA"
                               elif $gt then "CN2GT" else "CN2GIA" end)
    elif $a == "AS23764" then (if $gt then "CN2GT" else "CTGGIA" end)
    elif $a == "AS4538"  then "CERNET"
    elif $a == "AS7497"  then "CSTNET"
    elif ($all | test("AS58807")) then "CMIN2"
    elif ($all | test("AS9929"))  then "9929"
    elif ($all | test("AS10099")) then "10099"
    elif ($all | test("AS4809"))  then "CN2"
    elif ($all | test("AS9808"))  then "CMI"
    elif ($all | test("AS4134"))  then "163"
    elif ($all | test("AS4837"))  then "4837"
    else "NoData" end;

# The carrier it left on: the last hop before China that names an owner.
def route_carrier($h; $i):
  ([ $h[0:$i][] | select((.owner | length) > 0) ] | last) as $x
  | if $x == null then "" else ($x.owner | split(" ")[0]) end;

# A premium route earns the accent. One that could not be read stays grey
# rather than being guessed at.
def route_tone($n):
  if (["CN2GIA", "CTGGIA", "CMIN2", "9929"] | index($n)) then "ok"
  elif (["NoData", "Hidden", "Unknown", ""] | index($n)) then "mute"
  else "ink" end;

def route_of: route_hops as $h
  | ([ range(0; ($h | length)) | select($h[.] | is_cn) ][0]) as $i
  | { city: .city, isp: .isp, hops: $h, cn: $i,
      name: (if $i == null or $i == 0 then "Hidden" else route_name($h; $i) end),
      carrier: (if $i == null then "" else route_carrier($h; $i) end) };

def route_label: (if (.carrier | length) > 0 then .carrier + " → " else "" end) + .name;

$ip[0] as $ip | $hw[0] as $hw | $net[0] as $net | $shop[0] as $shop
| ([ ($route[0] // [])[] | route_of ]) as $routes

| ($ip.Info // {}) as $info
| ($hw.CPU // {}) as $cpu
| (($hw.CPU // {}).benchmarks.geekbench5 // {}) as $gb
| ($hw.Memory // {}) as $mem
| ($hw.Disk // {}) as $disk
| (($disk.benchmarks // {}).fio // {}) as $fio
| ($net.BGP // {}) as $bgp
| ($net.Local // {}) as $local

# ------------------------------------------------------------------ the page

| {
  lang: ($shop.lang // "zh"),

  shop: (($shop.shop // {}) + {
    ipv4: ($ip.Head.IP // null | clean),
    collected: ($ip.Head.Time // $hw.Head.Time // null | clean),
  } | with_entries(select(.value != null))),

  report: {

    # ------------------------------------------------------------- basic
    hw: [
      row("@k_cpu";    $cpu.model),
      row("@k_cores";  (if ($cpu.topology.cores // null) == null then null
                        else "\($cpu.topology.cores | floor) @ \($cpu.frequency_mhz.current // 0 | round) MHz" end)),
      row("@k_ram";    $mem.summary.total),
      row("Swap";      ($mem.swap.total | clean)),
      row("@k_disk";   ($disk.summary.total_bytes | bytes_h)),
      row("AES-NI";    ($cpu.features.aes | enabled);
                       (if $cpu.features.aes then "ok" else "mute" end)),
      row("VM-x / AMD-V"; ($cpu.features.virtualization | enabled);
                       (if $cpu.features.virtualization then "ok" else "mute" end))
    ],

    os: [
      row("@k_distro"; $hw.OS.name),
      row("@k_kernel"; $hw.OS.kernel),
      row("@k_virt";   $hw.OS.virtualization.type),
      row("@k_uptime"; $hw.OS.uptime; "sub"),
      row("Arch";      $hw.OS.architecture; "sub")
    ],

    isp: [
      row("ISP";         $info.Organization),
      row("ASN";         (if ($info.ASN | clean) == null then null else "AS\($info.ASN)" end)),
      row("@k_loc";      ($info.City.Name | clean) // ($info.City.Subdivisions | clean)),
      row("@k_country";  $info.Region.Name),
      row("@k_tz";       $info.TimeZone)
    ],

    # -------------------------------------------------------------- perf
    # Geekbench is not run here — it is a glibc binary and this is musl — so
    # the CPU tiles are sysbench's. "SYSBENCH" is a product name and reads the same in all four languages,
    # so the CPU tiles carry it literally and the memory pair keeps its
    # translated label. The memory numbers are the hardware check's own
    # measurement, not sysbench's, and the sub-line says so rather than
    # crediting the wrong tool.
    # Four tiles, and the design's are Geekbench's when there are any. The
    # image ships geekbench5 now, so the sysbench pair is the fallback for a
    # machine where it did not run — an arm64 box, or --no-geekbench — rather
    # than the only thing on offer.
    cpu: [
      (if ($gb.single // null) != null then
        { label: "@l_gb_s", value: ($gb.single | tostring), sub: "Geekbench 5" } else empty end),
      (if ($gb.multi // null) != null then
        { label: "@l_gb_m", value: ($gb.multi | tostring),
          sub: (if ($cpu.topology.threads // 1) <= 1 then "@v_singlecore"
                else "\($cpu.topology.threads) threads" end) } else empty end),
      (if ($gb.single // null) == null and ($cpu.benchmarks.sysbench.single // null) != null then
        { label: "SYSBENCH 1-THREAD", value: ($cpu.benchmarks.sysbench.single | round | tostring), sub: "events/s" } else empty end),
      (if ($gb.multi // null) == null and ($cpu.benchmarks.sysbench.multi // null) != null then
        { label: "SYSBENCH \($cpu.topology.threads // 1)-THREAD", value: ($cpu.benchmarks.sysbench.multi | round | tostring),
          sub: "events/s" } else empty end),
      (if ($mem.benchmarks.read_MBps // null) != null then
        { label: "@l_mem_r", value: "\($mem.benchmarks.read_MBps | round) MB/s",
          sub: (if ($mem.benchmarks.latency_ns // null) == null then "HardwareQuality" else "\($mem.benchmarks.latency_ns) ns" end) } else empty end),
      (if ($mem.benchmarks.write_MBps // null) != null then
        { label: "@l_mem_w", value: "\($mem.benchmarks.write_MBps | round) MB/s", sub: "HardwareQuality" } else empty end)
    ],

    # The link the design calls 原始结果 ↗. Geekbench uploads its own run to
    # get a score at all, and this is the URL it hands back.
    geekbench_url: (($gb.url // "") | clean),

    # The sub-heading names the tools the tiles actually came from.
    perf_note: (if ($gb.single // null) != null
                then "Geekbench 5 · SysBench · fio" else "SysBench · fio" end),

    # One line per block size and queue depth the check actually measured,
    # read against write, the way the design reads it.
    fio: [
      { bs: "4K q1",  r: $fio.randread."4K_q1",  w: $fio.randwrite."4K_q1" },
      { bs: "4K q32", r: $fio.randread."4K_q32", w: $fio.randwrite."4K_q32" },
      { bs: "1M q1",  r: $fio.read."1M_q1",      w: $fio.write."1M_q1" },
      { bs: "1M q8",  r: $fio.read."1M_q8",      w: $fio.write."1M_q8" }
    ] | map(select(.r != null or .w != null) | {
        bs,
        read:  ((.r.bw | bw_h) // "—"),
        write: ((.w.bw | bw_h) // "—"),
        total: (((.r.bw // 0) + (.w.bw // 0)) | bw_h),
        iops:  (((.r.iops // 0) + (.w.iops // 0)) | iops_h)
      }),

    # ---------------------------------------------------------------- ip
    ip_note: (if ($ip.Head.Version | clean) == null then null
              else "IPQuality \($ip.Head.Version)" end),

    ipBasic: [
      row("@k_as";      (if ($info.ASN | clean) == null then null else "AS\($info.ASN)" end); "acc"),
      row("@k_org";     $info.Organization),
      row("@k_coord";   $info.DMS; "sub"),
      row("@k_city";    $info.City.Name),
      row("@k_usedin";  (if ($info.Region.Code | clean) == null then null
                         else "[\($info.Region.Code)] \($info.Region.Name)" end)),
      row("@k_regin";   (if ($info.RegisteredRegion.Code | clean) == null then null
                         else "[\($info.RegisteredRegion.Code)] \($info.RegisteredRegion.Name)" end)),
      row("@k_tz";      $info.TimeZone),
      row("@k_iptype";  $info.Type; "ok")
    ],

    risk: [ ($ip.Score // {}) | to_entries[]
            | select(.value | blank | not)
            | { db: .key, score: (.value | tostring), w: "\((.value | pct) // 2)%",
                level: (if ((.value | pct) // 0) <= 25 then "@v_low" else "@v_other" end),
                tone: (if ((.value | pct) // 0) <= 25 then "ok"
                       elif ((.value | pct) // 0) <= 60 then "warn" else "bad" end) } ],

    usage: [ (($ip.Type // {}).Usage // {}) | to_entries[]
             | select(.value | blank | not)
             | { db: .key, type: .value, tone: "ok" } ],

    # The factor grid: one column per database, one row per thing they flag.
    # CountryCode is pulled out as its own row because it is the only one
    # whose answer is a place rather than a yes or a no.
    factorDbs: [ (($ip.Factor // {}) | to_entries | .[0].value // {} | keys_unsorted[]) ],

    factors: ([ (($ip.Factor // {}).CountryCode // {}) as $cc
                | if ($cc | length) == 0 then empty else
                  { name: "@f_region",
                    cells: [ $cc | to_entries[] | { v: (if (.value | blank) then "@v_none" else "[\(.value)]" end),
                                                    tone: (if (.value | blank) then "none" else "ok" end) } ] }
                  end ]
              + [ ($ip.Factor // {}) | to_entries[]
                  | select(.key != "CountryCode")
                  | { name: (
                        { "Proxy": "@f_proxy", "VPN": "@f_vpn", "Server": "@f_server",
                          "Abuser": "@f_abuse", "Robot": "@f_bot" }[.key] // .key),
                      cells: [ .value | to_entries[] | { v: (.value | yesno), tone: (.value | tone_bool) } ] } ]),

    unlock: [ ($ip.Media // {}) | to_entries[]
              | select(.value.Status | blank | not)
              | { name: .key,
                  status: ({ "Yes": "@v_unlocked", "Block": "@v_blocked", "Failed": "@v_failed",
                             "APPOnly": "@v_apponly" }[.value.Status] // .value.Status),
                  detail: ([ (.value.Region | clean), (.value.Type | clean) ] | map(select(. != null)) | join(" · ")),
                  tone: (if .value.Status == "Yes" then "ok"
                         elif .value.Status == "Block" or .value.Status == "Failed" then "bad"
                         else "warn" end) } ],

    # `//` treats false as absent, and false is the answer this row exists to
    # carry: a blocked port 25 is what a buyer needs to see, and writing it as
    # `.Port25 // null` deleted the row on exactly the machines that have one.
    # So the test is whether the key is a boolean, not whether it is truthy.
    port25: (($ip.Mail // {}) as $mail
             | if ($mail.Port25 | type) != "boolean" then null
               else { v: (if $mail.Port25 then "@v_yes" else "@v_port_blocked" end),
                      tone: (if $mail.Port25 then "ok" else "bad" end) } end),

    blacklist: (($ip.Mail.DNSBlacklist // {}) as $b
      | if ($b | length) == 0 then [] else [
          row("@k_valid";     $b.Total),
          row("@k_normal";    $b.Clean; "ok"),
          row("@k_flagged";   $b.Marked; "warn"),
          row("@k_blacklist"; $b.Blacklisted; "bad")
        ] | map({ k, v, tone }) end),

    # ---------------------------------------------------------- net/route
    net_note: (if ($net.Head.Version | clean) == null then null
               else "NetQuality \($net.Head.Version)" end),

    bgp: [
      row("@k_registry";  $bgp.RIR),
      row("@k_asname";    (if ($bgp.ASN | clean) == null then null
                           else "AS\($bgp.ASN) \($bgp.Organization // "")" | rtrimstr(" ") end)),
      row("@k_prefix";    (if ($bgp.Prefix | clean) == null then null else "/\($bgp.Prefix)" end)),
      row("@k_regmod";    (if ($bgp.ModDate | clean) == null then null
                           else "\(($bgp.RegDate | clean) // "—") / \($bgp.ModDate)" end)),
      row("@k_region";    ([($bgp.Country | clean), ($bgp.SubRegion | clean)]
                           | map(select(. != null)) | join(" · ") | clean)),
      row("@k_neighbors"; (if ($bgp.NeighborinTotal | clean) == null then null
                           else "\($bgp.NeighborActive) / \($bgp.NeighborinTotal) · \($bgp.IPActive) / \($bgp.IPinTotal)" end))
    ],

    # Symmetric NAT is the one line here a buyer might care about, so it is the
    # one that gets a tone rather than being another grey row.
    local: [
      row("@k_nat";   ([($local.NATDescribe | clean), ($local.Mapping | clean)]
                       | map(select(. != null)) | join(" · ") | clean);
                      (if ($local.NATDescribe // "") == "Symmetric" then "bad" else "ok" end)),
      row("@k_cc";    $local.TCPCongestionControl),
      row("@k_qdisc"; $local.QueueDiscipline),
      row("@k_rmem";  $local.TCPReceiveBuffer; "sub"),
      row("@k_wmem";  $local.TCPSendBuffer; "sub")
    ],

    peering: ([
      row("@k_ixp";      $bgp.IXCount),
      row("@k_upstream"; $bgp.UpstreamsCount),
      row("@k_peers";    $bgp.PeersCount)
    ] | map({ k, v })),

    # The target AS is this machine's own, so it is not one of its upstreams.
    upstreams: [ ($net.Connectivity // [])[]
                 | select(.IsTarget != true)
                 | { name: "AS\(.ASN) \(.Org // "")" | rtrimstr(" "), tier1: (.IsTier1 // false) } ],

    # No `name` per row on purpose: the checks return the provinces in the
    # order the language table lists them, so leaving the name out is what
    # makes the grid read as 粤 or Guangdong depending on the reader.
    #
    # A province that answered zero on all three carriers was not measured —
    # the check reports an unanswered probe as 0.00 — and a grid of zeros
    # would read as a machine with no latency at all.
    latency: (($net.Delay // [])
      | map({ cells: [ (.CT.Average // "0"), (.CU.Average // "0"), (.CM.Average // "0") ] })
      | if (map(select(.cells | map(tonumber? // 0) | add > 0)) | length) == 0 then null
        else { rows: . } end),

    domestic: [ ($net.Speedtest // [])[]
                | { node: ([(.City | clean), (.Provider | clean)] | map(select(. != null)) | join(" ")),
                    up: (.SendSpeed | mbps), upPing: ((.SendDelay // "") | tostring),
                    down: (.ReceiveSpeed | mbps), dnPing: ((.ReceiveDelay // "") | tostring),
                    upTone: (.SendSpeed | speed_tone), downTone: (.ReceiveSpeed | speed_tone) } ],

    intl: [ ($net.Transfer // [])[]
            | select((.SendSpeed | blank | not) or (.ReceiveSpeed | blank | not))
            | { city: .City, ping: ((.Delay.Average // "") | tostring),
                up: (.SendSpeed | mbps), upRt: ((.SendRetransmits // "") | tostring),
                down: (.ReceiveSpeed | mbps), dnRt: ((.ReceiveRetransmits // "") | tostring) } ],

    # ---------------------------------------------------------- route
    #
    # Both route sections come from raw/route.json, which nq-shop fills by
    # running the nine traces itself — Net.sh writes none of them to its JSON,
    # and firing all nine at once loses the API's rate limit anyway. See the
    # note above cmd_route.
    #
    # One matrix row per city, three cells across for the three carriers, in
    # the order the page's column heads name them.
    matrix: [ (["BJ", "SH", "GD"] | .[]) as $c
              | { city: $c, rows: [ $routes[] | select(.city == $c) ] }
              | select((.rows | length) > 0)
              | { label: "@{p.\(.city)} TCP",
                  cells: [ (["ct", "cu", "cm"] | .[]) as $i
                           | ([ .rows[] | select(.isp == $i) ][0]) as $r
                           | if $r == null then { v: "—", tone: "mute" }
                             else { v: ($r | route_label), tone: route_tone($r.name) } end ] } ],

    traces: [ $routes[]
              | select((.hops | length) > 0)
              | { title: "@{p.\(.city)} @{isp_\(.isp)} · \(route_label)",
                  # Province where there is one, country otherwise: the same
                  # granularity the design's geographic path reads at, and one
                  # step coarser than the city, which turns a single route into
                  # a list of every metro its packets touched.
                  geo: ([ .hops[]
                          | ((.prov | clean) // (.country | clean))
                          | select(. != null) ]
                        | . as $g | reduce $g[] as $x ([]; if (. | last) == $x then . else . + [$x] end)
                        | join(" → ")),
                  asPath: ([ .hops[] | .asn | select(. != "") ]
                           | . as $a | reduce $a[] as $x ([]; if (. | last) == $x then . else . + [$x] end)
                           | join(" → ")),
                  hops: [ .hops[]
                          | select(.ttl != null)
                          | { n: (.ttl | tostring),
                              rtt: (if .rtt == null then "*"
                                    else "\((.rtt / 1000000 * 100 | round) / 100)ms" end),
                              ip: .ip,
                              asn: (if .asn == "" then "—" else .asn end),
                              org: ([ (.owner | clean),
                                      ([(.country | clean), (.prov | clean)]
                                       | map(select(. != null)) | join(" ") | clean) ]
                                    | map(select(. != null)) | join(" ")) } ] } ]
  }

  # A section the checks could not fill is dropped rather than published
  # empty: the renderer hides what has no rows, and an empty array in the
  # document is just noise for whoever opens it to edit the prices.
  | with_entries(select(
      .value != null and .value != [] and .value != {} and .value != ""
    ))
}
