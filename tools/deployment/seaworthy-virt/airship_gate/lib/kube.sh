#!/bin/bash

kubectl_apply() {
    VIA=${1}
    FILE=${2}
    ssh_cmd_raw "${VIA}" "KUBECONFIG=${KUBECONFIG}" "cat ${FILE} | kubectl apply -f -"
}

kubectl_cmd() {
    VIA=${1}

    shift

    ssh_cmd_raw "${VIA}" "KUBECONFIG=${KUBECONFIG}" kubectl "${@}"

}

kubectl_wait_for_pod() {
    VIA=${1}
    NAMESPACE=${2}
    POD_NAME=${3}
    SEC=${4:-600}
    log Waiting "${SEC}" seconds for termination of pod "${POD_NAME}"

    POD_PHASE_JSONPATH='{.status.phase}'

    end=$(($(date +%s) + SEC))
    while true; do
        POD_PHASE=$(kubectl_cmd "${VIA}" --request-timeout 10s --namespace "${NAMESPACE}" get -o jsonpath="${POD_PHASE_JSONPATH}" pod "${POD_NAME}")
        if [[ ${POD_PHASE} = "Succeeded" ]]; then
            log Pod "${POD_NAME}" succeeded.
            break
        elif [[ $POD_PHASE = "Failed" ]]; then
            log Pod "${POD_NAME}" failed.
            kubectl_cmd "${VIA}" --request-timeout 10s --namespace "${NAMESPACE}" get -o yaml pod "${POD_NAME}" 1>&2
            exit 1
        else
            now=$(date +%s)
            if [[ $now -gt $end ]]; then
                log Pod did not terminate before timeout.
                kubectl_cmd "${VIA}" --request-timeout 10s --namespace "${NAMESPACE}" get -o yaml pod "${POD_NAME}" 1>&2
                exit 1
            fi
            sleep 1
        fi
    done
}
