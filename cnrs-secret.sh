#!/bin/sh

kubectl apply -n tap-install -f - << EOF
apiVersion: v1
kind: Secret
metadata:
 name: cnrs-patch
stringData:
 patch.yaml: |
   #@ load("@ytt:overlay", "overlay")
   #@overlay/match by=overlay.subset({"kind":"ConfigMap","metadata":{"name":"config-logging","namespace":"knative-serving"}})
   ---
   data:
     #@overlay/match missing_ok=True
     loglevel.controller: "debug"
EOF
