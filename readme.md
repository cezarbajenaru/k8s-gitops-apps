```
$ tree
.
├── apps
│   └── podinfo
│       ├── deployment.yaml
│       └── service.yaml
├── argo
│   ├── applications
│   │   ├── apps.yaml
│   │   └── root-application.yaml
│   ├── bootstrap.yaml
│   └── install
│       ├── helm-argocd.yaml
│       ├── kustomization.yaml
│       ├── secrets.yaml
│       └── values.yaml
├── github_known_hosts
├── pforward.sh
└── readme.md

6 directories, 12 files
################# come back and recreate the whole tree everytime you add stuff like folders and files. Helps readability#####
```
step 0 - have the infrastructure done with Terraform - VPC, EKS, Nodegroup

#########################################################

step 0.5
Install the core ArgoCD at a minimal state ( no TLS, no autosync)

   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   kubectl get pods -n argocd

#########################################################

step 1 - apply bootstrap.yaml to install argo and link it to the cluster to the repo
   kubectl apply -f argo/bootstrap.yaml
      reapply bootstrap if you change repo links or anything else, otherwise Argo will work on initial boostrap setup and things will fail

After boostrap it automatically Upgrades the simple ArgoCD install created at at step 1  |  install/ will use it's own resources to configure itself TLS, RBAC, Autosync rules, server service type, Ingress, LoadBalancer(our case), Image updates, high availability configurations - ensures no drift, reproducability, version controlled platform config

#########################################################
Step 1.5
root-application does not have a declarative root-application.yaml file ( the acual configuration of Argocd in a worker node and namespace) so we have to create it as a file. If not, you cannot edit it's main repo target and will remain orphan/ If orphan then secrets cannot be used by it and connect to depo github and does not have it's own source of truth into GIT.
# use this command to export it into the repo. It must be edited out because it will have allot of automated configs inside. In this way we are altering the configmap in the correct way though this file declaration with a source of truth meaning, with GIT
# Delete everything under status:
kubectl get application root-application \
  -n argocd \
  -o yaml > argo/applications/root-application.yaml


#########################################################

step 2
   kubectl port-forward -n argocd svc/argocd-server 8089:443
  Go to localhost:8089 ( I stopped using 8080 because there is always something using it)

#########################################################

step 3 - # username is admin and you get the generated password though this command
   kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" | base64 -d && echo
#########################################################

Step 4 access you apps via adresses like IP:port

kubectl get applications -n argocd  # to gget what apps are running
then
kubectl describe application root-application -n argocd  # see what is working and what errors exist

#########################################################

step 5 - Security procedures:

ssh-keygen -t ed25519 -C "argocd@minikube" -f ~/.ssh/argocd_ssh_key -N ""
cat ~/.ssh/argocd_ssh_key.pub
Go to: GitHub Repo → Settings → Deploy Keys → Add Key
keep it read only, do not tick anything
go to .gitignore and add sercrets.yaml file so you do not commit it to git ( not production level but works in development locally )

# use the command to create the secret for Kubernetes with the name git-cezarbajenaru-ekscourse or whatever name
kubectl create secret generic git-cezarbajenaru-ekscourse \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url=git@github.com:cezarbajenaru/ekscourse_gitops_platform.git \
  --from-file=sshPrivateKey=/home/plasticmemory/.ssh/argocd_ssh_key

protect the local key
chmod 600 ~/.ssh/argocd_ssh_key

Add GitHub to known_hosts inside cluster (optional but correct)

ssh-keyscan github.com > github_known_hosts
kubectl create configmap argocd-ssh-known-hosts-cm \
  -n argocd \
  --from-file=ssh_known_hosts=github_known_hosts \
  -o yaml --dry-run=client | kubectl apply -f -

# restart repo-server to load the key
kubectl rollout restart deploy/argocd-repo-server -n argocd

#check if there is any drift
argocd repo list
kubectl logs deploy/argocd-repo-server -n argocd | grep ssh



##############################################

#show argo errors!
argocd app get root-application


#  restarts repository server
kubectl -n argocd rollout restart deployment argocd-repo-server

# forces a hard refresh / with this command you restart the applications in the namespace
kubectl annotate application root-application -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
############################################
############################################
############################################
# for podinfo to run
kubectl get svc -n default  # to get the services running  / default because the apps are running in default namespace, not the same namespace as the root-application(argocd)

kubectl port-forward svc/podinfo -n default 32080:80 #choose a port, if not 32080, can be anything else. Just not 8080 because something always uses it
# for Argo to run
kubectl port-forward -n argocd svc/argocd-server 8089:443
############################################
############################################
############################################

# reevaluate all connections
kubectl annotate app root-application -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl annotate app podinfo -n argocd argocd.argoproj.io/refresh=hard --overwrite

############################################

# login to argocd cli
# first port forward argocd CLI

#generates the password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

argocd login localhost:8089 --username admin --password <password> --insecure


# force redeploy
argocd app sync root-application #resync and name of app

# more debugging
argocd app list
argocd app delete nameofapp --cascade  #if there are pods broken and you want to get rid of the app completely ( do no forget to delete from scripts also)
argocd app get root-application  # get the errors regarding app and SSH problems 
argocd context

# secrets section
argocd repo list
kubectl get secrets -n argocd
kubectl apply -f argo/install/secrets.yaml


# Argo CLI
argocd context set localhost:8089

#creating already existent cluster Argo scripts for recreating ArgoCD configis

################################################



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




