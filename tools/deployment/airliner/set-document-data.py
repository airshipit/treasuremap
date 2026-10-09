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
"""Set data of a document in rendered site documents (in place).

Usage: set-document-data.py <rendered.yaml> <schema> <name> <path>=<value>...

<path> is a dot separated list of keys inside the document data,
e.g. "values.kubelet.restart". <value> is parsed as YAML, missing keys
are created. Used by the gate to change the configuration deployed by
Armada on day 2.
"""

import sys

import yaml


def main(argv):
    if len(argv) < 5:
        sys.exit(__doc__)
    rendered, schema, name = argv[1:4]

    with open(rendered) as f:
        docs = list(yaml.safe_load_all(f))
    for doc in docs:
        if doc and doc.get('schema') == schema and \
                doc.get('metadata', {}).get('name') == name:
            break
    else:
        sys.exit('Document %s %s is not found in %s' % (schema, name, rendered))

    for assignment in argv[4:]:
        path, sep, value = assignment.partition('=')
        if not sep or not path:
            sys.exit('Invalid assignment "%s", expected <path>=<value>' %
                     assignment)
        keys = path.split('.')
        data = doc.setdefault('data', {})
        for key in keys[:-1]:
            data = data.setdefault(key, {})
            if not isinstance(data, dict):
                sys.exit('Key "%s" of %s %s is not a mapping' %
                         (key, schema, name))
        data[keys[-1]] = yaml.safe_load(value)

    with open(rendered, 'w') as f:
        yaml.safe_dump_all(docs, f, default_flow_style=False,
                           explicit_start=True)


if __name__ == '__main__':
    main(sys.argv)
