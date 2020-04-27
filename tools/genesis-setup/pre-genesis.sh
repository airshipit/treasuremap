#!/bin/bash
#
# The purpose of this script is to perform the steps necessary to properly
# configure a node as the Genesis host before the `genesis.sh` script can be run.
#
# This script sources most of this configuration data from the rendered site
# manifests, which it takes as input. The remaining configuration data is
# tunable via environment variables advertised at the top of each module section.
#
# This script makes a number of assumptions about general site design patterns,
# and the expected path to data in the manifests. Environment variables are also
# provided to disable unneeded sections.
#
# Expected runtime: Approximately 5-10 minutes, depending on manifests size and
# connection speed.
#
# **NOTE1** By default this script disables password-based SSH access. Ensure
#           you have your SSH key properly configured and working before running.
# **NOTE2** Bad things can happen to your disk if your hardware profile does not
#           specify the correct PCI ID for your desired ceph journal.
# **NOTE3** IP addresses of the node will change after running this script to
#           values from your manifests file. New IPs will be annouced prior to
#           final reboot.
# **NOTE4** The script performs a reboot after successful completion.

set -o errtrace
set -o pipefail

declare -Ax __log_types=(
  [ERROR]='fd=2, color=\e[01;31m'  # red
  [TRACE]='fd=2, color=\e[01;31m'  # red
  [WARN]='fd=1, color=\e[01;93m'   # yellow
  [INFO]='fd=1, color=\e[01;37m'   # white
  [DEBUG]='fd=1, color=\e[01;90m'  # dark grey
  [DEBUG2]='fd=1, color=\e[01;36m' # second debug channel; cyan
)
for __log_type in "${!__log_types[@]}"; do
  alias log.${__log_type}="echo ${__log_type}"
done
shopt -s expand_aliases

__logfile="/var/log/$(basename ${BASH_SOURCE})_$(date +"%m-%d-%y_%H:%M:%S").log"

__text_formatter(){
  local log_prefix='None'
  local default_log_type='INFO'
  local default_xtrace_type='DEBUG'
  local log_type
  local color_prefix
  local fd
  for log_type in "${!__log_types[@]}"; do
    if [[ ${1} == ${log_type}* ]]; then
      log_prefix=''
      color_prefix="$(echo ${__log_types["${log_type}"]} |
                      cut -d',' -f2 | cut -d'=' -f2)"
      fd="$(echo ${__log_types["${log_type}"]} |
            cut -d',' -f1 | cut -d'=' -f2)"
      break
    fi
  done
  if [ "${log_prefix}" = "None" ]; then
    # xtrace output usually begins with "+" or "'", mark as debug
    if [[ ${1} = '+'* ]] || [[ ${1} = \'* ]]; then
      log_prefix="${default_xtrace_type} "
      log_type="${default_xtrace_type}"
    else
      log_prefix="${default_log_type} "
      log_type="${default_log_type}"
    fi
    color_prefix="$(echo ${__log_types["${log_type}"]} |
                    cut -d',' -f2 | cut -d'=' -f2)"
    fd="$(echo ${__log_types["${log_type}"]} |
          cut -d',' -f1 | cut -d'=' -f2)"
  fi
  local color_suffix=''
  if [ -n "${color_prefix}" ]; then
    color_suffix='\e[0m'
  fi
  echo -e "${color_prefix}${log_prefix}${1}${color_suffix}" >&${fd}
  echo "${1}" >> "${__logfile}"
}
# Due to this unresolved issue: http://bit.ly/2xPmOY9 we choose preservation of
# message ordering at the expense of applying appropriate tags to stderr. As a
# result, stderr from subprocesses will still display as INFO level messages.
# However we can still log ERROR messages using the aliased log handlers.
exec >& >(while read line; do
            if [ "${line}" = '__EXIT_MARKER__' ]; then
              break
            else
              __text_formatter "${line}"
            fi
          done)

