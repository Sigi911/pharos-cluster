#!/bin/bash

set -e

etcd_healthy() {
  response=$(curl -s --cacert /etc/pharos/pki/ca.pem --cert /etc/pharos/pki/etcd/client.pem --key /etc/pharos/pki/etcd/client-key.pem https://${PEER_IP}:2379/health)
  [ "${response}" = '{"health": "true"}' ]
}

etcd_version_matches() {
  grep -q "etcd-${ARCH}:${ETCD_VERSION}" /etc/kubernetes/manifests/pharos-etcd.yaml
}

mkdir -p /etc/kubernetes/manifests
mkdir -p /etc/kubernetes/tmp
if [ ! -e /etc/kubernetes/manifests/pharos-etcd.yaml ] || [ ! etcd_version_matches ] || [ ! etcd_healthy ]; then
  cat  >/etc/kubernetes/tmp/pharos-etcd.yaml <<EOF && mv /etc/kubernetes/tmp/pharos-etcd.yaml /etc/kubernetes/manifests/pharos-etcd.yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --name=${PEER_NAME}
    - --cert-file=/etc/kubernetes/pki/etcd/server.pem
    - --key-file=/etc/kubernetes/pki/etcd/server-key.pem
    - --trusted-ca-file=/etc/kubernetes/pki/ca.pem
    - --peer-trusted-ca-file=/etc/kubernetes/pki/ca.pem
    - --data-dir=/var/lib/etcd
    - --peer-cert-file=/etc/kubernetes/pki/etcd/peer.pem
    - --peer-key-file=/etc/kubernetes/pki/etcd/peer-key.pem
    - --listen-client-urls=https://localhost:2379,https://${PEER_IP}:2379
    - --advertise-client-urls=https://${PEER_IP}:2379
    - --listen-peer-urls=https://${PEER_IP}:2380
    - --initial-advertise-peer-urls=https://${PEER_IP}:2380
    - --client-cert-auth=true
    - --peer-client-cert-auth=true
    - --initial-cluster=${INITIAL_CLUSTER}
    - --initial-cluster-token=pharos-etcd-token
    - --initial-cluster-state=${INITIAL_CLUSTER_STATE}

    image: ${IMAGE_REPO}/etcd-${ARCH}:${ETCD_VERSION}
    livenessProbe:
      exec:
        command:
        - /bin/sh
        - -ec
        - ETCDCTL_API=3 etcdctl --endpoints=localhost:2379 --cacert=/etc/kubernetes/pki/ca.pem
          --cert=/etc/kubernetes/pki/etcd/client.pem --key=/etc/kubernetes/pki/etcd/client-key.pem
          get foo
      failureThreshold: 8
      initialDelaySeconds: 15
      timeoutSeconds: 15
    name: etcd
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
    - mountPath: /etc/kubernetes/pki
      name: etcd-certs
  hostNetwork: true
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
  - hostPath:
      path: /etc/pharos/pki
      type: DirectoryOrCreate
    name: etcd-certs
EOF
fi


if [ ! -e /etc/kubernetes/kubelet.conf ]; then
  mkdir -p /etc/systemd/system/kubelet.service.d
  cat <<EOF >/etc/systemd/system/kubelet.service.d/5-pharos-etcd.conf
[Service]
ExecStartPre=-/sbin/swapoff -a
ExecStart=
ExecStart=/usr/bin/kubelet ${KUBELET_ARGS} --pod-infra-container-image=${IMAGE_REPO}/pause-${ARCH}:3.1
EOF

  apt-mark unhold kubelet
  apt-get install -y kubelet=${KUBE_VERSION}-00
  apt-mark hold kubelet
fi

echo "Waiting etcd to launch on port 2380..."
while ! etcd_healthy; do
  sleep 1
done
echo "etcd launched"