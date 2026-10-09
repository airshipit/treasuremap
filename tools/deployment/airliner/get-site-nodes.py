#!/usr/bin/env python3
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
"""Print nodes of the kubeadm chart document of rendered site documents.

Usage: get-site-nodes.py <rendered.yaml> all|local

Prints "<name> <ip> <role> <phase>" lines, where phase is the bootstrap
phase of the node: "init" for the first control plane node,
"control-plane" for the rest of control plane nodes and "worker".

"all" prints all nodes. "local" prints the node which IP is configured on
this machine; a single node site prints its node even if its IP is not
configured yet (the bootstrap script brings it up).
"""

import subprocess
import sys

import yaml


def site_nodes(rendered):
    with open(rendered) as f:
        for doc in yaml.safe_load_all(f):
            if doc and doc.get('schema') == 'armada/Chart/v1' and \
                    doc.get('metadata', {}).get('name') == 'kubeadm':
                nodes = doc['data']['values']['nodes']
                break
        else:
            sys.exit('Document armada/Chart/v1 kubeadm is not found')

    init_done = False
    for node in nodes:
        phase = 'worker'
        if node['role'] == 'control-plane':
            phase = 'control-plane' if init_done else 'init'
            init_done = True
        node['phase'] = phase
    if not init_done:
        sys.exit('No control plane nodes defined')
    return nodes


def local_ips():
    out = subprocess.check_output(['ip', '-4', '-o', 'addr', 'show'], text=True)
    return {line.split()[3].split('/')[0] for line in out.splitlines()}


def main(argv):
    if len(argv) != 3 or argv[2] not in ('all', 'local'):
        sys.exit(__doc__)
    nodes = site_nodes(argv[1])
    if argv[2] == 'local':
        ips = local_ips()
        nodes = [n for n in nodes if n['ip'] in ips] or \
            (nodes if len(nodes) == 1 else [])
        if not nodes:
            sys.exit('None of the site node IPs is configured on this machine')
    for n in nodes:
        print(n['name'], n['ip'], n['role'], n['phase'])


if __name__ == '__main__':
    main(sys.argv)
