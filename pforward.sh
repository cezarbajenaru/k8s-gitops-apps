#!/bin/bash
while true; do
  kubectl port-forward svc/argocd-server -n argocd 8080:443
  
  sleep 2
done
