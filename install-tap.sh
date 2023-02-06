#!/bin/sh

usage() {
  echo "$0 [prepare|install|expose|get [packagename]|list|update|delete]]"
}
prepare() {
  tanzu package repository add tanzu-tap-repository \
    --url $TAP_INSTALL_REGISTRY_HOSTNAME/tanzu-application-platform/tap-packages:$TAP_VERSION \
    --namespace $TAP_INSTALL_NS
  sleep 1
  tanzu package repository get tanzu-tap-repository --namespace $TAP_INSTALL_NS
  
  tanzu package available list --namespace $TAP_INSTALL_NS
}
install() {
if [ -f "$TAP_INSTALL_CONFIG" ]; then
  echo Found config $TAP_INSTALL_CONFIG
else
  echo Creating config $TAP_INSTALL_CONFIG
  tee $TAP_INSTALL_CONFIG <<EOF
accelerator:
  domain: $TAP_DOMAIN
  ingress:
    include: true
buildservice:
  exclude_dependencies: false
  kp_default_repository: $KP_REGISTRY_HOSTNAME/$KP_REPOSITORY_PATH
  kp_default_repository_secret:
    name: kp-default-repository-creds
    namespace: tap-install
  tanzunet_secret:
    name: tanzunet-repository-creds
    namespace: tap-install
ceip_policy_disclosed: true
cnrs:
  domain_name: $TAP_DOMAIN
  https_redirection: true
  ingress:
    external:
      namespace: tanzu-system-ingress
    internal:
      namespace: tanzu-system-ingress
  ingress_issuer: letsencrypt
contour:
  envoy:
    service:
      annotations:
        external-dns.alpha.kubernetes.io/hostname: "*.$TAP_DOMAIN"
      aws:
        LBType: nlb
  infrastructure_provider: aws
metadata_store:
  app_service_type: LoadBalancer
  ns_for_export_app_cert: "*"
ootb_supply_chain_basic:
  gitops:
    ssh_secret: ""
  registry:
    repository: $KP_REPOSITORY_PATH
    server: $KP_REGISTRY_HOSTNAME
ootb_supply_chain_testing_scanning:
  gitops:
    ssh_secret: ""
  registry:
    repository: $KP_REPOSITORY_PATH
    server: $KP_REGISTRY_HOSTNAME
  scanning:
    image:
      policy: image-scan-policy
    source:
      policy: scan-policy
package_overlays:
  - name: cnrs
    secrets:
      - name: cnrs-overlay-auto-tls
shared:
  ingress_domain: $INGRESS_DOMAIN
  ingress_issuer: letsencrypt
tap_gui:
  app_config:
    app:
      baseUrl: https://$TAP_GUI_FQDN
    auth:
      allowGuestAccess: false
      environment: $ENVIRONMENT
      providers:
        github:
          development:
            clientId: $GITHUB_CLIENT_ID
            clientSecret: $GITHUB_CLIENT_SECRET
      session:
        secret: custom session secret
    backend:
      baseUrl: https://$TAP_GUI_FQDN
      cors:
        origin: https://$TAP_GUI_FQDN
    integrations:
      github:
        - host: github.com
          token: $GITHUB_TOKEN
  ingressDomain: $INGRESS_DOMAIN
  ingressEnabled: true
  service_type: ClusterIP
  tls:
    namespace: tap-gui
    secretName: tap-gui-tls
EOF
fi
  tanzu package install tap --create-namespace --wait=true -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file $TAP_INSTALL_CONFIG -n $TAP_INSTALL_NS
  
  tanzu package installed get tap -n $TAP_INSTALL_NS
  tanzu package installed list -A
} 
expose() {
  kubectl apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
  namespace: cert-manager
spec:
  acme:
    email: $ACME_ACCOUNTT_EMAIL
    privateKeySecretRef:
      name: letsencrypt
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
    - http01:
        ingress:
          class: contour
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gui
  namespace: tap-gui
spec:
  commonName: $TAP_GUI_FQDN
  dnsNames:
  - $TAP_GUI_FQDN
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  secretName: tap-gui-tls
---
apiVersion: v1
kind: Secret
metadata:
  annotations:
    cert-manager.io/issuer-kind: ClusterIssuer
    cert-manager.io/issuer-name: letsencrypt
  name: tap-gui-tls
  namespace: tap-gui
type: kubernetes.io/tls
EOF
   
  sleep 1
  kubectl describe httpproxy -n tap-gui
  kubectl describe cr -n tap-gui
}
get() {
  if [ -z "$1" ]; then
    package=tap
  else
    package=$1
  fi
  tanzu package installed get -n $TAP_INSTALL_NS $package
}
list() {
  tanzu package installed list -n $TAP_INSTALL_NS
}
update() {
  tanzu package installed update -n $TAP_INSTALL_NS --version $TAP_VERSION --values-file $TAP_INSTALL_CONFIG tap
}
delete() {
  tanzu package installed delete -n $TAP_INSTALL_NS tap
}
case "$1" in
  install)
    prepare
    install
    expose
    exit
    ;;
  expose)
    expose
    ;;
  get)
    get $2
    exit
    ;;
  list)
    list
    exit
    ;;
  update)
    update
    exit
    ;;  
  delete) 
    delete
    kubectl get pvc -A
    exit
    ;;
  *)
    usage
    exit
    ;;
esac

