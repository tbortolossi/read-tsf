# Reading a PAN-OS Tech Support File

A practical guide to what a TSF contains, where to look, and in which order —
written for someone who has one on disk and a problem to explain.
The layout below was checked against ten real TSFs — PA-440, PA-1420,
PA-3220, PA-3410, PA-5250, PA-5430, PA-7050, PA-7080, PAN-OS 10.2.9 to
12.1.4; a path marked `12.x` or `chassis` exists only there, an unmarked one
was on all of them. Panorama differs in details, not in shape.

## 1. What a TSF is

A **tech support file** is a gzipped tar (`<date>_<time>_techsupport.tgz`,
typically 100–400 MB) that PAN-OS assembles on request. It is a snapshot of
three things:

1. **The device's configuration** — running, candidate, saved copies, and what
   Panorama pushed.
2. **The daemon logs** from `/var/log/pan/`, with their rotations — usually 5 to
   30 days of history depending on how chatty the box is.
3. **The output of several hundred `show` / `debug` commands**, run at
   generation time, captured into one big text file.

Generate it from **Device › Support › Generate Tech Support File** (GUI), or
from the CLI with `request tech-support dump` followed by
`scp export tech-support to user@host:/path`. Generating takes 5–15 minutes
and briefly loads the management plane; on a struggling box, do it anyway —
the state you want is the state it is in now.

Two dates matter and they are not the same:

- the **generation time**, in the filename and at the top of
  `tmp/cli/techsupport_*.txt` (`> show clock`);
