#!/bin/bash

export CLUSTER_NAME=""
export DELAY_DS=5
export INSTANA_KEY=""
export INSTANA_ENDPOINT=""

# read params
while getopts "c:d:k:e:" flag
do
    case "${flag}" in
        c) CLUSTER_NAME=${OPTARG};;
        d) DELAY_DS=${OPTARG};;
        k) INSTANA_KEY=${OPTARG};;
        e) INSTANA_ENDPOINT=${OPTARG};;
        *) echo "usage: ./installAgent.sh -c '...your-cluster-name...' -d 3 -k '...your-instana-key...' -e 'ingress-...-saas.instana.io'";;
    esac
done

if [[ -z ${INSTANA_KEY} ]]; then
    echo "Error key"
    exit
fi

if [[ -z ${INSTANA_ENDPOINT} ]]; then
    echo "Error endpoint" 
fi

if [[ -z ${CLUSTER_NAME} ]]; then
    echo "Error cluster name" 
fi


AGENT_VERSION="2.6.0"

echo "Installing instana agent version ${AGENT_VERSION} fro cluster ${CLUSTER_NAME} pointing to ${INSTANA_ENDPOINT}"

oc new-project instana-agent
oc project instana-agent

cat << EOF | oc apply --force -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: instana-agent
  labels:
    app.kubernetes.io/name: instana-agent
    app.kubernetes.io/version: ${AGENT_VERSION}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: instana-agent
  namespace: instana-agent
  labels:
    app.kubernetes.io/name: instana-agent
    app.kubernetes.io/version: ${AGENT_VERSION}
---
apiVersion: v1
kind: Secret
metadata:
  name: instana-agent
  namespace: instana-agent
  labels:
    app.kubernetes.io/name: instana-agent
    app.kubernetes.io/version: ${AGENT_VERSION}
type: Opaque
data:
  key: ${INSTANA_KEY}
  downloadKey: ${INSTANA_KEY}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: instana-agent
  namespace: instana-agent
  labels:
    app.kubernetes.io/name: instana-agent
    app.kubernetes.io/version: ${AGENT_VERSION}
data:
  cluster_name: '${CLUSTER_NAME}'
  configuration.yaml: |
  
    # Manual a-priori configuration. Configuration will be only used when the sensor
    # is actually installed by the agent.
    # The commented out example values represent example configuration and are not
    # necessarily defaults. Defaults are usually 'absent' or mentioned separately.
    # Changes are hot reloaded unless otherwise mentioned.
    
    # It is possible to create files called 'configuration-abc.yaml' which are
    # merged with this file in file system order. So 'configuration-cde.yaml' comes
    # after 'configuration-abc.yaml'. Only nested structures are merged, values are
    # overwritten by subsequent configurations.
    
    # Secrets
    # To filter sensitive data from collection by the agent, all sensors respect
    # the following secrets configuration. If a key collected by a sensor matches
    # an entry from the list, the value is redacted.
    #com.instana.secrets:
    #  matcher: 'contains-ignore-case' # 'contains-ignore-case', 'contains', 'regex'
    #  list:
    #    - 'key'
    #    - 'password'
    #    - 'secret'
    
    # Host
    #com.instana.plugin.host:
    #  tags:
    #    - 'dev'
    #    - 'app1'
    
    # Hardware & Zone
    #com.instana.plugin.generic.hardware:
    #  enabled: true # disabled by default
    #  availability-zone: 'zone'
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: instana-agent
  labels:
    app.kubernetes.io/name: instana-agent
    app.kubernetes.io/version: ${AGENT_VERSION}
rules:
- nonResourceURLs:
    - '/version'
    - '/healthz'
  verbs: ['get']
  apiGroups: []
  resources: []
- apiGroups: ['batch']
  resources:
    - 'jobs'
    - 'cronjobs'
  verbs: ['get', 'list', 'watch']
- apiGroups: ['extensions']
  resources:
    - 'deployments'
    - 'replicasets'
    - 'ingresses'
  verbs: ['get', 'list', 'watch']
- apiGroups: ['apps']
  resources:
    - 'deployments'
    - 'replicasets'
    - 'daemonsets'
    - 'statefulsets'
  verbs: ['get', 'list', 'watch']
- apiGroups: ['']
  resources:
    - 'namespaces'
    - 'events'
    - 'services'
    - 'endpoints'
    - 'nodes'
    - 'pods'
    - 'replicationcontrollers'
    - 'componentstatuses'
    - 'resourcequotas'
    - 'persistentvolumes'
    - 'persistentvolumeclaims'
  verbs: ['get', 'list', 'watch']
- apiGroups: ['']
  resources:
    - 'endpoints'
  verbs: ['create', 'update', 'patch']
- apiGroups: ['networking.k8s.io']
  resources:
    - 'ingresses'
  verbs: ['get', 'list', 'watch']
- apiGroups: ['apps.openshift.io']
  resources:
    - 'deploymentconfigs'
  verbs: ['get', 'list', 'watch']
