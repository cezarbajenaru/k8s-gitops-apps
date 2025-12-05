```
used tree in terminal
├── apps
│   ├── k9s
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── podinfo
│       ├── deployment.yaml
│       └── service.yaml
├── argo
│   ├── applications
│   │   └── apps.yaml
│   ├── bootstrap.yaml
│   └── install
│       ├── helm-argocd.yaml
│       ├── kustomization.yaml
│       └── values.yaml
└── readme.md

7 directories, 10 files
################# come back and recreate the whole tree everytime you add stuff like folders and files. Helps readability#####
```
step 0 - have the infrastructure done with Terraform

step 0.5

   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   kubectl get pods -n argocd



step 1 - apply bootstrap.yaml to install argo and link it to the cluster to the repo
   kubectl apply -f argo/bootstrap.yaml
      reapply bootstrap if you change repo links or anything else, otherwise Argo will work on initial boostrap setup and things will fail

After boostrap it automatically Upgrades the simple ArgoCD install created at at step 1  |  install/ will use it's own resources to configure itself TLS, RBAC, Autosync rules, server service type, Ingress, LoadBalancer(our case), Image updates, high availability configurations - ensures no drift, reproducability, version controlled platform config

step 2
   kubectl port-forward -n argocd svc/argocd-server 8089:443

step 3 - # username is admin and you get the generated pass though this command
   kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" | base64 -d && echo

Step 4 access you apps via adresses like IP:port


kubectl get applications -n argocd  # to gget what apps are running
then
kubectl describe application root-application -n argocd  # see what is working and what errors exist

step 5 - Security :

Adding github to known hosts:

# this could already be configured but you can try it / ArgoCD install already includes a known-hosts CM.

ssh-keyscan github.com > github_known_hosts
kubectl -n argocd create configmap argocd-ssh-known-hosts-cm \
  --from-file=ssh_known_hosts=github_known_hosts

# then hit this for Argo to restart with the above setting
kubectl -n argocd rollout restart deployment argocd-repo-server

# now we have to use the existing known hosts and use it for kubernetes configuration map

kubectl -n argocd create configmap argocd-ssh-known-hosts-cm \
  --from-file=ssh_known_hosts=github_known_hosts \
  -o yaml --dry-run=client | kubectl apply -f -


# this command will read the ssh key used for github and then use it in kubernetes secrets stored inside the cluster
kubectl -n argocd create secret generic repo-ssh-creds \
  --from-literal=sshPrivateKey="$(cat ~/.ssh/id_ed25519)"  # watch the name of the key to be the one used into github

# make Argo use the ssh key
kubectl -n argocd patch secret argocd-secret \
  --type merge \
  -p '{"stringData": {
        "repositories": "- url: git@github.com:cezarbajenaru/ekscourse_gitops_platform.git\n  sshPrivateKeySecret:\n    name: repo-ssh-creds\n    key: sshPrivateKey"
  }}'


kubectl -n argocd patch configmap argocd-cm \
  --type merge \
  -p '{"data": {
        "sshPrivateKeySecretName": "repo-ssh-creds"
  }}'


# restarts repository server
kubectl -n argocd rollout restart deployment argocd-repo-server

# with this command you restart the applications in the namespace
kubectl annotate application root-application -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite




In short, Argo applies only what is defined in argo/applications:
   Under argo/applications/ folder , apps/yaml file contains YAML code for ArgoCD to execute the apps that reside in main apps/aplication_folder_name/k8s_manifests.yaml (deployment, service etc)
In apps.yaml (the orchestrator) you can have a separate different repo for each app. In this file, YAMLs from different apps are separated with --- ( this does not break the YAML)

```
bootstrap.yaml
   ↓ (apply manually once)
ArgoCD minimal
   ↓ (reads from Git)
argo/applications/*   ← App-of-apps definitions
   ↓
argo/install/*        ← Full ArgoCD installation (self-managed)
apps/<app-name>/*     ← Application manifests (podinfo, etc.)

```


There are two common ways to manage ArgoCD installation in GitOps:
- Raw YAML manifests - not recomended - hard to upgade, no values overrides
- Helm Charts - THE WAY TO GO - configuration lives in values.yaml
```
argo/
└── install/
    ├── kustomization.yaml
    ├── helm-argocd.yaml  # defines a Helm release
    └── values.yaml

helm-argocd.yaml lets argo upgrade itself anytime with Helm chart updates

bootstrap.yaml
   ↓ (apply manually once)
ArgoCD minimal
   ↓ (reads from Git)
argo/applications/*   ← App-of-apps definitions
   ↓
argo/install/*        ← Full ArgoCD installation (self-managed)
apps/<app-name>/*     ← Application manifests (podinfo, etc.)
```

The best part of using Argo is that each team can use it's own repo and each time they commit something to that particular repo, Argo deploys it. It can be a dev cluster or even production. This is practically autonomous microservice deployments with a centralized platform that you can govern with allmost a single app like Argo. Argo uses git differences and deploys, does health checks and does canary or rollbacks

THere are no passwords, no kubectl for me

Discover Argo for multimple environments

dev cluster can be made fully automatic
staging cluster can be semi-automatic with approve in Argo UI manually
production cluster can be PR based + gating rules
Practically git each commit auto-transfers to real infrastructure and real users(production case)




