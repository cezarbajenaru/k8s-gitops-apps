minikube was used in this project because it runs in a VM and has memory of what we create here
use kubectl to create the cluster and then point argocd installation that particular namespace - namespace that logically maps to the cluster 

```
$ tree
.
├── apps
│   ├── podinfo
│   │   ├── deployment.yaml
│   │   ├── ingress.yaml
│   │   └── service.yaml
│   └── wordpress
│       └── ingress.yaml
├── argo
│   ├── applications
│   │   ├── apps.yaml
│   │   └── root-application.yaml
│   ├── bootstrap.yaml
│   ├── ingress
│   │   └── argocd-ingress.yaml
│   └── install
│       ├── helm-argocd.yaml
│       ├── kustomization.yaml
│       ├── secrets.yaml
│       └── values.yaml
├── github_known_hosts
├── pforward.sh
└── readme.md

8 directories, 15 files
################# come back and recreate the whole tree everytime you add stuff like folders and files. Helps readability#####
```

# 1. Fresh start
minikube delete
minikube start
minikube addons enable ingress

# 2. Create namespace
kubectl create namespace argocd

# 3. Install ArgoCD (this creates the Application CRD you need)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.1/manifests/install.yaml

# 4. Wait (this takes 2-3 minutes, be patient)
kubectl get pods -n argocd -w
# Press Ctrl+C when all pods show "Running"

# 5. Apply your secrets
kubectl apply -f argo/install/secrets.yaml

# 6. Create SSH known hosts
kubectl create configmap argocd-ssh-known-hosts-cm --from-file=ssh_known_hosts=github_known_hosts -n argocd

# 7. Now you can apply helm-argocd.yaml (Application CRD exists now)
kubectl apply -f argo/install/helm-argocd.yaml

# 8. Bootstrap your apps
kubectl apply -f argo/bootstrap.yaml

# 9. Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 10. Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8089:80

http://localhost:8089

##########################################
Install the core ArgoCD at a minimal state ( no TLS, no autosync)

   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   kubectl get pods -n argocd

#########################################################


      reapply bootstrap if you change repo links or anything else, otherwise Argo will work on initial boostrap setup and things will fail

After boostrap it automatically Upgrades the simple ArgoCD install created at at step 1  |  install/ will use it's own resources to configure itself TLS, RBAC, Autosync rules, server service type, Ingress, LoadBalancer(our case), Image updates, high availability configurations - ensures no drift, reproducability, version controlled platform config

#########################################################

root-application does not have a declarative root-application.yaml file ( the acual configuration of Argocd in a worker node and namespace) so we have to create it as a file. If not, you cannot edit it's main repo target and will remain orphan/ If orphan then secrets cannot be used by it and cannot connect to repo on github and does not have it's own source of truth into GIT.
# use this command to export it into the repo. It must be edited out because it will have allot of automated configs inside. In this way we are altering the configmap in the correct way through this file declaration with a source of truth meaning(git repo is the source of truth)
# Delete everything under status:
kubectl get application root-application \
  -n argocd \
  -o yaml > argo/applications/root-application.yaml



you must login the actual ArgoCD CLI itself into the admin with the exactly same credentials used for the ArgoUI

argocd login localhost:8089 --insecure --username admin --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)


#######################################################

access you apps via adresses like IP:port

kubectl get applications -n argocd  # to gget what apps are running
then
kubectl describe application root-application -n argocd  # see what is working and what errors exist

#########################################################



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
What you must now add: Ingress Resources for each app you want to expose
these need to have their own scripts now ( wsl2 was with port forwarding )

Argo CD UI

WordPress UI

Podinfo app

Any future service

These are separate YAML manifests, like the one we just created for Argo CD.
```
(Client / Browser)
      |
      ↓
[ Ingress Controller ]  <-- ingress-nginx-main.yaml   Application (the main load balancer)
      |
      +── (host: argocd.local) → argocd-service
      |           ↑
      |    Ingress Rule: argocd-ingress.yaml
      |
      +── (host: podinfo.local) → podinfo-service
      |           ↑
      |    Ingress Rule: podinfo/ingress.yaml
      |
      +── (host: wordpress.local) → wordpress-service
                  ↑
          Ingress Rule: wordpress/ingress.yaml (not created yet)


```

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

TO DO AND LEARN



1. move secrets to SOPS ???
2. method to recreate Argo into an already existing and working cluster
      how do you create the files? The need to be exported to Yaml and modified to a clean declarative state without breaking



