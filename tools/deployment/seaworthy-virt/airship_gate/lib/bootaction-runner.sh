#!/bin/bash
#
# Copyright 2019 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


###############################################################################
# Helper functions
###############################################################################

# Key/value lookups from manifests
manifests_lookup(){
  local file="$1"
  local schema="$2"
  local mdata_name="$3"
  local key_path="$4"
  local oper="$5"
  local allow_fail="$6"

  FAIL=false
  RESULT=$(python3 -c "
import yaml,sys
y = yaml.load_all(open('$file'))
for x in y:
  if x.get('schema') == '$schema':
    if x['metadata']['name'] == '$mdata_name':
      if isinstance(x$key_path,list):
        if '$oper' == 'get_size':
          print(len(x$key_path))
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
  sys.exit(1)" 2>&1) || FAIL=true

  if [[ $FAIL = true ]] && [[ $allow_fail != true ]]; then
    echo "Lookup failed for schema '$schema', metadata.name '$mdata_name', key path '$key_path'"
    exit 1
  fi
}


install_file(){
  local path="$1"
  local content="$2"
  local permissions="$3"
  local dirname
  dirname=$(dirname "$path")

  if [[ ! -d $dirname ]]; then
    mkdir -p "$dirname"
  fi

  if [[ ! -f $path ]] || [ "$(cat "$path")" != "$content" ]; then
    echo "$content" > "$path"
    chmod "$permissions" "$path"
    export FILE_UPDATED=true
  else
    export FILE_UPDATED=false
  fi
}


###############################################################################
# Script inputs and validations
###############################################################################

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as sudo/root"
  exit 1
fi

if ([[ -z $1 ]] && [[ -z $RENDERED ]]) || [[ $1 =~ .*[hH][eE][lL][pP].* ]]; then
  echo "Missing required script argument"
  echo "Usage: ./$(basename "${BASH_SOURCE[0]}") /path/to/rendered/site/manifest.yaml"
  exit 1
fi

if [[ -n $1 ]]; then
  rendered_file="$1"
else
  rendered_file="$RENDERED"
fi
if [[ ! -f $rendered_file ]]; then
  echo "Specified rendered manifests file '$rendered_file' does not exist"
  exit 1
fi
echo "Using rendered manifests file '$rendered_file'"

# env vars which can be set if you want to disable
: "${DISABLE_SECCOMP_PROFILE:=}"
: "${DISABLE_APPARMOR_PROFILES:=}"


###############################################################################
# bootaction: seccomp-profiles
###############################################################################

if [[ ! $DISABLE_SECCOMP_PROFILE ]]; then

  # Fetch seccomp profile data
  manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                   "seccomp-profiles" "['data']['assets'][0]['path']"
  path="$RESULT"
  echo "seccomp profiles asset[0] path located: '$path'"
  manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                   "seccomp-profiles" "['data']['assets'][0]['permissions']"
  permissions="$RESULT"
  echo "seccomp profiles asset[0] permissions located: '$permissions'"
  manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                   "seccomp-profiles" "['data']['assets'][0]['data']"
  content="$RESULT"
  echo "seccomp profiles assets[0] data located: '$content'"

  # seccomp_default
  install_file "$path" "$content" "$permissions"
fi

###############################################################################
# bootaction: apparmor-profiles
###############################################################################

if [[ ! $DISABLE_APPARMOR_PROFILES ]]; then

  manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                   "apparmor-profiles" "['data']['assets']" "get_size" "true"

  if [[ -n "$RESULT" ]] && [[ $RESULT -gt 0 ]]; then

    # Fetch apparmor profile data
    LAST=$(( RESULT - 1 ))
    for i in $(seq 0 $LAST); do

      manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                       "apparmor-profiles" "['data']['assets'][$i]['path']"
      path="$RESULT"
      echo "apparmor profiles asset[$i] path located: '$path'"
      manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                       "apparmor-profiles" "['data']['assets'][$i]['permissions']"
      permissions="$RESULT"
      echo "apparmor profiles asset[$i] permissions located: '$permissions'"
      manifests_lookup "$rendered_file" "drydock/BootAction/v1" \
                       "apparmor-profiles" "['data']['assets'][$i]['data']"
      content="$RESULT"
      echo "apparmor profiles assets[$i] data located: '$content'"

      install_file "$path" "$content" "$permissions"
    done

    # reload all apparmor profiles
    systemctl reload apparmor.service
  fi
fi
