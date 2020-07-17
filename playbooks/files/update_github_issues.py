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
import logging
import re
import sys

import github

GH_USER = sys.argv[1]
GH_PW = sys.argv[2]
ZUUL_MESSAGE = sys.argv[3]
GERRIT_URL = sys.argv[4]
REPO_NAME = 'airshipit/airshipctl'
PROCESS_LABELS = ['wip', 'ready for review', 'triage', 'blocked']


def construct_issue_list(match_list: list) -> set:
    new_list = []
    for _issue in match_list:
        try:
            new_list.append(int(_issue))
        except ValueError:
            logging.warning(f'Value {_issue} could not be converted to `int` type')
    return set(new_list)


def parse_issue_number(commit_msg: str) -> dict:
    # Searches for Relates-To or Closes tags first to match and return
    logging.debug(f'Parsing commit message: {commit_msg}')
    related = re.findall(r'(?<=Relates-To: #)([0-9]+?)(?=\n)', commit_msg)
    logging.debug(f'Captured related issues: {related}')
    closes = re.findall(r'(?<=Closes: #)([0-9]+?)(?=\n)', commit_msg)
    logging.debug(f'Captured closes issues: {closes}')
    if related or closes:
        return {
            'related': construct_issue_list(related),
            'closes': construct_issue_list(closes)
        }
    # If no Relates-To or Closes tags are defined, find legacy [#X] style tags
    logging.debug('Falling back to legacy tags')
    legacy_matches = re.findall(r'(?<=\[#)([0-9]+?)(?=\])', commit_msg)
    logging.debug(f'Captured legacy issues: {legacy_matches}')
    if not legacy_matches:
        return {}
    return {
        'related': construct_issue_list(legacy_matches)
    }


def remove_duplicated_issue_numbers(issue_dict: dict) -> dict:
    if 'closes' in issue_dict:
        issue_dict['related'] = [x for x in issue_dict.get('related', []) if x not in issue_dict['closes']]
    return issue_dict


if __name__ == '__main__':
    issue_number_dict = parse_issue_number(ZUUL_MESSAGE)
    issue_number_dict = remove_duplicated_issue_numbers(issue_number_dict)
    gh = github.Github(GH_USER, GH_PW)
    repo = gh.get_repo(REPO_NAME)
    for key, issue_list in issue_number_dict.items():
        for issue_number in issue_list:
            issue = repo.get_issue(number=issue_number)
            comment_msg = ''
            link_exists = False
            if key == 'closes':
                issue.create_comment(f'The [Change]({GERRIT_URL}) that closes this issue was merged.')
                for label in PROCESS_LABELS:
                    try:
                        issue.remove_from_labels(label)
                    except github.GithubException:
                        pass
            else:
                issue.create_comment(f'A [Related Change]({GERRIT_URL} was merged. This issue may be ready to close.')
