#!/bin/bash

kubectl exec -it airflow-worker-0 -c airflow-worker -n ucp -- sh -c "find logs/update_software/ -print -type f -exec cat {} \;"