- apiGroups: ['security.openshift.io']
  resourceNames: ['privileged']
  resources: ['securitycontextconstraints']
  verbs: ['use']
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: instana-agent
  labels:
    app.kubernetes.io/name: instana-agent
    app.kubernetes.io/version: ${AGENT_VERSION}
subjects:
- kind: ServiceAccount
  name: instana-agent
  namespace: instana-agent
roleRef:
  kind: ClusterRole
  name: instana-agent
  apiGroup: rbac.authorization.k8s.io
EOF

oc adm policy add-scc-to-user privileged -z instana-agent -n instana-agent

echo "wait "${DELAY_DS}" secs for stuffs setup..."
sleep ${DELAY_DS}

cat << EOF | oc apply --force -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: instana-agent
  namespace: instana-agent
  labels:
    app.kubernetes.io/name: instana-agent
    app.kubernetes.io/version: ${AGENT_VERSION}
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: instana-agent
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app.kubernetes.io/name: instana-agent
        app.kubernetes.io/version: ${AGENT_VERSION}
        instana/agent-mode: 'APM'
      annotations: {}
    spec:
      serviceAccountName: instana-agent
      hostNetwork: true
      hostPID: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: instana-agent
          image: 'icr.io/instana/agent:latest'
          imagePullPolicy: Always
          env:
            - name: INSTANA_AGENT_LEADER_ELECTOR_PORT
              value: '42655'
            - name: INSTANA_ZONE
              value: ''
            - name: INSTANA_KUBERNETES_CLUSTER_NAME
              valueFrom:
                configMapKeyRef:
                  name: instana-agent
                  key: cluster_name
            - name: INSTANA_AGENT_ENDPOINT
              value: ${INSTANA_ENDPOINT}
            - name: INSTANA_AGENT_ENDPOINT_PORT
              value: '443'
            - name: INSTANA_AGENT_KEY
              valueFrom:
                secretKeyRef:
                  name: instana-agent
                  key: key
            - name: INSTANA_DOWNLOAD_KEY
              valueFrom:
                secretKeyRef:
                  name: instana-agent
                  key: downloadKey
                  optional: true
            - name: INSTANA_MVN_REPOSITORY_URL
              value: 'https://artifact-public.instana.io'
            - name: INSTANA_AGENT_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          securityContext:
            privileged: true
          volumeMounts:
            - name: dev
              mountPath: /dev
              mountPropagation: HostToContainer
            - name: run
              mountPath: /run
              mountPropagation: HostToContainer
            - name: var-run
              mountPath: /var/run
              mountPropagation: HostToContainer
            - name: sys
              mountPath: /sys
              mountPropagation: HostToContainer
            - name: var-log
              mountPath: /var/log
              mountPropagation: HostToContainer
            - name: var-lib
              mountPath: /var/lib
              mountPropagation: HostToContainer
            - name: var-data
              mountPath: /var/data
              mountPropagation: HostToContainer
            - name: machine-id
              mountPath: /etc/machine-id
            - name: configuration
              subPath: configuration.yaml
              mountPath: /root/configuration.yaml
          livenessProbe:
            httpGet:
              host: 127.0.0.1 # localhost because Pod has hostNetwork=true
              path: /status
              port: 42699
            initialDelaySeconds: 300 # startupProbe isnt available before K8s 1.16
            timeoutSeconds: 3
            periodSeconds: 10
            failureThreshold: 3
          resources:
            requests:
              memory: '512Mi'
              cpu: 0.5
            limits:
              memory: '768Mi'
              cpu: 1.5
          ports:
            - containerPort: 42699
        - name: leader-elector
          image: 'icr.io/instana/leader-elector:0.5.16'
          env:
            - name: INSTANA_AGENT_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          command:
            - '/busybox/sh'
            - '-c'
            - 'sleep 12 && /app/server --election=instana --http=localhost:42655 --id=\${INSTANA_AGENT_POD_NAME}'            
          resources:
            requests:
              cpu: 0.1
              memory: '64Mi'
          livenessProbe:
            httpGet: # Leader elector /health endpoint expects version 0.5.8 minimum, otherwise always returns 200 OK
              host: 127.0.0.1 # localhost because Pod has hostNetwork=true
              path: /health
              port: 42655
            initialDelaySeconds: 30
            timeoutSeconds: 3
            periodSeconds: 3
            failureThreshold: 3
          ports:
            - containerPort: 42655
      volumes:
        - name: dev
          hostPath:
            path: /dev
        - name: run
          hostPath:
            path: /run
        - name: var-run
          hostPath:
            path: /var/run
        - name: sys
          hostPath:
            path: /sys
        - name: var-log
          hostPath:
            path: /var/log
        - name: var-lib
          hostPath:
            path: /var/lib
        - name: var-data
          hostPath:
            path: /var/data
        - name: machine-id
          hostPath:
            path: /etc/machine-id
        - name: configuration
          configMap:
            name: instana-agent
EOF
