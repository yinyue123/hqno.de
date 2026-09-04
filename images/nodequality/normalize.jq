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

$ip[0] as $ip | $hw[0] as $hw | $net[0] as $net | $trace[0] as $tr | $shop[0] as $shop

| ($ip.Info // {}) as $info
| ($hw.CPU // {}) as $cpu
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
    cpu: [
      (if ($cpu.benchmarks.sysbench.single // null) != null then
        { label: "SYSBENCH 1-THREAD", value: ($cpu.benchmarks.sysbench.single | round | tostring), sub: "events/s" } else empty end),
      (if ($cpu.benchmarks.sysbench.multi // null) != null then
        { label: "SYSBENCH \($cpu.topology.threads // 1)-THREAD", value: ($cpu.benchmarks.sysbench.multi | round | tostring),
          sub: "events/s" } else empty end),
      (if ($mem.benchmarks.read_MBps // null) != null then
        { label: "@l_mem_r", value: "\($mem.benchmarks.read_MBps | round) MB/s",
          sub: (if ($mem.benchmarks.latency_ns // null) == null then "HardwareQuality" else "\($mem.benchmarks.latency_ns) ns" end) } else empty end),
      (if ($mem.benchmarks.write_MBps // null) != null then
        { label: "@l_mem_w", value: "\($mem.benchmarks.write_MBps | round) MB/s", sub: "HardwareQuality" } else empty end)
    ],

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

    port25: (if ($ip.Mail.Port25 // null) == null then null
             else { v: (if $ip.Mail.Port25 then "@v_yes" else "@v_port_blocked" end),
                    tone: (if $ip.Mail.Port25 then "ok" else "bad" end) } end),

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
                    up: (.SendSpeed // ""), upPing: (.SendDelay // ""),
                    down: (.ReceiveSpeed // ""), dnPing: (.ReceiveDelay // ""),
                    upTone: "sub", downTone: "sub" } ],

    intl: [ ($net.Transfer // [])[]
            | select((.SendSpeed | blank | not) or (.ReceiveSpeed | blank | not))
            | { city: .City, ping: (.Delay.Average // ""),
                up: (.SendSpeed // ""), upRt: (.SendRetransmits // ""),
                down: (.ReceiveSpeed // ""), dnRt: (.ReceiveRetransmits // "") } ]

    # The route matrix and the hop-by-hop detail are *not* built here, and the
    # renderer draws both if a document carries them — see
    # shop/example.page.json, which does.
    #
    # The reason is upstream: Net.sh writes exactly seven keys to its JSON —
    # Head, BGP, Local, Connectivity, Delay, Speedtest, Transfer — and the
    # nine backhaul routes are not among them. `-R` prints them to the report
    # and nothing else, so the file NodeQuality saves as backroute_trace.json
    # is the same envelope with the route fields empty. There is no JSON to
    # read, only a coloured table to scrape, and a route name guessed wrong is
    # worse on a sales page than a route section that is not there.
    #
    # The report is kept verbatim as raw/trace.log for whoever wants to read
    # it or paste it in by hand.
  }

  # A section the checks could not fill is dropped rather than published
  # empty: the renderer hides what has no rows, and an empty array in the
  # document is just noise for whoever opens it to edit the prices.
  | with_entries(select(
      .value != null and .value != [] and .value != {} and .value != ""
    ))
}
