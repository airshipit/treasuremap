#!/usr/bin/env python3

# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
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

#
# versions.yaml file updater tool
#
# Being run in directory with versions.yaml, will create versions.new.yaml,
# with updated git commit id's to the latest HEAD in:
#   1) references of all charts
#   2) tags of container images listed in dict `image_repo_git_url` in the
#      code below
#

from functools import reduce
import argparse
import logging
import operator
import os
import sys

try:
    import git
    import yaml
except ImportError as e:
    sys.exit("Failed to import git/yaml libraries needed to run" +
             "this tool %s" % str(e))

descr_text="Process versions.yaml and create versions.new.yaml with \
           updated git commit id\'s to the latest HEAD in: \
           1) references of all charts \
           2) tags of container images listed in dict \
           `image_repo_git_url` in the code."
parser = argparse.ArgumentParser(description=descr_text)

# Dictionary containing container image repository url to git url mapping
#
# We expect that each image in container image repository has image tag which
# equals to the git commit id of the HEAD in corresponding git repository
image_repo_git_url = {
    # airflow image is built from airship-shipyard repository
    'quay.io/airshipit/airflow': 'https://git.openstack.org/openstack/airship-shipyard',
    'quay.io/airshipit/armada': 'https://git.openstack.org/openstack/airship-armada',
    'quay.io/airshipit/deckhand': 'https://git.openstack.org/openstack/airship-deckhand',
    'quay.io/airshipit/divingbell': 'https://git.openstack.org/openstack/airship-divingbell',
    'quay.io/airshipit/drydock': 'https://git.openstack.org/openstack/airship-drydock',
    # maas-{rack,region}-controller images are built from airship-maas repository
    'quay.io/airshipit/maas-rack-controller': 'https://git.openstack.org/openstack/airship-maas',
    'quay.io/airshipit/maas-region-controller': 'https://git.openstack.org/openstack/airship-maas',
    'quay.io/airshipit/pegleg': 'https://git.openstack.org/openstack/airship-pegleg',
    'quay.io/airshipit/promenade': 'https://git.openstack.org/openstack/airship-promenade',
    'quay.io/airshipit/shipyard': 'https://git.openstack.org/openstack/airship-shipyard',
    # sstream-cache image is built from airship-maas repository
    'quay.io/airshipit/sstream-cache': 'https://git.openstack.org/openstack/airship-maas',
    'quay.io/attcomdev/nagios': 'https://github.com/att-comdev/nagios'
    # Disabled by Kaspars: https://review.openstack.org/#/c/596909/21/tools/updater.py@53
    #'quay.io/attcomdev/prometheus-openstack-exporter': 'https://github.com/att-comdev/prometheus-openstack-exporter'
}

logging.basicConfig(level=logging.INFO)

# Temporary dict of git url's and cached commit id's: {'git_url': 'commit_id'}
git_url_commit_ids = {}
dict_path = None


# https://stackoverflow.com/a/35585837
def lsremote(url, remote_ref):
    """Accepts git url and remote reference, returns git commit id."""
    git_commit_id_remote_ref = {}
    g = git.cmd.Git()
    logging.info('Fetching ' + url + ' ' + remote_ref + ' reference...')
    hash_ref_list = g.ls_remote(url, remote_ref).split('\t')
    git_commit_id_remote_ref[hash_ref_list[1]] = hash_ref_list[0]
    return git_commit_id_remote_ref[remote_ref]


def get_commit_id(url):
    """Accepts url of git repo and returns corresponding git commit hash"""
    # If we don't have this git url in our url's dictionary,
    # fetch latest commit ID and add new dictionary entry
    logging.debug('git_url_commit_ids: %s', git_url_commit_ids)
    if url not in git_url_commit_ids:
        logging.debug('git url: ' + url +
                      ' is not in git_url_commit_ids dict;' +
                      ' adding it with HEAD commit id')
        git_url_commit_ids[url] = lsremote(url, 'HEAD')
    return git_url_commit_ids[url]


# https://stackoverflow.com/a/14692747
def get_by_path(root, items):
    """Access a nested object in root by item sequence."""
    return reduce(operator.getitem, items, root)


