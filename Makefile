# Copyright 2017 AT&T Intellectual Property.  All other rights reserved.
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

SHELL := /bin/bash
BUILD_DIR := build
KUBEVAL_BIN := $(BUILD_DIR)/bin

.PHONY: all
all: docs

.PHONY: clean
clean:
	rm -rf doc/build $(BUILD_DIR)

.PHONY: docs
docs: clean build_docs

.PHONY: build_docs
build_docs:
	tox -e docs

# Perform auto formatting
.PHONY: format
format:
	tox -e fmt

# Validate all URL references in documentation work
.PHONY: dead-link-linter
dead-link-linter:
	@./tools/dead-link-linter
