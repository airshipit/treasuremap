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
"""Print data of a document from rendered site documents.

Usage: get-document-data.py <rendered.yaml> <schema> <name> [<path>]

<path> is a dot separated list of keys inside the document data,
e.g. "values.certs.ca.crt". Strings are printed as is, other scalars
as YAML values (e.g. "true", "2"), mappings and lists as YAML.
"""

import sys

import yaml


def main(argv):
    if len(argv) not in (4, 5):
        sys.exit(__doc__)
    rendered, schema, name = argv[1:4]
    path = argv[4].split('.') if len(argv) == 5 and argv[4] else []

    with open(rendered) as f:
        for doc in yaml.safe_load_all(f):
            if not doc or doc.get('schema') != schema or \
                    doc.get('metadata', {}).get('name') != name:
                continue
            data = doc.get('data')
            for key in path:
                if not isinstance(data, dict) or key not in data:
                    sys.exit('Key "%s" is not found in %s %s' %
                             ('.'.join(path), schema, name))
                data = data[key]
            if isinstance(data, str):
                sys.stdout.write(data if data.endswith('\n') else data + '\n')
            elif isinstance(data, (dict, list)):
                yaml.safe_dump(data, sys.stdout, default_flow_style=False)
            else:
                # scalars as YAML without the document end marker
                sys.stdout.write(yaml.safe_dump(data).splitlines()[0] + '\n')
            return
    sys.exit('Document %s %s is not found in %s' % (schema, name, rendered))


if __name__ == '__main__':
    main(sys.argv)