die(){
  set +x
  # write to stderr any passed error message
  if [[ $@ = *[!\ ]* ]]; then
    log.ERROR "$@"
  fi
  log.TRACE "Backtrace:"
  for ((i=0;i<${#FUNCNAME[@]}-1;i++)); do
    log.TRACE $(caller $i)
  done
  echo __EXIT_MARKER__
  # Exit after pipe closes to ensure all output is flushed first
  while : ; do
    echo "Waiting on exit..." || exit 1
  done
}
export -f die
trap 'die' ERR
set -x

###############################################################################
# Helper functions
###############################################################################

write_test(){
  touch "${1}/__write_test" &&
    rm "${1}/__write_test" ||
    die "Write test to ${1} failed."
}

die_if_null(){
  local var="${1}"
  shift
  [ -n "${var}" ] || die "Null variable exception $@"
}

manifests_filter(){
  local file="$1"
  local filters="$2"
  outfile="$(mktemp)"
  python3 -c "
import yaml
l = []
y = yaml.load_all(open('$file'))
for x in y:
  if False $filters:
    l.append(x)
with open('$outfile', 'w') as outfile:
    yaml.dump_all(l, outfile, default_flow_style=False)
"
  rendered_file="$outfile"
  log.DEBUG2 "Pruned manifests location: $outfile"
}

# Key/value lookups from manifests
manifests_lookup(){
  local file="$1"
  local schema="$2"
  local mdata_name="$3"
  local key_path="$4"
  local oper="$5"
  local allow_fail="$6"
  local key_name="$7"

  FAIL=false
  RESULT=`python3 -c "
import yaml,sys
y = yaml.load_all(open('$file'))
for x in y:
  if x.get('schema') == '$schema':
    if x['metadata']['name'] == '$mdata_name':
      if isinstance(x$key_path,list):
        if '$oper' == 'get_size':
          print(len(x$key_path))
          break
        elif '$oper' == 'get_index':
          j = 0
          for i in x$key_path:
            if isinstance(i, dict) and  i['name'] == '$key_name':
              print(j)
              break
            j += 1
          break
        else:
          for i in x$key_path:
            print(i)
          break
      else:
        if '$oper' == 'dict_keys':
          print(' '.join(x$key_path.keys()))
          break
        else:
          print(x$key_path)
          break
else:
  sys.exit(1)" 2>&1` || FAIL=true

  if [[ $FAIL = true ]] && [[ $allow_fail != true ]]; then
    die "Lookup failed for schema '$schema', metadata.name '$mdata_name', key path '$key_path'"
  fi
}

clear_mini_mirror() {
  if docker ps | grep -q mini-mirror; then
    docker stop -t 10 mini-mirror
  fi
  if docker ps -a | grep -q mini-mirror; then
    docker rm mini-mirror
  fi
  rm -f /var/tmp/minimirror-tmp.*
}

# Setup/teardown mini-mirror container.
mini_mirror() {
  manifests_lookup "$rendered_file" "armada/Chart/v1" \
                                    "mini-mirror" "['data']['values']['images']['tags']['mini-mirror']"
  mini_mirror_image="$RESULT"

  set -x
  if [[ "$1" == "start" ]]; then
    clear_mini_mirror
    config="$(mktemp -p /var/tmp minimirror-tmp.XXXXXX)"
    tee $config << EOF
server {
  listen 8000;
  root /srv;
  server_name nginx;

  location / {
    autoindex on;
  }
}
EOF
    # make sure docker is enabled for subsequent reboots so that
    # --restart=always works as intended
    /bin/systemctl daemon-reload
    /bin/systemctl enable docker.service

    docker run --restart=always -d --net host -v $config:/etc/nginx/conf.d/default.conf \
               --name mini-mirror $mini_mirror_image
  elif [[ "$1" == "stop" ]]; then
    docker stop mini-mirror
    docker rm mini-mirror
  else
    die "Unable to start/stop mini-mirror. Usage: mini_mirror [start/stop]"
  fi
}

install_file(){
  local path="$1"
  local content="$2"
  local permissions="$3"
  local force_update="${4:-false}"
  local systemd_unit="${5:-false}"
  local reboot="${6:-false}"
  local dirname=$(dirname "$path")

  if [[ ! -d $dirname ]]; then
    mkdir -p "$dirname"
  fi

  if [[ ! -f $path ]] || [ "$(cat "$path")" != "$content" ] || \
                         [[ $force_update = force_update ]]; then
    echo "$content" > "$path"
    chmod "$permissions" "$path"
    if [[ $systemd_unit = systemd_unit ]]; then
      # Load changes
      systemctl daemon-reload
      # Mark for autostart on boot
      systemctl enable "$(basename $path)"
      # (re)start service now
      systemctl restart "$(basename $path)"
    fi
    if [[ $reboot = reboot ]]; then
      REBOOT=true
      echo '*** System restart required ***' > /run/reboot-required
    fi
    FILE_UPDATED=true
  else
    FILE_UPDATED=false
  fi
}

check_if_mounted(){
  local mountpoint="$1"

  # Get list of node mounts
  mounts="$(df -h)"

  MP_FOUND=false
  IFS=$'\n'
  for i in $mounts; do
    # mountpoint
    host_mp="$(echo $i | awk '{print $6}')"
    # total capacity of mountpoint
    #host_size="$(echo $i | awk '{print $2}')"
    if [[ $host_mp = $mountpoint ]]; then
      MP_FOUND=true
      break
    fi
  done
  unset IFS
}

apt_install(){
  for pkg in $@; do
    dpkg -s $pkg 2> /dev/null | grep 'Status: install ok installed' || DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install $pkg
  done
}

apt_uninstall(){
  for pkg in $@; do
    if dpkg -s $pkg 2> /dev/null | grep 'Status: install ok installed'; then
      DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold remove $pkg
    fi
  done
}

find_smallest_mac(){
  local macs="$1"
  local min=281474976710655 # ff:ff:ff:ff:ff:ff
  for m in $macs; do
    mac_dec=$(echo $(( 16#${m//:} )))

    if [[ "$mac_dec" -lt "$min" ]]; then
      min="$mac_dec"
    fi
  done
  mac="$(printf '%x\n' $min)"
  MIN_MAC_ADDR=${mac:0:2}:${mac:2:2}:${mac:4:2}:${mac:6:2}:${mac:8:2}:${mac:10:2}
}

get_var_crash_index () {
  manifests_lookup "$rendered_file" "drydock/HostProfile/v1" \
                   "$CONTROL_PLANE_HOST_PROFILE_SAMPLE" \
                   "['data']['storage']['physical_devices']['$VAR_CRASH_DEVICE']['partitions']" \
                   "get_index" \
                   true \
                   "$VAR_CRASH_PART_NAME"
  var_crash_index="$RESULT"
  log.DEBUG2 "Var crash index: '$var_crash_index'"
  if [[ $FAIL = true ]]; then
    die "Failed finding var crash partition in host profile."
  fi
}

get_var_crash_size () {
  manifests_lookup "$rendered_file" "drydock/HostProfile/v1" \
                   "$CONTROL_PLANE_HOST_PROFILE_SAMPLE" \
                   "['data']['storage']['physical_devices']['$VAR_CRASH_DEVICE']['partitions'][$var_crash_index]['size']"
  var_crash_size="$(echo $RESULT | awk '{ print toupper($0) }')"
  log.DEBUG2 "Var crash partition size: '$var_crash_size'"

  if [[ $FAIL = true ]]; then
    die "Failed partitioning var_crash disk. Partition size was not defined."
  fi
}

get_var_crash_format () {
  manifests_lookup "$rendered_file" "drydock/HostProfile/v1" \
                   "$CONTROL_PLANE_HOST_PROFILE_SAMPLE" \
                   "['data']['storage']['physical_devices']['$VAR_CRASH_DEVICE']['partitions'][$var_crash_index]['filesystem']['fstype']"
  var_crash_format="$RESULT"
  log.DEBUG2 "Var crash partition filesystem format: '$var_crash_format'"

  if [[ $FAIL = true ]]; then
    die "Failed partitioning var_crash disk. Partition filesystem format was not defined."
  fi
}

get_var_crash_mount_point () {
  manifests_lookup "$rendered_file" "drydock/HostProfile/v1" \
                   "$CONTROL_PLANE_HOST_PROFILE_SAMPLE" \
                   "['data']['storage']['physical_devices']['$VAR_CRASH_DEVICE']['partitions'][$var_crash_index]['filesystem']['mountpoint']"
  var_crash_mount_point="$RESULT"
  log.DEBUG2 "Var crash partition mount point: '$var_crash_mount_point'"

  if [[ $FAIL = true ]]; then
    die "Failed partitioning var_crash disk. Partition mount point was not defined."
  fi
}

find_block_device() {
  disk_pci_regex="${device_bus_type}-${device_pci_id//./:}"
  disk_pci_id_file="$(find /dev/disk/by-path/ -name "*${disk_pci_regex}")"
  log.DEBUG "Var crash bock device pci id file: '$disk_pci_id_file'"
  if [[ -z $disk_pci_id_file ]]; then
    die "Could not find a local disk drive with PCI ID '$device_pci_id'."
  fi

  disk_block_device="$(readlink -f "$disk_pci_id_file")"
  log.DEBUG "Var crash block device alias: '$disk_block_device'"
  die_if_null "$disk_block_device" "Could not map disk PCI ID '$disk_pci_id_file' to a block device."
}

check_var_crash_partition_exists() {
  var_crash_exists=false
  part_count="$(fdisk -l $disk_block_device | (grep "${disk_block_device}[0-9]" || true) | wc -l)"
  if [[ $part_count -gt 0 ]]; then
    for ((p=1; p<=$part_count; p++)); do
      pci_id_file="$(find /dev/disk/by-path/ -name "*${disk_pci_regex}-part${p}")"
      die_if_null "$pci_id_file" "Did not find a partion for block device '$disk_block_device$p'"
      blk_dev="$(readlink -f "$pci_id_file")"
      die_if_null "$blk_dev" "Link between '$pci_id_file' and '$blk_dev' does not exist."
      p_size="$(fdisk -l $disk_block_device | grep "$blk_dev" | awk '{ print $5 }')"
      log.DEBUG2 "Partition size is: '$p_size', var_crash_size is: '$var_crash_size'."
      if [[ "$var_crash_size" == "$p_size" && $(($var_crash_index + 1)) -eq $p ]]; then
        log.INFO "A var_crash partition with the right size exists on '$blk_dev'."
        var_crash_exists=true
        var_crash_pci_id_file="$pci_id_file"
        var_crash_blk_device="$blk_dev"
      fi
    done
  fi
}

format_var_crash_partition() {
  current_fstype="$(blkid "$var_crash_pci_id_file" | sed -n 's/.*\( TYPE=\)/\1/p' | cut -d'"' -f2)"
  log.INFO "Existing fstype: '$current_fstype'"

  if [[ "$current_fstype" == "$var_crash_format" ]]; then
    log.INFO "'$var_crash_blk_device' file system is already formatted as '$var_crash_format'. No action needed."
  # Format disk if no filesystem is present
  elif [[ -z $current_fstype ]]; then
    # unmount the partition if mounted, before formatting it.
    get_var_crash_mount_point
    check_if_mounted "$var_crash_mount_point"
    if [[ $MP_FOUND = true ]]; then
      log.INFO "'$var_crash_mount_point' is mounted, unmounting before formatting."
      umount "$var_crash_mount_point"
    fi
    log.INFO "Creating '$var_crash_format' file system on '$var_crash_blk_device."
    mkfs.$var_crash_format "$var_crash_blk_device"
  elif [[ $current_fstype != $var_crash_format ]]; then
    log.ERROR "Expected var crash device '$var_crash_blk_device' be formatted as '$var_crash_format', but it is currently formatted as '$current_fstype'"
    log.ERROR "Manually use 'mkfs' to fix this after checking this is the right disk"
    die "Var crash partition has an existing filesystem that does not match desired fstype"
  fi
}

add_var_crash_fstab_entry() {
  local fstab="/etc/fstab"
  local fstab_bkp="$(mktemp -p /var/tmp fstab-bkp-tmp.XXXXXX)"
  cat $fstab > ${fstab_bkp}
  vc_uuid="$(blkid "$var_crash_pci_id_file" | sed -n 's/.*\( UUID=\)/\1/p' | cut -d'"' -f2)"
  die_if_null "$vc_uuid" "Did not find a UUID for the var_crash partition."
  # Fetch intended var_crash mount options
  manifests_lookup "$rendered_file" "drydock/HostProfile/v1" \
                   "$CONTROL_PLANE_HOST_PROFILE_SAMPLE" \
                   "['data']['storage']['physical_devices']['$VAR_CRASH_DEVICE']['partitions'][$var_crash_index]['filesystem']['mount_options']"
  var_crash_mount_options="$RESULT"
  log.DEBUG2 "Var crash partition mount options: '$var_crash_mount_options'"
  if [[ $FAIL = true ]]; then
    die "Failed partitioning var_crash disk. Partition mount options were not defined."
  fi
  var_crash_block_device="$(readlink -f "$var_crash_pci_id_file")"
  die_if_null "Var crash partition block device: '$var_crash_block_device'"
  mount_line="UUID=$vc_uuid $var_crash_mount_point $var_crash_format $var_crash_mount_options 0 0"
  if ! grep "^$mount_line$" $fstab; then
    # remove any previous mounts of this partition
    sed -i "/^UUID=$vc_uuid/d" $fstab
    sed -i "\@^$var_crash_block_device@d" $fstab
    sed -i "\@ $var_crash_mount_point @d" $fstab
    # write the new mount
    echo "$mount_line" >> $fstab
  fi
  mount -a
}

set_interface_mtu() {
  local interface="$1"
  local mtu="$2"
  log.DEBUG2 "Setting $interface MTU to $mtu"
  ip link set dev ${interface} mtu ${mtu} || true
}

update_yaml(){
  local key="$1"
  local value="$2"
  local input_yaml="$3"
  outfile="$(mktemp)"
  FAIL=false
  RESULT=`python3 -c "
import yaml
with open('$input_yaml') as infile:
  doc = yaml.safe_load(infile)
doc "$key" = $value
with open('$outfile', 'w') as outfile:
  yaml.safe_dump(doc, outfile, indent=4, default_flow_style=False)
" 2>&1` || FAIL=true
  if [[ $FAIL = true ]]; then
    log.ERROR "Unable to set $key to $value in $input_yaml"
    die "Existing netplan configuration may not have all interfaces defined"
  else
    mv -f $outfile $input_yaml
    chmod 644 $input_yaml
    log.DEBUG2 "Updated $key MTU to $value in $input_yaml"
  fi
}

###############################################################################
# Script inputs and validations
###############################################################################

if [[ $EUID -ne 0 ]]; then
  die "This script must be run as sudo/root"
fi

if ([[ -z $1 ]] && [[ -z $RENDERED ]]) || [[ $1 =~ .*[hH][eE][lL][pP].* ]]; then
  log.ERROR "Missing required script argument"
  die "Usage: ./$(basename $BASH_SOURCE) /path/to/rendered/site/manifest.yaml"
fi

if [[ -n $1 ]]; then
  rendered_file="$1"
else
  rendered_file="$RENDERED"
fi
if [[ ! -f $rendered_file ]]; then
  die "Specified rendered manifests file '$rendered_file' does not exist"
fi
log.DEBUG2 "Using rendered manifests file '$rendered_file'"

# There is an outstanding bug when pegleg writes manifest output to stdout that
# includes ^M (carriage returns) among other formatting issues which will cause
# problems with YAML parsing. To avoid this, pegleg's '-o' option must be used
# to write the output directly to file instead of to stdout.
# Here we look at just the first 5 lines of the file, since ^M's may be present
# in other encoded scripts.
if [[ $(head -5 "$rendered_file" | grep $'\r$' | wc -l) -gt 1 ]]; then
  die "Detected carriage returns in '$rendered_file'. Avoid this Pegleg bug by using its '-o' option to write the rendered output to file instead of stdout."
fi

# There are numerous bugs with the formatting in the output of `pegleg render`.
# This is a workaround for one of those bugs which causes quotations to sometimes
# get dropped from the value segment of key-value pairs, which causes issues in
# reading numeric data and other data with certain characters.
sed -i "s/\(.* address: \)\([^'].*\)/\1'\2'/g" "$rendered_file"

# This is a workaround for another bug which has not been merged as of this
# writing. This workaround can be removed after merge of
# https://review.openstack.org/#/c/604123
if [[ $(tail -1 "$rendered_file") != '...' ]]; then
  echo '...' >> "$rendered_file"
fi
if [[ $(head -1 "$rendered_file") != '---' ]]; then
  sed -i '1s;^;---\n;' "$rendered_file"
fi

# Install python yaml parsing module if not already. There is a catch22
# here in that this package is a pre-requisite for reading the rendered YAML
# which contains the desired apt source list settings. In other words this
# package has to be installed prior to configuring the apt source list to
# the manifest-specified value, which could fail and have to be resolved
# manually
apt_install python3-yaml

# Get site type since some actions are specific to certain site types
site_type="$(grep 'site_type: [a-zA-Z]' "$rendered_file" | awk '{print $2}')"

# Get the subset of manifests that has only the needed documents (by schema)
filters="$(grep manifests_lookup $BASH_SOURCE | cut -d'"' -f4 | \
           grep -v manifests_lookup | sort | uniq | \
           sed "s/\(.*\)/or x.get('schema') == '\1'/g" | tr '\n' ' ')"
manifests_filter "$rendered_file" "$filters"
# $rendered_file var is now changed to point to the smaller/filtered rendered
# file under /tmp

REBOOT=false

# env vars which can be set if you want to disable certain parts of the script
# (can be uncommented here or simply set in your env)
: ${DISABLE_SSH_NO_PASSWD:=}
: ${DISABLE_DISK_LAYOUT_CHECK:=}
: ${DISABLE_DISK_SIZE_CHECK:=true}
: ${DISABLE_TIMEZONE_ENFORCEMENT:=}
: ${DISABLE_HOSTNAME_AND_FQDN:=}
: ${DISABLE_DNS_CONFIGURE:=}
: ${DISABLE_STANDALONE_MINI_MIRROR:=}
: ${DISABLE_APT_SOURCES_LIST_SETUP:=}
: ${DISABLE_APT_INSTALL:=}
: ${DISABLE_CEPH_JOURNAL_DISK_PREP:='true'}
# v2 = single mounted journal disk, v3 = one or more journal disks partitioned
: ${CEPH_JOURNAL_DESIGN:=v3}
# WARNING: this will wipe the ceph journal disks , don't run on
# a node with a ceph cluster you care about.
: ${WIPE_CEPH_JOURNAL:='true'}
: ${DISABLE_CREATE_VAR_CRASH_PARTITION:='true'}
: ${DISABLE_KERNEL_UPDATE:=}
# v1 = get kernel ver from sstream-cache img, v2 = get kernel ver from manifests
: ${KERNEL_UPDATE_TYPE:=v2}
: ${DISABLE_NTPD_SETUP:=}
: ${DISABLE_APPARMOR_PROFILES:=}
: ${DISABLE_CALICO_IP_RULES:=}
: ${DISABLE_I40E_DRIVER:=}
# v1 = blacklist i40evf only, v2 = blacklist i40evf and install i40e-dkms
: ${I40E_BOOTACTION_VERSION:=v2}
: ${DISABLE_UNATTENDED_UPGRADE:=}
: ${DISABLE_GSTOOLS_PREP:=}
: ${DISABLE_PROMJOIN_PREP:=}
: ${DISABLE_NETWORK_INTERFACES_CONFIG_NETPLAN:=}
: ${DISABLE_OVS_DPDK_KERNEL_PARM:=}
: ${DISABLE_REBOOT:=}

################################################################################
## Set sources.list
################################################################################

# This section assumes that the source list(s) and packages given defined in
# the global versions file are available in the global versions mini-mirror
# image.

# Timeout in seconds to try to reach apt mirror given in manifests
: ${APT_URL_TIMEOUT:=360}

# NOTE(aw442m): Remove ANY previous APT configuration (i.e. proxy) that is
# bundled with ISO or set otherwise. This is required to reach mini-mirror via
# localhost.
rm -f /etc/apt/apt.conf
rm -f /etc/apt/apt.conf.d/90airship-proxy

#DISABLE_STANDALONE_MINI_MIRROR=TRUE
if [[ ! $DISABLE_APT_SOURCES_LIST_SETUP ]]; then


  repositories=()

  manifests_lookup "$rendered_file" "pegleg/SoftwareVersions/v1" \
                   "software-versions" "['data']['packages']['repositories']" \
                   "dict_keys"
  repo_names="$RESULT"

  for r in $repo_names; do
    manifests_lookup "$rendered_file" "pegleg/SoftwareVersions/v1" \
                     "software-versions" "['data']['packages']['repositories']['"$r"']['repo_type']"
    repo_type="$RESULT"
    if [[ "$repo_type" != "apt" ]]; then
      continue
    fi

    manifests_lookup "$rendered_file" "pegleg/SoftwareVersions/v1" \
                     "software-versions" "['data']['packages']['repositories']['"$r"']['url']"
    repo_url="$RESULT"

    # distributions: bionic, xenial, etc.
    manifests_lookup "$rendered_file" "pegleg/SoftwareVersions/v1" \
                     "software-versions" "['data']['packages']['repositories']['"$r"']['distributions']"
    repo_distros="$RESULT"

    # subrepos: updates, security, etc. (optional, key might not exist, so allow_fail on lookup)
    manifests_lookup "$rendered_file" "pegleg/SoftwareVersions/v1" \
                     "software-versions" "['data']['packages']['repositories']['"$r"']['subrepos']" \
                     "" true
    if [[ $FAIL != true ]]; then
      repo_subrepos="$RESULT"
    else
      repo_subrepos=""
    fi

    # components: main, universe, multiverse, etc.
    manifests_lookup "$rendered_file" "pegleg/SoftwareVersions/v1" \
                     "software-versions" "['data']['packages']['repositories']['"$r"']['components']"
    repo_components="$(echo $RESULT)"

    # add to the list of candidate repos
    # each entry will be similar to a sources.list entry, without the leading 'deb'
    for dist in $repo_distros; do
      repo="${repo_url} ${dist} ${repo_components}"
      repositories+=("$repo")
      for subrepo in $repo_subrepos; do
        repo="${repo_url} ${dist}-${subrepo} ${repo_components}"
        repositories+=("$repo")
      done
    done

    # Fetch repo key
    manifests_lookup "$rendered_file" "pegleg/SoftwareVersions/v1" \
                     "software-versions" "['data']['packages']['repositories']['"$r"']['gpgkey']"
    key="$RESULT"
    echo "$key" | apt-key add -
  done

  temp_sources="/etc/apt/sources.list.temp"
  echo -n '' > "${temp_sources}"

  for repository in "${repositories[@]}"; do
    interval=15 # 15 second interval
    time_waited=0
    repo_health=bad
    while [[ $time_waited < $APT_URL_TIMEOUT ]]; do
      if curl --max-time $interval "${repository%% *}/"; then
        repo_health=good
        break
      fi
      time_waited=$(($time_waited + $interval))
    done
    # write the new repo to apt config if it passed connection check
    if [[ $repo_health = good ]]; then
      # write new sources.list.temp
      if ! grep "^deb ${repository}" "${temp_sources}"; then
        echo "deb ${repository}" >> "${temp_sources}"
      fi
    else
      die "ERROR: Could not reach ${repository%% *} after ${APT_URL_TIMEOUT}s of trying! Is Apt repo down?"
    fi
  done
  if grep -q '^deb ' "${temp_sources}"; then
    mv "${temp_sources}" /etc/apt/sources.list
  fi

  apt-key update
  apt-get update || die "Failed to run 'apt-get update'. Check your apt source list."

fi


###############################################################################
# Install matching kernel version - v2 = get kernel ver from manifests
###############################################################################

# If maniests dont specify a kernel package, use this one
: ${KERNEL_PACKAGE:=linux-image-4.15.0-46-generic}

# Reboot automatically without prompting if a known bad kernel version is
# detected, provided the target kernel is staged to take over after reboot.
: ${BAD_KERNEL_REBOOT:=}

if [[ ! $DISABLE_KERNEL_UPDATE ]] && [[ $KERNEL_UPDATE_TYPE = v2 ]]; then

  # Fetch kernel image type
  manifests_lookup "$rendered_file" "drydock/HostProfile/v1" \
                   "$CONTROL_PLANE_HOST_PROFILE_SAMPLE" \
                   "['data']['platform']['kernel_params']['kernel_package']" \
                   "none" "true"
  kernel_package="$RESULT"
  if [[ $FAIL = true ]]; then
    log.DEBUG2 "Manifests lookup of kernel version failed; using $KERNEL_PACKAGE"
    kernel_package=$KERNEL_PACKAGE
  else
    log.DEBUG2 "Kernel package located: '$kernel_package'"
  fi

  # install kernel
  apt_install $kernel_package

  # install headers
  kernel_headers_pkg="linux-headers-$(echo "$kernel_package" | grep -o '[0-9].*')"
  apt_install $kernel_headers_pkg

  # Check if we are using a known bad kernel version that causes
  # an inability to timesync to NTP servers.
  if uname -a | grep '4.13.0-36-generic'; then
    if dpkg -s $kernel_package 2> /dev/null | grep 'Status: install ok installed'; then
      log.WARN "YOU ARE USING A KNOWN BAD KERNEL VERSION, but appear to have installed the target kernel version."
      log.WARN "You must reboot, and then RERUN THIS SCRIPT with the same arguments and env vars as previously."
      log.WARN "To be clear, YOU MUST COMPLETE RUNNING THIS SCRIPT AFTER REBOOT."
      if [[ -z $BAD_KERNEL_REBOOT ]]; then
        log.WARN "Reboot now? (y/n)"
        read BAD_KERNEL_REBOOT
      fi
      if [[ $BAD_KERNEL_REBOOT = y ]] || [[ $BAD_KERNEL_REBOOT = true ]]; then
        log.WARN "REBOOTING IN 30 SECONDS..."
        sleep 30
        log.WARN "REBOOTING..."
        reboot
      else
        die "Quitting without reboot."
      fi
    else
      die "YOU ARE USING A KNOWN BAD KERNEL VERSION, AND DON'T SEEM TO HAVE INSTALLED THE TARGET KERNEL VERSION."
    fi
  fi
fi


###############################################################################
# bootaction: seccomp-profiles
###############################################################################

if [[ ! $DISABLE_SECCOMP_PROFILE ]]; then
  # Fetch seccomp profile data
  manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                   "seccomp-profiles" "['data']['assets'][0]['path']"
  path="$RESULT"
  log.DEBUG2 "seccomp profiles asset[0] path located: '$file'"
  manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                   "seccomp-profiles" "['data']['assets'][0]['permissions']"
  permissions="$RESULT"
  log.DEBUG2 "seccomp profiles asset[0] permissions located: '$permissions'"
  manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                   "seccomp-profiles" "['data']['assets'][0]['data']"
  content="$RESULT"
  log.DEBUG2 "seccomp profiles assets[0] data located: '$content'"

  # seccomp_default
  install_file "$path" "$content" "$permissions"
fi

###############################################################################
# OVS-DPDK: Additional kernel parameters and hugepages
#           Applicable to any Genesis node using nc-cp-primary-adv profile
###############################################################################
if [[ ! $DISABLE_OVS_DPDK_KERNEL_PARM ]] && \
   [[ $CONTROL_PLANE_HOST_PROFILE_SAMPLE == nc-cp-primary-adv ]]; then

  manifests_lookup "$rendered_file" "drydock/HostProfile/v1" \
                   "$CONTROL_PLANE_HOST_PROFILE_SAMPLE" \
                   "['data']['platform']['kernel_params']" \
                   "dict_keys" "true"
  kernel_params=$RESULT
  log.DEBUG2 "kernel_params: '$kernel_params'"

  grub_args=()
  # NOTE: reverse sort is to ensure hugepagesz is before hugepages
  for kp in $(echo $kernel_params | tr ' ' '\n' | sort -r); do
    manifests_lookup "$rendered_file" "drydock/HostProfile/v1" \
                     "$CONTROL_PLANE_HOST_PROFILE_SAMPLE" \
                     "['data']['platform']['kernel_params']['$kp']"
    log.DEBUG2 "OVS-DPDK kernel parameter '$kp': '$RESULT'"
    if [[ $(tr '[:lower:]' '[:upper:]' <<< "$RESULT") == "TRUE" ]]; then
      grub_args+=("$kp")
    else
      grub_args+=("$kp=$RESULT")
    fi
  done

  path="/etc/default/grub.d/50-curtin-settings.cfg"
  content="GRUB_CMDLINE_LINUX_DEFAULT=\"${grub_args[@]}\""

  install_file "$path" "$content" '644' false false reboot

  update-grub
fi

###############################################################################
# Cleanup & Reboot
###############################################################################

log.DEBUG2 "All operations completed successfully. Going for reboot in 30 seconds"
sleep 30
reboot
#