def set_by_path(root, items, value):
    """Set a value in a nested object in root by item sequence."""
    get_by_path(root, items[:-1])[items[-1]] = value


# Based on http://nvie.com/posts/modifying-deeply-nested-structures/
def traverse(obj, dict_path=None):
    """Accepts Python dictionary with values.yaml contents,
    updates it with latest git commit id's.
    """
    logging.debug('traverse: dict_path: %s, object type: %s, object: %s',
                  dict_path, type(obj), obj)

    if dict_path is None:
        dict_path = []

    if isinstance(obj, dict):
        # It's a dictionary element
        logging.debug('this object is a dictionary')

        for k, v in obj.items():
            # If value v we are checking is a dictionary itself, and this
            # dictionary contains key named 'type', and a value of key 'type'
            # equals 'git', then
            if isinstance(v, dict) and 'type' in v and v['type'] == 'git':

                old_git_commit_id = v['reference']
                git_url = v['location']

                new_git_commit_id = get_commit_id(git_url)

                # Update git commit id in reference field of dictionary
                if old_git_commit_id != new_git_commit_id:
                    logging.info('Updating git reference for chart %s from %s to ' +
                                 '%s (%s)',
                                 k, old_git_commit_id, new_git_commit_id,
                                 git_url)
                    v['reference'] = new_git_commit_id
                else:
                    logging.info('Git reference %s for chart %s is already up to date (%s) ',
                                 old_git_commit_id, k, git_url)
            else:
                logging.debug('value %s inside object is not a dictionary, or it does not ' +
                              'contain key \'type\' with value \'git\', skipping', v)

            # Traverse one level deeper
            traverse(v, dict_path + [k])
    elif isinstance(obj, list):
        # It's a list element
        logging.debug('this object is a list')

        for elem in obj:
            # TODO: Do we have any git references or container image tags in
            # versions.yaml which are inside lists? Probably not.
            traverse(elem, dict_path + [[]])
    else:
        # It's already a value
        logging.debug('this object is a value')
        v = obj

        # Searching for container image repositories, we are only intrested in
        # strings; there could also be booleans or other types we are not interested in.
        if isinstance(v, str):
            for image_repo, git_url in image_repo_git_url.items():
                if image_repo in v:
                    logging.debug('image_repo %s is in %s string', image_repo, v)

                    # hash_v: {'&whatever repo_url', 'git commit id tag'}
                    # Note: 'image' below could contain not just image, but also
                    # '&ref host.domain/path/image'
                    hash_v = v.split(":")
                    image, old_git_commit_id = hash_v

                    new_git_commit_id = get_commit_id(git_url)

                    # Update git commit id in tag of container image
                    if old_git_commit_id != new_git_commit_id:
                        logging.info('Updating git commit id in' +
                                     ' tag of container image %s from %s to' +
                                     ' %s (%s)',
                                     image, old_git_commit_id,
                                     new_git_commit_id, git_url)
                        set_by_path(versions_data_dict, dict_path, image + ':' + new_git_commit_id)

                    else:
                        logging.info('Git tag %s for container ' +
                                     'image %s is already up to date (%s)',
                                     old_git_commit_id, image, git_url)
                else:
                    logging.debug('image_repo %s is not in %s string, skipping', image_repo, v)
        else:
            logging.debug('value %s is not string, skipping', v)


if __name__ == '__main__':
    """Small Main program"""

    parser.add_argument('--in-file', default = 'versions.yaml', help = '/path/to/versions.yaml file')
    args = parser.parse_args()

    in_file = args.in_file

    if os.path.isfile(in_file):
        out_file = os.path.join(os.path.dirname(os.path.abspath(in_file)), 'versions.new.yaml')
        with open(in_file, 'r') as f:
            f_old = f.read()
            versions_data_dict = yaml.safe_load(f_old)
    else:
        logging.error("Can\'t find versions.yaml file.\n")
        parser.print_help()
        sys.exit(1)

    # Traverse loaded yaml and change it
    traverse(versions_data_dict)

    with open(out_file, 'w') as f:
        f.write(yaml.safe_dump(versions_data_dict,
                               default_flow_style=False, default_style='\"',
                               explicit_end=True, explicit_start=True,
                               width=4096))
        logging.info('New versions.yaml created as %s' % out_file)