- the **device timezone**, printed by the same `show clock`
  (`Sun Apr  5 09:36:57 CEST 2026`). Every log line inside the TSF is in that
  timezone, with no offset written. If you correlate with an external
  system (SIEM, Panorama, a customer's e-mail), convert first.

## 2. Layout

```
./tmp/cli/techsupport_<hostname>_<YYYYMMDD>_<HHMM>.txt   ← START HERE: all show/debug output
                                           (named after the device, never the model;
                                            a hyphen of the hostname may be dropped — glob it)
./tmp/cli/logs/                            ← a few big command outputs kept apart
    show_log_system.txt, show_log_config.txt, show_log_globalprotect.txt,
    show_log_alarm.txt, sdb.txt, sysd_objects_meta.xml (11.x+), cli_netstat.txt,
    pdt.txt, pmap_mgmtsrvr.txt, online_diags_run_log.txt, cpld_dumps.txt,
    scheduled_report_listing.txt; 12.x adds show_log_journal.txt,
    show_log_systemd.txt, fs_manifest.txt
./opt/pancfg/mgmt/saved-configs/
    running-config.xml                     ← the config in force
    techsupport-saved-currcfg.xml          ← candidate at generation time
    .merged-running-config.xml             ← local + Panorama-pushed, merged
    .ha-remote-rc.xml                      ← the HA peer's running config
./opt/pancfg/mgmt/devices/localhost.localdomain/
    platform.xml                           ← capacity limits PAN-OS enforces
    candidatecfg.<n>.xml, refreshed-candidatecfg.<n>.xml, last-candidatecfg.xml
    rule-hit-count-db.txt, rule-hit-count.bin
    global-external-list.xml               ← EDL contents
    vsys<n>_<EDL name>.ebl                 ← per-EDL binary cache (IP lists; spaces in the name become #)
./opt/pancfg/mgmt/tmp/panorama_pushed/     ← what Panorama sent: newsp/lastsp/mergesp.xml,
                                              pushsp.xml, *-push-request.xml; before/after-sp-imported.xml on 12.x
./opt/pancfg/mgmt/audit/cfg-audit.xml,v    ← RCS history of every commit
./opt/pancfg/mgmt/global/                  ← content/AV version info, report configs
./opt/pancfg/mgmt/healthchecks/            ← periodic health snapshots (.cli, .xml) — 12.x
./opt/pancfg/mgmt/updates/{cur,old}content/global/global.xml  ← the App-ID/Threat DB (37 MB, ignore)
./var/log/pan/                             ← DAEMON LOGS (see §4); dp-monitor.log here on PA-400/1400/3400/5400/VM
./opt/dpfs/var/log/pan/                    ← the dataplane's logs on the PA-3200 family (dp-monitor.log, bcm.log, pan_task_<n>.log)
./opt/var.dp<n>/{log/pan,cores}/           ← per-dataplane logs (PA-5200); opt/var.cp/log/pan/ = control plane (cp-monitor.log)
./opt/var/s<slot>/{dp<n>,cp,lfp<n>}/log/pan/  ← PA-7000: per slot — dataplanes, card CP (cp-monitor.log), log processing cards
./var/cores/crashinfo/                     ← *.info sidecars, one per crash (directory absent or empty = no MP crash);
                                              chassis: opt/var/s<slot>/dp<n>/cores/crashinfo/ per dataplane
./var/log/pan/sslvpn-access/               ← GlobalProtect access log (text) + sslvpn-task.log* (binary) — only when GP is configured
./var/log/pan/frr/                         ← frr_export.log; with advanced routing on, ns<N>_frr_export.log per logical router
./var/log/{messages,dmesg,syslog-system,audit/,sa/}  ← Linux side: kernel ring buffer, auth, sar
./var/log/nginx/                           ← web front ends: access, error, api_metrics, restapi_metrics,
                                              l3svc_access, and sslvpn_access.log — the GP portal's nginx,
                                              rotated to .N.zip (not .gz); nginx_*.pid / .status beside them
./var/log/ntpstats/{loopstats,peerstats}   ← clock offset and drift per NTP update (dates are Modified Julian Days)
./opt/pancfg/mgmt/{template,sp}/           ← Panorama-managed only: the pushed template and shared policy,
                                              with push-version.txt, push-checksum.txt and their own *-audit.xml,v
./opt/panrepo/logs/                        ← boot history: bios.log, reboot.log, swm.log, history.log
./etc/frr/                                 ← routing daemon config (advanced routing engine)
./opt/plugins/var/log/pan/                 ← plugin logs (adem, dlp, …)
./opt/pancfg/hsm/, ./opt/nfast/, ./etc/Chrystoki.conf  ← HSM scaffolding: shipped on most boxes even with no HSM
                                              (only *-original* files = never configured)
```

Rotation conventions in `var/log/pan/`: `<daemon>.log` is live, `<daemon>.log.old`
or `.1`, `.2`… are older, `.gz` are compressed rotations (`.log.0.gz` exists
too — `0` is a rotation, not the live file). **`var/log/nginx/` rotates to
`.zip`** instead: `sslvpn_access.log.1.zip`… Single-member deflate, so
`zcat -f`/`zgrep` read them; `unzip -l` shows the member's original name and
the date its window ends. **The failure window
is often only in a rotation** — a daemon that logs 10 MB an hour has rotated
the interesting hour away by the time the TSF is generated. Always list the
rotations before concluding "nothing in the log".

## 3. Where to start: the techsupport txt

`tmp/cli/techsupport_<hostname>_<date>.txt` is ~20 000 lines of `> command`
headers followed by output (150 000+ on a chassis: every dataplane command is
repeated per DP, each block opened by `> set system setting target-dp
s<slot>dp<n>` — index those first). Search for the `> ` prefix to navigate.
The sections worth reading on every case, in order:

| section | tells you |
|---|---|
| `> show system info` | model, serial, **PAN-OS version**, content/AV/threat versions, uptime, HA, mgmt IP |
| `> show clock` | device time and timezone (see §1) |
| `> show running resource-monitor` | dataplane CPU per core, and `Resource utilization (%)`: session, **packet buffer, packet descriptor (on-chip)** — read the *(maximum)* rows; descriptor saturation drops packets while CPU looks idle |
| `> show session info` | sessions in use vs. the limit, packet rate, throughput, timeouts |
| `> show counter global filter delta yes` | dataplane drop counters — **read the `drop` and `error` severities first** |
| `> show interface all` | link state, speed/duplex, errors per interface |
| `> show high-availability all` / `state-synchronization` / `path-monitoring` | HA state, why a failover happened |
| `> show jobs processed` | commit history with success/failure and duration |
| `> show system files` | crash files and core dumps present on the box |
| `> show system environmentals` | temperature, fans, power supplies |
| `> show system disk-space` / `> show system logdb-quota` | full disks, log partitions |
| `> show routing route` / `> show advanced-routing route` | the FIB, static/OSPF/BGP |
| `> show vpn ike-sa` / `> show vpn ipsec-sa` / `> show vpn flow` | tunnel state |
| `> show global-protect-gateway …` / `-portal …` | GP sessions, auth, statistics |
| `> show user ip-user-mapping-mp all` / `> show user user-id-agent statistics` | User-ID health |
| `> request license info` | licences and expiry (an expired licence explains many "it stopped working") |
| `> debug dataplane pool statistics` | dataplane pools — `Packet Buffers free/total` vs `Low free buffer limit`, `Depleted` segments; depleted pools drop packets silently |
| `> show zone-protection` | per-zone, per-mechanism `packet dropped:` counts — these drops write **no traffic log** |
| `> show system setting …` | tuning knobs that differ from defaults |

`> show counter global` appears twice: once raw and once as a delta over a
few seconds. The delta is the one that says what is happening *now* — but it
can span 0.2 s, so low-rate counters only surface in the raw section (which
has its own rate column). `> show system resources` is **not** in the dump
(checked on ten TSFs, 10.2 to 12.1): management-plane CPU and memory history
is `mp-monitor.log` (§4).

Packet-buffer cases (verified on ten real PBP-case TSFs, 10.2 → 11.1,
including a PA-5430 Active/Active pair):
`Packet buffer congestion (utilization) is X/Y` lines in
`tmp/cli/logs/show_log_system.txt` are the per-minute, weeks-long,
reboot-surviving buffer history — Y is the measured pool total (on a PA-5430
the `Pow Atomic Memory Pools` `[ 0] Packet Buffers` total of `debug dataplane
pool statistics`; the on-chip `PKI POOL DFLT` on 3200/5200/7000, where that
command has **no** `Packet Buffers` row — match the number to a pool rather
than assuming from the family). Buffer average high while sessions idle = leak (resets only
at reboot); maxima spiking with recovery between = burst — the hour/day/week
resource-monitor blocks (newest-first) and the pool table embedded in every
`dp-monitor.log` snapshot decide between them. PBP counters on 10.2/11.x are
`flow_dos_pbp_drop`/`_ifp_zone`/`_block_host` + `flow_dos_drop_ip_blocked`,
not only `pkt_buf_protect_*`; no TSF in the corpus carries `show session
packet-buffer-protection`, `ingress-backlogs` or threat logs — blocked-host
identity is unrecoverable after the fact. Details and the L2-storm /
fragmentation / proxy-retransmit counter signatures: SKILL.md, buffers
section. Three more from the PA-5430 pair, all detailed there: PBP set to
`monitor-only` holds every PBP counter at zero while the buffer sits at 98 %
(read the flags in `.merged-running-config.xml`, not the counters, and not
`running-config.xml` on a Panorama-managed box); the offender is found in
`show running application statistics` — a couple of never-closing GRE/ERSPAN
sessions carrying 90 % of the firewall's bytes — never in `show session all`,
which the dump caps at ~1024 sessions; and in Active/Active the feed belongs
to one member for its whole life, so the peer only congests during that
member's reboot minutes.

## 4. Daemon logs — which file for which problem

All under `var/log/pan/`. Daemon names are stable across releases, but **some
daemons have two log names and the newest is the live one**: on 11.1+ IKE
writes `ikemgr-ng.log` while `ikemgr.log` stays present and idle; same for
`keymgr`/`keymgr-ng` and `dnsproxyd`/`dnsproxy_go`/`dns-go-agent`. Check both.

| problem | read | then |
|---|---|---|
| commit failed / slow | `configd.log`, `show_log_config.txt`, `commit_stats.log` (12.x) | `mgmt_httpd_error.log`, `cfg-audit.xml,v` for what changed |
| reboot / crash | `var/cores/crashinfo/*.info` (per DP on a chassis), `sysd.log`, `messages`, `opt/panrepo/logs/reboot.log` | `show system files`; `mp-monitor.log` for memory before the crash; the serial console (`Welcome to the PanOS Bootloader…`, timestamped — the boot sequence and any panic text the kernel printed on the way down): `dataplane-console-output.log` (PA-3200), `controlplane-console-output.log` + `opt/var.cp/log/pan/dataplane<n>-console-output.log` (PA-5200), `slot<n>-console-output.log` + `fpp-console-output.log` + `opt/var/s<slot>/cp/log/pan/dataplane<n>-console-output.log` (PA-7000); none on 400/1400/3400/5400 |
| HA failover | `ha_agent.log`, `show_log_system.txt` (filter `ha`) | `show high-availability all`; path/link monitoring config in `running-config.xml` |
| site-to-site VPN | `ikemgr-ng.log` (or `ikemgr.log`), `keymgr*.log` | `> debug ike stat …`, `show vpn ike-sa`, `show vpn ipsec-sa`; the peer's proposals in the config |
| GlobalProtect | `gpsvc.log`, `sslvpn-access/sslvpn-access.log`, `sslvpn_ngx_error.log`, `show_log_globalprotect.txt` (can be the biggest text file of the TSF — 64 MB seen; one row per portal/gateway event, columns: time, gateway/portal, status, event, region, `domain\user`) | `rasmgr.log`, `authd.log`, `sslmgr.log` (certs); `var/log/pan/sslvpn-access/sslvpn-task.log*.gz` are **binary** per-request records (`strings`/`grep -a`) |
| authentication (admin, GP, captive portal) | `authd.log` | `useridd.log` for group mapping, `sslmgr.log` for cert-based auth |
| User-ID | `useridd.log`, `distributord.log`, `redis_useridd.log` | `> show user …` sections |
| routing | `routed.log` (legacy) or `var/log/pan/frr/` (`frr_export.log`, `ns<N>_frr_export.log` per logical router) + `etc/frr/` (advanced routing) | `> show routing …` / `> show advanced-routing …` (on an ARE box the classic sections only say `Command deprecated` — use the advanced ones); `bfd.log` for BFD. Time dimension: RIB `age` per learned route; SPF runs and path-monitor Up/Down in `routed.log`; LSDB `Age`/seq. No per-prefix add/delete history and no system logdb in the archive. |
| interfaces / links | `pan_ifmgr.log`, `brdagent.log` (port/ASIC faults), `l2ctrld.log` | `> show interface all`, `show system environmentals` |
| performance / drops | `mp-monitor.log`, `dp-monitor.log` (under `opt/dpfs/var/log/pan/` on a PA-3200, per plane on a chassis), `dp-sessperf_mon.log` | `> show running resource-monitor`, `show counter global filter delta yes`, `debug dataplane pool statistics` |
| content / AV updates | `paninstaller_content.log`, `curlog_out_*`, `contentd.log`, `md_*.log` | `> request content upgrade info`, `opt/pancfg/mgmt/global/*info.xml` |
| WildFire | `wildfire-monitor.log`, `wildfire-upload.log`, `wf_curl.log` | `> show wildfire status` |
| logging / log forwarding | `logrcvr.log`, `varrcvr.log`, `logging-services.log`, `logpurger.log` — on a PA-7000, under the log processing cards `opt/var/s<slot>/lfp<n>/log/pan/` (`logrcvr.log`, `syslog-ng.log`, `lfp-monitor.log`) | `> show logging-status`, `debug log-receiver statistics`; `redis_useridd.log`/`redis_mgmt.log` can be the biggest files of the TSF (200 MB seen) |
| forwarding to the cloud (Strata Logging Service / Cortex Data Lake) | `icd.log` — the ingestion client, JSON lines; its certificate-chain checks name the region the device ships to (`CN=ingest.<region>.prd.strata.logging.paloaltonetworks.com`) | `icd_dp.log` — the data path, **warnings and errors only**: `dpi nonack stream[0:N] failed to send ingestion request, EOF`, `rpc error: code = Unavailable … reset reason: overflow`. Tens of thousands of those = logs are not reaching the cloud, and nothing else in the TSF says so. `lcaas_agent.log`, `envoy_broker.log`, `l3svc_ngx_error.log` for the transport underneath |
| SNMP polling | `snmpd.log` | `Unable to fetch <sysd key>` / `No counter node` = the daemon could not read the value the NMS asked for — an OID that stopped answering without the box being down |
| device health monitors | `sysdagent.log` | one timed cycle per check, each with a `result:` — `MONITOR: Disk space check`, `MONITOR: Certificate expiry check completed. Expired certificates found: N`, `MONITOR: Backup status check`. The dated history behind a health alarm |
| certificates / keystore | `sslmgr.log`, `cryptod.log` (`Id:<name> not found in keystore`, master-key changes), `device_certgen.log`, `dsms-certificates.log` | `> show device-certificate status`; `sysdagent.log` for the expiry count over time |
| MP ↔ DP plumbing | `mprelay.log`, `pan_comm_0.log` (the message bus; an error count in the thousands is the signal, not one line), `pan_dha.log` (dataplane HA agent) | `cp-monitor.log` `cp_stats` on platforms that have a CP (SKILL.md, step 2b) |
| daemon supervision / startup | `sysd.log`, `supervisor.log` (`*** Supervisor process is initializing system ***` = a full MP restart), `md-startscript.log`, `mgmt_fb.log` | `mp-monitor.log` PID changes; `opt/panrepo/logs/reboot.log`. There is **no** `masterd.log` on 10.2–12.1 |
| time sync | `var/log/ntpstats/loopstats` (offset, drift), `peerstats` (per peer) | dates are Modified Julian Days: `date -d "1858-11-17 + <MJD> days"`. Sub-ms offset = timestamps across the archive are comparable; a step of seconds re-bases every correlation |
| SD-WAN / LSVPN / tunnels | `sdwand.log`, `satd.log` (satellite), `tund.log` | `> show sdwan …`, the `network/sdwan` subtree of the config |
| IoT Security / device identification | `iotd.log`, `redis_iotd.log`, `icd.log` (same ingestion path) | `> show iot …` where the plugin is installed |
| Cloud Identity Engine / directory sync | `dscd.log` (JSON), `redis_dscd.log` | `useridd.log` for what the mappings became |
| plugins | `plugin_api_server.log` (the plugin bus — client connect/disconnect churn), `plugin_install.log`, `check_plugin_compat.log` | `opt/plugins/var/log/pan/` for each plugin's own log |
| reports | `reportd.log`, `report_gen.log`, `genreport.log`, `indexgen.log` | |
| SSL decryption / certificates | `sslmgr.log`, `device_certgen.log`, `uia_tsa_cert.log` | `> show device-certificate status`, `debug sslmgr statistics` |
| DHCP / DNS proxy | `pan_dhcpd.log`, `dhclient_debug.log`, `dnsproxy_go.log` | |
| Panorama connectivity | `devsrv.log`, `ms.log`, `configd.log` | `> show panorama-status` |
| web UI / API | `mgmt_httpd_access.log`, `mgmt_httpd_error.log`, `appweb3-panmodule.log`, `php.debug.log` | `dagger.log`: every operational command dispatched (`OPCMD: handler "session"` / `finish handler …`, timestamped) — what was run from CLI/API, and when |
| disk | `logdb_dirs_gen.log`, `panlogs-partition.log`, `messages` | `> show system disk-space` |
| telemetry / cloud services | `device_telemetry*.log`, `lcaas_agent.log`, `envoy_broker.log` | |

### Names that are not in any TSF

Published PAN-OS log lists and cheat sheets circulate names that no archive
in this corpus (PA-440 → PA-7080, PAN-OS 10.2.9 → 12.1.4) contains. Before
reporting that a log is missing, `ls var/log/pan/ | grep -i <daemon>`.

| name you may read elsewhere | what is actually there |
|---|---|
| `masterd.log`, `masterd_detail.log` | `sysd.log`, `supervisor.log`, `md-startscript.log` |
| `logcvr.log`, `varcvr.log` | `logrcvr.log`, `varrcvr.log` (the shortened spellings are typos) |
| `ha-agent.log` | `ha_agent.log` |
| `userid.log` | `useridd.log` |
| `pan_bc_download.log` | no equivalent; content downloads are in `curlog_out_*` and `paninstaller_content.log` |
| `pan_packet_diag.log` | real, but on a single archive of the corpus — treat as platform- or version-specific |

The converse also holds: `pan_comm_0.log`, `pan_dha.log`, `sysdagent.log`,
`cryptod.log`, `snmpd.log`, `icd.log` and `pppoed.log` are on **every**
archive of the corpus and appear in no vendor cheat sheet.

`show_log_system.txt` (the system log) is the cross-daemon timeline: when
you do not know where to look, grep it for the failure minute and it names
the daemon.

Files you can ignore unless you have a reason not to: `global.xml` (the
content database), `regip/reg_ips.xml`, `*.dat` (regex group binaries),
`ui_content/*.js.gz`, `fs_manifest.txt` (a file listing of the whole box),
`req_stats.log` (management-server request accounting),
`last-candidatecfg-audit.xml,v` (RCS history of every *candidate*, tens of
MB), the working copies under `opt/pancfg/mgmt/tmp/` (`cndt_cfg.xml`,
`tplsp_cfg_to_validate.xml`, `tplsp_cfg_subintf_add.xml`,
`candidate_cfg_*.xml` — 25 MB each, the commit machinery's scratch space),
`wif_event/` (WildFire inline-ML event records),
`tmp/cli/logs/sysd_objects_meta.xml` (the whole sysd object tree as
XML — 100 MB on a chassis; `sdb.txt` is the same data as grep-able dotted
keys), `opt/var*/…/log/pan/memdump/hwbuf-*.raw` (100 MB binary hardware
buffer dumps per DP). Two that look like noise but are not: `content_telemetry.log` opens
with a full `--- show system info ---` block (a second copy of the device's
identity and versions), and `show_log_system.txt` (79 MB seen) is the
cross-daemon timeline — grep it, never open it.

## 5. Reading the config

`running-config.xml` is the config in force. Structure:

```
config/
  mgt-config/                  admins, passwords (hashed), roles
  shared/                      shared objects: certificates, server profiles (LDAP/RADIUS/syslog), log settings
  devices/entry[localhost.localdomain]/
    deviceconfig/system/       hostname, DNS, NTP, mgmt IP, Panorama servers
    deviceconfig/setting/      tuning: session timeouts, jumbo frames, ctd, …
    deviceconfig/high-availability/
    network/                   interfaces, virtual routers, IKE gateways, IPsec tunnels, zones, profiles
    vsys/entry[vsys1]/         address/service objects, rulebase (security, nat, pbf, decryption…), GP portal/gateway, auth
```

Panorama-managed devices carry the pushed part in `.merged-running-config.xml`
and the raw push in `opt/pancfg/mgmt/tmp/panorama_pushed/` (`newsp.xml`,
`lastsp.xml`, `mergesp.xml`, `pushsp.xml`, the `*-push-request.xml`
requests; 12.x adds `before-` and `after-sp-imported.xml`).
`running-config.xml` alone is then incomplete.

On a Panorama-managed device, `opt/pancfg/mgmt/template/` and
`opt/pancfg/mgmt/sp/` hold the pushed template and shared policy as the
device received them, each with `push-version.txt` (a plain integer — the
push the device holds), `p-push-version.txt` (the one before it),
`push-checksum.txt` (md5 of the pushed blob) and its own
`template-config-audit.xml,v` / `sp-config-audit.xml,v` RCS history. Those
version integers answer "is this device running the push Panorama thinks it
sent" without diffing megabytes of XML.

`cfg-audit.xml,v` is an RCS file: each revision is one commit, with author
and timestamp. `rlog`/`co -p` read it, or search `date` headers by hand. It
answers "what changed just before it broke".

`platform.xml` holds the limits PAN-OS actually enforces for this model
(sessions, rules, tunnels, licensed vsys) — compare them with `show session
info` and the object counts rather than trusting a datasheet.

## 6. A reading order that works

1. `show system info` → version, uptime, HA, serial. Uptime shorter than the
   problem's age means a reboot: go to crashes first.
2. `show system files` + `var/cores/crashinfo/` (and `opt/var*/…/cores/`
   on a chassis) → any core dump or crash sidecar? The process and the
   crash time are in the filename (`routed-20260109122837-11.1.10-h1.info`).
3. `show_log_system.txt` around the reported time → which daemon complained.
4. That daemon's log, **including rotations**, around the same minute.
5. The relevant `show` sections (§3) for the current state.
6. The config for the objects the log lines name (rule, gateway, profile).
7. `cfg-audit.xml,v` / `show jobs processed` → what changed, and when.

Keep the device timezone in mind at every step, and remember that a TSF is a
snapshot: counters are *since boot* unless a section says delta.

## 7. Reading an anonymized TSF

An archive produced by this tool has the same layout, the same files, the
same line counts and timestamps; only identifiers changed, consistently:

| you see | it was |
|---|---|
| `100.64.x.y` … `100.127.x.y` | a private (RFC 1918) address |
| `192.0.2.x`, `198.51.100.x`, `203.0.113.x` | a public address |
| `hostNNN.anon.internal`, `hostNNN` | a FQDN / hostname |
| `userNNN` | a username (also the local part of an e-mail) |
| `ZONE-0012`, `RULE-0045`, `ADDR-0003`, `GW-0002`, `OBJ-0100` … | a named config object; the prefix is its category |
| all-digit serial of the same length | a serial number |

The same original value always maps to the same replacement across every
file, so "peer `203.0.113.7` on gateway `GW-0002`" is the same peer and
gateway wherever they appear. Interface names (`ethernet1/1`, `ae1`,
`tunnel.1`), built-in objects (`any`, `trust`, `vsys1`), vendor domains and
netmasks are untouched. **Member names are rewritten with the same
mapping**: the command dump reads `tmp/cli/techsupport_host001_<date>.txt`.
The device's own hostname, devicename, domain and serial are taken from
`show system info` itself, so they are pseudonymized wherever they appear —
including glued with underscores in a file name.

The `*.mapping.json` sidecar reverses every substitution. It is the
customer's identity in one file: it stays with whoever owns the original and
is never sent along with the anonymized archive.

Binary files (`rule-hit-count.bin`, `*.dat`, sqlite DBs, `wtmp`/`btmp`/
`lastlog`, and `sslvpn-task.log*.gz` — a binary record format that embeds the
source IP and username of every GlobalProtect request) are copied through
unchanged; the integrity report lists any that still embed identifiers. With
**redact binaries** — on by default — such a member's payload is replaced by
the one-line marker `[tsf-anonymizer] binary payload redacted…`; the original
is gone from the archive, not hidden, and the verification checks that each
redaction was warranted. Every redacted family has a text twin that is
anonymized normally (`saNN` → `sarNN`, `rule-hit-count.bin` →
`rule-hit-count-db.txt`, `sslvpn-task` → `show_log_globalprotect.txt`),
except `wtmp`/`btmp`/`lastlog`: the admin login history is the one thing an
anonymized archive no longer carries — `show_log_system.txt` and `authd.log`
cover the same question.
