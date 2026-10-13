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
"""Set data of a document of the site in the repository (in place).

Usage: set-document-data.py <site> <schema> <name> <path>=<value>...

The document of the most specific layer of the site (site, then the site
type, then global) is changed: the change applies to the documents layered
on or substituted from it, as the site documents are rendered by Pegleg and
by Deckhand (the documents of the site are uploaded to it as they are, see
050-armada-apply.sh). Used by the gate to change the configuration deployed
by Armada on day 2, the site is rendered again then (020-render-site.sh).

<path> is a dot separated list of keys inside the document data,
e.g. "values.kubelet.restart". <value> is parsed as YAML, missing keys
are created.
"""

import glob
import os
import sys

import yaml


def site_type(site):
    for path in glob.glob('site/%s/**/*.yaml' % site, recursive=True):
        with open(path) as f:
            for doc in yaml.safe_load_all(f):
                if doc and doc.get('schema') == 'pegleg/SiteDefinition/v1':
                    return doc['data']['site_type']
    sys.exit('Site definition of %s is not found' % site)


def find_document(site, schema, name):
    for layer_dir in ('site/%s' % site, 'type/%s' % site_type(site), 'global'):
        for path in sorted(glob.glob('%s/**/*.yaml' % layer_dir,
                                     recursive=True)):
            with open(path) as f:
                docs = list(yaml.safe_load_all(f))
            for doc in docs:
                if doc and doc.get('schema') == schema and \
                        doc.get('metadata', {}).get('name') == name:
                    return path, docs, doc
    sys.exit('Document %s %s of the site %s is not found' %
             (schema, name, site))


def main(argv):
    if len(argv) < 5:
        sys.exit(__doc__)
    site, schema, name = argv[1:4]
    path, docs, doc = find_document(site, schema, name)

    for assignment in argv[4:]:
        key_path, sep, value = assignment.partition('=')
        if not sep or not key_path:
            sys.exit('Invalid assignment "%s", expected <path>=<value>' %
                     assignment)
        keys = key_path.split('.')
        data = doc.setdefault('data', {})
        for key in keys[:-1]:
            data = data.setdefault(key, {})
            if not isinstance(data, dict):
                sys.exit('Key "%s" of %s %s is not a mapping' %
                         (key, schema, name))
        data[keys[-1]] = yaml.safe_load(value)

    with open(path, 'w') as f:
        yaml.safe_dump_all([d for d in docs if d], f, default_flow_style=False,
                           explicit_start=True, sort_keys=False)
    print('%s %s: %s' % (schema, name, os.path.relpath(path)))


if __name__ == '__main__':
    main(sys.argv)
